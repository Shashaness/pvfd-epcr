#!/usr/bin/env python3
"""Explicit offline key ceremony. Never invoked at import or application startup."""
import argparse
import getpass
import warnings
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from pvfd_recovery_format import RecoveryError, key_id
from pvfd_recovery_io import atomic_new, directory, ensure_absent


def generate(private_path, public_path, passphrase, confirmation):
    # Policy floor is a guardrail, not a substitute for high-entropy custody.
    if len(passphrase) < 16 or len(passphrase.encode('utf-8')) > 1024 or not passphrase.strip():
        raise RecoveryError('passphrase_policy')
    if passphrase != confirmation:
        raise RecoveryError('passphrase_mismatch')
    private_path, public_path = Path(private_path), Path(public_path)
    if private_path.absolute() == public_path.absolute() or private_path.parent.absolute() == public_path.parent.absolute():
        raise RecoveryError('separate_key_directories_required')
    # Keep even encrypted private keys outside source checkouts.
    for ancestor in (private_path.absolute().parent, *private_path.absolute().parents):
        if (ancestor / '.git').exists():
            raise RecoveryError('private_key_in_source_checkout')
    for path in (private_path, public_path):
        with directory(path.parent, create=True, private=True):
            pass
        ensure_absent(path)
    key = rsa.generate_private_key(public_exponent=65537, key_size=3072)
    private = key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                               serialization.BestAvailableEncryption(passphrase.encode('utf-8')))
    public = key.public_key().public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo)
    # No pair-wide transaction: a failure can leave an encrypted private key only.
    # Never delete/replace an existing key to try to repair that state.
    atomic_new(private_path, private)
    atomic_new(public_path, public)
    return key_id(key.public_key())


def prompt(text):
    with warnings.catch_warnings():
        warnings.simplefilter('error', getpass.GetPassWarning) # No echoed-input fallback.
        return getpass.getpass(text)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--private-output', required=True)
    parser.add_argument('--public-output', required=True)
    args = parser.parse_args(argv)
    try:
        identifier = generate(args.private_output, args.public_output,
                              prompt('Recovery private-key passphrase: '), prompt('Confirm passphrase: '))
        print('Key generation complete. Public key ID: ' + identifier)
        return 0
    except RecoveryError as error:
        print('Key generation failed: ' + error.code)
    except (OSError, ValueError, EOFError, KeyboardInterrupt, getpass.GetPassWarning):
        print('Key generation failed: operation_failed')
    except Exception:
        print('Key generation failed: operation_failed')
    return 2


if __name__ == '__main__':
    raise SystemExit(main())
