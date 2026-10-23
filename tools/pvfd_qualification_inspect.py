#!/usr/bin/env python3
"""Read-only, target-pinned qualification inventory. No install/reset/decryption."""
import argparse
import json
import re
import shlex
import struct
import subprocess

TARGET='R95Y804S2PV'
PACKAGE='com.pvfd3.pvfd_epcr'
ROOTS=['app_flutter','files/pvfd_qualification_v1/documents']
LEGACY=re.compile(r'app_flutter/pcr_[A-Za-z0-9_-]+\.json(?:\.reserve|\.epcr-tmp-[A-Za-z0-9_-]+)?\Z')
HEX=re.compile(r'[0-9a-f]{64}\Z')
RECORD=re.compile(r'(?:app_flutter|files/pvfd_qualification_v1/documents)/protected_epcr_v1/[0-9a-f]{32}/(?:record\.epcr|committed\.marker|(?:rev_[0-9]{16}|\.stage_[0-9a-f]{32})/(?:local\.enc|recovery\.pvfdbak|pending\.json|\.uploaded))\Z')
TEMP=re.compile(r'app_flutter/protected_epcr_v1/\.key-tmp-[0-9a-f]{32}\Z')


class InspectionBlocked(Exception):
    pass


def metadata(data):
    value=json.loads(data)
    if not isinstance(value,dict) or set(value)!={'version','revision','operation','recoveryKeyId','recoverySha256'}:
        raise InspectionBlocked('invalid_queue_metadata')
    if type(value['version']) is not int or value['version']!=1 or type(value['revision']) is not int or not 1<=value['revision']<=9007199254740991:
        raise InspectionBlocked('invalid_queue_metadata')
    if value['operation'] not in ('save','delete') or not all(isinstance(value[k],str) and HEX.fullmatch(value[k]) for k in ('recoveryKeyId','recoverySha256')):
        raise InspectionBlocked('invalid_queue_metadata')
    return value


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--adb',default='adb')
    parser.add_argument('--serial',required=True,choices=[TARGET])
    args=parser.parse_args()
    def adb(*command):
        result=subprocess.run([args.adb,'-s',args.serial,*command],capture_output=True,timeout=30)
        if result.returncode or len(result.stdout)>1024*1024:
            raise InspectionBlocked('read_only_device_query_failed')
        return result.stdout
    def private(*command):
        return adb('shell',shlex.join(['run-as',PACKAGE,*command]))
    def prefix(path,count):
        return private('dd','if='+path,'bs=1','count='+str(count))
    try:
        if adb('get-state').strip()!=b'device': raise InspectionBlocked('device_not_authorized')
        if not adb('shell','pm','path',PACKAGE).strip().startswith(b'package:'):
            raise InspectionBlocked('expected_package_missing')
        if adb('shell','am','get-current-user').strip()!=b'0':
            raise InspectionBlocked('unexpected_active_profile')
        report={'target':TARGET,'package':PACKAGE,'mode':'read-only provisional inventory; final hash-bound reset token requires separately approved armed harness',
                'known_development_reset_files':[],'excluded_or_unknown_count':0,'encrypted_members':[]}
        for root in ROOTS:
            # Missing known roots are reported distinctly, never interpreted as a confirmed empty database.
            check=adb('shell',shlex.join(['run-as',PACKAGE,'sh','-c','test -d '+shlex.quote(root)+' && echo PRESENT || echo ABSENT']))
            if check.strip()==b'ABSENT':
                report[root]='directory absent';continue
            if check.strip()!=b'PRESENT': raise InspectionBlocked('private_metadata_unavailable')
            names=private('find',root,'-type','f').decode('utf-8').splitlines()
            links=private('find',root,'-type','l').decode('utf-8').splitlines()
            if links: raise InspectionBlocked('symlinks_require_review')
            if len(names)>2048: raise InspectionBlocked('inventory_limit')
            for name in sorted(names):
                if not (LEGACY.fullmatch(name) or RECORD.fullmatch(name) or TEMP.fullmatch(name)):
                    report['excluded_or_unknown_count']+=1;continue
                if name.startswith('app_flutter/'):
                    report['known_development_reset_files'].append(name)
                if not RECORD.fullmatch(name): continue # NEVER read legacy JSON contents.
                size=int(private('stat','-c','%s',name).strip())
                digest=private('sha256sum',name).decode().split()[0]
                if not HEX.fullmatch(digest): raise InspectionBlocked('invalid_hash_result')
                item={'path':name,'size':size,'sha256':digest}
                if name.endswith('/pending.json'):
                    if size>1024: raise InspectionBlocked('queue_metadata_limit')
                    item['queue']=metadata(prefix(name,size))
                elif name.endswith('/local.enc'):
                    fixed=prefix(name,16)
                    if len(fixed)!=16 or fixed[:8]!=b'PVFDECRY' or fixed[8:10]!=b'\x01\x01':
                        raise InspectionBlocked('invalid_local_envelope_header')
                    k,n=struct.unpack_from('>HI',fixed,10)
                    if not 1<=k<=64 or n>16777216 or size!=16+k+12+n+16:
                        raise InspectionBlocked('invalid_local_envelope_length')
                    header=prefix(name,16+k+12)
                    key=header[16:16+k].decode('ascii')
                    if not re.fullmatch(r'[A-Za-z0-9_-]{1,64}',key): raise InspectionBlocked('invalid_local_key_id')
                    item['header']={'magic':'PVFDECRY','version':1,'algorithm':1,'keyId':key,'ciphertextLength':n}
                elif name.endswith('/recovery.pvfdbak'):
                    header=prefix(name,480)
                    if len(header)!=480 or header[:8]!=b'PVFDBAK1' or header[8:16]!=b'\x01\x01\x00\x40\x01\x80\x0c\x10':
                        raise InspectionBlocked('invalid_recovery_header')
                    n=struct.unpack_from('>I',header,16)[0];identifier=header[20:84].decode('ascii')
                    if n>16777216 or size!=480+n+16 or not HEX.fullmatch(identifier):
                        raise InspectionBlocked('invalid_recovery_length_or_id')
                    item['header']={'magic':'PVFDBAK1','version':1,'algorithm':1,'keyId':identifier,'ciphertextLength':n}
                report['encrypted_members'].append(item)
        report['known_development_reset_file_count']=len(report['known_development_reset_files'])
        report['reset_confirmation']='NOT ISSUED: separate operator approval/armed harness plan required'
        print(json.dumps(report,indent=2))
        return 0
    except (InspectionBlocked,ValueError,UnicodeError,OSError,subprocess.SubprocessError):
        print('STOP: inspection unavailable or invalid; do not infer zero records, install, reset or print raw file contents.')
        return 2


if __name__=='__main__':
    raise SystemExit(main())
