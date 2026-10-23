#!/usr/bin/env python3
"""Explicit synthetic Android -> Python interoperability test; no operational keys."""
import argparse
import contextlib
import io
import secrets
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding
from pvfd_generate_recovery_keys import generate
from pvfd_recovery_format import RecoveryError, decrypt, key_id, load_private, parse
from pvfd_recover import recover

PACKAGE = 'com.pvfd3.pvfd_epcr'


def run_test(device):
    def adb(*args, data=None):
        result = subprocess.run(['adb', '-s', device, *args], input=data, capture_output=True)
        if result.returncode:
            raise RecoveryError('adb_operation_failed')
        return result.stdout
    if adb('get-state').strip() != b'device':
        raise RecoveryError('device_not_authorized')
    run = 'm42a_test_' + uuid.uuid4().hex
    remote = 'cache/' + run
    with tempfile.TemporaryDirectory(prefix='pvfd-m42a-synthetic-', dir=Path(tempfile.gettempdir()).resolve()) as temporary:
        root = Path(temporary)
        phrase = secrets.token_urlsafe(48) # Test-only passphrase, never printed or sent to Android.
        private = root/'custody'/'private.pem'; public = root/'provisioning'/'public.pem'
        generate(private, public, phrase, phrase)
        key = load_private(private.read_bytes(), phrase.encode())
        der = key.public_key().public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)
        try:
            adb('shell', 'run-as', PACKAGE, 'mkdir', remote)
            adb('shell', '-T', 'run-as', PACKAGE, 'dd', 'of=' + remote + '/public.der', data=der)
            if adb('exec-out', 'run-as', PACKAGE, 'cat', remote + '/public.der') != der:
                raise RecoveryError('public_key_transfer_failed')
            status = adb('shell', 'am', 'instrument', '-w', '-r', '-e', 'run', run, '-e', 'keyId', key_id(key.public_key()),
                         PACKAGE + '.test/' + PACKAGE + '.RecoverySelfTestInstrumentation')
            if b'PASS:' not in status or b'FAIL:' in status or b'INSTRUMENTATION_CODE: -1' not in status:
                for line in status.decode('ascii', errors='replace').splitlines():
                    if line.startswith('INSTRUMENTATION_RESULT: result=FAIL:'):
                        print(line) # Fixed native codes/stages only; no raw exception message.
                raise RecoveryError('android_self_test_failed')
            source = root/'encrypted'; source.mkdir(mode=0o700)
            expected = [b'{"synthetic":true,"note":"TEST ONLY"}', b'',
                        '{"synthetic":true,"note":"Δ 日本語 🩺"}'.encode(),
                        bytes(range(256))*4096, bytes(range(256))]
            expected += [expected[0], expected[0]]
            aes_keys, nonces = set(), set()
            for index, plaintext in enumerate(expected):
                payload = adb('exec-out', 'run-as', PACKAGE, 'cat', remote + f'/case_{index}.pvfdbak')
                if decrypt(payload, key) != plaintext:
                    raise RecoveryError('interop_byte_mismatch')
                envelope = parse(payload)
                dek = key.decrypt(envelope.wrapped_key, padding.OAEP(mgf=padding.MGF1(hashes.SHA256()), algorithm=hashes.SHA256(), label=None))
                if len(dek) != 32:
                    raise RecoveryError('interop_key_size')
                aes_keys.add(dek); nonces.add(envelope.nonce)
                (source/f'case_{index}.pvfdbak').write_bytes(payload)
            if len(aes_keys) != 7 or len(nonces) != 7:
                raise RecoveryError('interop_randomness_check_failed')
            # Recovery runs on the workstation after synthetic device-key deletion;
            # neither the recovery function nor format has a Keystore dependency.
            with contextlib.redirect_stdout(io.StringIO()):
                if recover(source, None, key, verify_only=True) != (7, 0):
                    raise RecoveryError('interop_verify_failed')
                if recover(source, root/'recovered', key) != (7, 0):
                    raise RecoveryError('interop_directory_failed')
            for index, plaintext in enumerate(expected):
                if (root/'recovered'/f'case_{index}.pvfdbak.recovered').read_bytes() != plaintext:
                    raise RecoveryError('interop_output_mismatch')
            print('PASS: Android -> Python: 7 exact byte matches, empty/Unicode/1 MiB/binary, distinct 256-bit DEKs and nonces, verify-only, directory recovery, isolated Keystore-key loss.')
        finally:
            # Fixed test-only names, no recursive cleanup and no clinical file access.
            for name in ['public.der'] + [f'case_{index}.pvfdbak' for index in range(7)]:
                adb('shell', 'run-as', PACKAGE, 'rm', '-f', remote + '/' + name)
            adb('shell', 'run-as', PACKAGE, 'rmdir', remote)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True)
    args = parser.parse_args()
    try:
        run_test(args.device)
        return 0
    except RecoveryError as error:
        print('FAIL: synthetic Android interoperability: ' + error.code)
        return 1
    except OSError:
        print('FAIL: synthetic Android interoperability: local_io_failed')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
