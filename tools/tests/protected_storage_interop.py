#!/usr/bin/env python3
"""Synthetic committed-queue -> production Kotlin/JCA -> Python recovery test.

No Android deployment, operational private key, or second cipher implementation.
Requires a completed debug build's production Kotlin classes, JDK and stdlib JAR.
"""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from pvfd_recovery_format import decrypt, key_id


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--java-home',required=True)
    parser.add_argument('--kotlin-stdlib',required=True)
    args=parser.parse_args()
    root=Path(__file__).resolve().parents[2]
    compiled=root/'pvfd_epcr/build/app/tmp/kotlin-classes/debug'
    with tempfile.TemporaryDirectory(prefix='synthetic-protected-interop-',dir=Path(tempfile.gettempdir()).resolve()) as temp:
        output=Path(temp)
        key=rsa.generate_private_key(public_exponent=65537,key_size=3072) # Synthetic, memory-only.
        public=output/'public.der'
        public.write_bytes(key.public_key().public_bytes(serialization.Encoding.DER,serialization.PublicFormat.SubjectPublicKeyInfo))
        classpath=os.pathsep.join([str(compiled),args.kotlin_stdlib,str(output)])
        java=Path(args.java_home)/'bin/java'
        subprocess.run([str(Path(args.java_home)/'bin/javac'),'-cp',classpath,'-d',str(output),str(root/'tools/tests/NativeRecoveryEncrypt.java')],check=True)
        command=['flutter','test','test/protected_storage_interop_test.dart',
          '--dart-define=PVFD_TEST_PUBLIC_DER='+str(public), '--dart-define=PVFD_TEST_RECOVERY_ID='+key_id(key.public_key()),
          '--dart-define=PVFD_TEST_JAVA='+str(java),'--dart-define=PVFD_TEST_JAVA_CP='+classpath,'--dart-define=PVFD_TEST_OUTPUT='+str(output)]
        subprocess.run(command,cwd=root/'pvfd_epcr',check=True)
        assert decrypt((output/'backup.pvfdbak').read_bytes(),key)==(output/'original.bin').read_bytes()
        print('PASS: staged newest recovery revision -> production Kotlin/JCA -> independent Python; exact bytes after simulated local-key loss.')
    return 0


if __name__=='__main__':
    raise SystemExit(main())
