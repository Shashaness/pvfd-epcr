"""Synthetic keys/data only. No operational fixtures or ePCR access."""
import contextlib
import io
import os
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from pvfd_recovery_format import (RecoveryError, MAGIC, FIXED, DOMAIN, MAX_PAYLOAD,
                                 MAX_ENVELOPE, decrypt, parse, key_id, load_private, load_public)
from pvfd_generate_recovery_keys import generate, main as generate_main
from pvfd_recovery_io import atomic_new, read_regular
from pvfd_recover import recover, main as recover_main


def test_envelope(public_key, plaintext, dek=None, nonce=None):
    """Independent test producer; production Python utility only decrypts."""
    dek = os.urandom(32) if dek is None else dek
    nonce = os.urandom(12) if nonce is None else nonce
    wrapped = public_key.encrypt(dek, padding.OAEP(mgf=padding.MGF1(hashes.SHA256()),
                                                  algorithm=hashes.SHA256(), label=None))
    header = FIXED.pack(MAGIC, 1, 1, 64, 384, 12, 16, len(plaintext)) + key_id(public_key).encode('ascii') + wrapped + nonce
    return header + AESGCM(dek).encrypt(nonce, plaintext, DOMAIN + header)


class RecoveryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.key = rsa.generate_private_key(public_exponent=65537, key_size=3072)
        cls.other = rsa.generate_private_key(public_exponent=65537, key_size=3072)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=Path(tempfile.gettempdir()).resolve())
        self.root = Path(self.temp.name)
        self.addCleanup(self.temp.cleanup)

    def assertCode(self, code, fn):
        with self.assertRaises(RecoveryError) as caught:
            fn()
        self.assertEqual(caught.exception.code, code)

    def test_empty_unicode_binary_large(self):
        for data in [b'', 'Synthetic Δ 日本語 🩺'.encode(), bytes(range(256)), b'x' * (1024 * 1024)]:
            self.assertEqual(decrypt(test_envelope(self.key.public_key(), data), self.key), data)

    def test_wrong_key(self):
        self.assertCode('key_id_mismatch', lambda: decrypt(test_envelope(self.key.public_key(), b'x'), self.other))

    def test_tampering(self):
        original = test_envelope(self.key.public_key(), b'SYNTHETIC')
        for offset, expected in [(84, 'invalid_wrapped_key'), (468, 'authentication_failed'),
                                 (480, 'authentication_failed'), (len(original)-1, 'authentication_failed'),
                                 (20, 'key_id_mismatch')]:
            value = bytearray(original)
            value[offset] = ord('0') if offset == 20 and value[offset] != ord('0') else value[offset] ^ 1
            self.assertCode(expected, lambda: decrypt(bytes(value), self.key))

    def test_metadata_valid_changed_length_is_authenticated(self):
        original = bytearray(test_envelope(self.key.public_key(), b'SYNTHETIC'))
        # Keep parsing valid by changing N and inserting a ciphertext byte.
        struct.pack_into('>I', original, 16, len(b'SYNTHETIC') + 1)
        original.insert(480, 0)
        self.assertCode('authentication_failed', lambda: decrypt(bytes(original), self.key))

    def test_all_truncations(self):
        data = test_envelope(self.key.public_key(), b'x')
        for end in range(len(data)):
            self.assertCode('truncated_envelope', lambda: parse(data[:end]))

    def test_versions_algorithms_lengths_trailing(self):
        original = test_envelope(self.key.public_key(), b'x')
        for offset, value, code in [(0, 0, 'malformed_envelope'), (8, 2, 'unsupported_version'),
                                    (9, 2, 'unsupported_algorithm'), (10, 1, 'malformed_envelope'),
                                    (14, 16, 'malformed_envelope'), (20, 255, 'invalid_key_id')]:
            modified = bytearray(original); modified[offset] = value
            self.assertCode(code, lambda: parse(bytes(modified)))
        self.assertCode('trailing_bytes', lambda: parse(original + b'x'))
        oversized = bytearray(original)
        struct.pack_into('>I', oversized, 16, MAX_PAYLOAD + 1)
        self.assertCode('oversized_payload', lambda: parse(bytes(oversized)))
        self.assertCode('oversized_payload', lambda: parse(b'x' * (MAX_ENVELOPE + 1)))

    def test_wrapped_key_wrong_length_plaintext(self):
        self.assertCode('invalid_wrapped_key', lambda: decrypt(test_envelope(self.key.public_key(), b'x', dek=b'x'*16), self.key))

    def test_public_key_parameters_fingerprint_canonical(self):
        public = self.key.public_key()
        der = public.public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)
        self.assertEqual(key_id(load_public(der, key_id(public))), key_id(public))
        self.assertCode('key_id_mismatch', lambda: load_public(der, '0'*64))
        self.assertCode('invalid_public_key', lambda: load_public(der + b'x', key_id(public)))
        self.assertCode('invalid_public_key', lambda: load_public(b'garbage', key_id(public)))
        weak = rsa.generate_private_key(public_exponent=65537, key_size=2048).public_key()
        self.assertCode('invalid_public_key', lambda: key_id(weak))
        self.assertCode('invalid_key_id', lambda: load_public(der, '../bad'))

    def test_key_generation_encrypted_private_permissions_no_overwrite(self):
        private, public = self.root/'custody'/'private.pem', self.root/'provisioning'/'public.pem'
        phrase = 'synthetic-test-custody-phrase-only'
        identifier = generate(private, public, phrase, phrase)
        encoded = private.read_bytes()
        self.assertTrue(encoded.startswith(b'-----BEGIN ENCRYPTED PRIVATE KEY-----'))
        loaded = load_private(encoded, phrase.encode())
        self.assertEqual(key_id(loaded.public_key()), identifier)
        self.assertEqual(key_id(load_public(public.read_bytes(), identifier)), identifier)
        self.assertEqual(private.stat().st_mode & 0o777, 0o600)
        self.assertEqual(private.parent.stat().st_mode & 0o777, 0o700)
        self.assertCode('output_exists', lambda: generate(private, public, phrase, phrase))
        self.assertEqual(private.read_bytes(), encoded)
        self.assertCode('private_key_unlock_failed', lambda: load_private(encoded, b'wrong-passphrase'))
        clear = loaded.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption())
        self.assertCode('invalid_private_key', lambda: load_private(clear, phrase.encode()))

    def test_passphrase_confirmation_and_path_separation(self):
        priv, pub = self.root/'priv'/'key.pem', self.root/'pub'/'key.pem'
        self.assertCode('passphrase_policy', lambda: generate(priv, pub, 'short', 'short'))
        self.assertCode('passphrase_mismatch', lambda: generate(priv, pub, 'a'*20, 'b'*20))
        self.assertCode('separate_key_directories_required', lambda: generate(priv, priv, 'a'*20, 'a'*20))
        self.assertFalse(priv.exists())

    def test_multiple_files_recursive_and_verify_only(self):
        source = self.root/'input'; (source/'nested').mkdir(parents=True)
        (source/'one.pvfdbak').write_bytes(test_envelope(self.key.public_key(), b'one'))
        (source/'nested'/'two.pvfdbak').write_bytes(test_envelope(self.key.public_key(), b'two'))
        output = self.root/'output'
        self.assertEqual(recover(source, output, self.key, recursive=True, verify_only=True), (2, 0))
        self.assertFalse(output.exists())
        self.assertEqual(recover(source, output, self.key, recursive=True), (2, 0))
        self.assertEqual((output/'nested'/'two.pvfdbak.recovered').read_bytes(), b'two')
        self.assertEqual((output/'one.pvfdbak.recovered').stat().st_mode & 0o777, 0o600)
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(recover(source, output, self.key, recursive=True), (0, 2))
        self.assertEqual((output/'one.pvfdbak.recovered').read_bytes(), b'one')

    def test_authentication_failure_never_writes_plaintext(self):
        source = self.root/'bad.pvfdbak'; payload = bytearray(test_envelope(self.key.public_key(), b'PRIVATE_SYNTHETIC'))
        payload[-1] ^= 1; source.write_bytes(payload)
        output = self.root/'output'
        with contextlib.redirect_stdout(io.StringIO()) as log:
            self.assertEqual(recover(source, output, self.key), (0, 1))
        self.assertEqual(list(output.iterdir()), [])
        self.assertNotIn('PRIVATE_SYNTHETIC', log.getvalue())
        self.assertNotIn(str(source), log.getvalue())

    def test_interrupted_write_no_published_output_or_temp(self):
        output = self.root/'safe'/'record.recovered'
        with patch('pvfd_recovery_io.os.fsync', side_effect=OSError('private error detail')):
            self.assertCode('output_write_failed', lambda: atomic_new(output, b'SYNTHETIC'))
        self.assertFalse(output.exists())
        self.assertEqual(list(output.parent.iterdir()), [])

    def test_traversal_symlinks_and_conflicts(self):
        output = self.root/'output'; output.mkdir(mode=0o700)
        self.assertCode('unsafe_path', lambda: atomic_new(output/'..'/'escape', b'x'))
        outside = self.root/'outside'; outside.mkdir(mode=0o700)
        (output/'link').symlink_to(outside, target_is_directory=True)
        self.assertCode('unsafe_or_unavailable_path', lambda: atomic_new(output/'link'/'escape', b'x'))
        (output/'file').symlink_to(outside/'target')
        self.assertCode('output_exists', lambda: atomic_new(output/'file', b'x'))
        self.assertFalse((outside/'target').exists())
        source = self.root/'input'; source.mkdir()
        (source/'unsafe.pvfdbak').symlink_to(self.root/'anything')
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(recover(source, output, self.key), (0, 1))
        self.assertCode('overlapping_paths', lambda: recover(source, source/'child', self.key))
        self.assertCode('unsafe_path', lambda: read_regular(output/'..'/'anything', 10))

    def test_read_bound_and_fifo(self):
        path = self.root/'large'; path.write_bytes(b'1234')
        self.assertCode('oversized_input', lambda: read_regular(path, 3))
        fifo = self.root/'fifo'; os.mkfifo(fifo)
        self.assertCode('unsafe_input_file', lambda: read_regular(fifo, 10))

    def test_generator_cli_confirmation_and_safe_summary(self):
        private, public = self.root/'custody'/'private.pem', self.root/'public'/'public.pem'
        args = ['--private-output', str(private), '--public-output', str(public)]
        with patch('pvfd_generate_recovery_keys.prompt', side_effect=['synthetic-passphrase-only', 'different-phrase']), contextlib.redirect_stdout(io.StringIO()) as log:
            self.assertEqual(generate_main(args), 2)
        self.assertFalse(private.exists())
        self.assertNotIn('synthetic-passphrase-only', log.getvalue())
        with patch('pvfd_generate_recovery_keys.prompt', return_value='synthetic-passphrase-only'), contextlib.redirect_stdout(io.StringIO()) as log:
            self.assertEqual(generate_main(args), 0)
        self.assertIn('Public key ID:', log.getvalue())
        self.assertNotIn(str(private), log.getvalue())
        self.assertNotIn('synthetic-passphrase-only', log.getvalue())

    def test_refuse_private_key_in_checkout(self):
        checkout = self.root/'checkout'; checkout.mkdir(); (checkout/'.git').mkdir()
        self.assertCode('private_key_in_source_checkout', lambda: generate(
            checkout/'keys'/'private.pem', self.root/'public'/'public.pem', 'a'*20, 'a'*20))
        self.assertFalse((checkout/'keys'/'private.pem').exists())

    def test_nonrecursive_selection_and_verify_failure_no_output(self):
        source = self.root/'input'; (source/'nested').mkdir(parents=True)
        (source/'one.pvfdbak').write_bytes(test_envelope(self.key.public_key(), b'one'))
        (source/'nested'/'two.pvfdbak').write_bytes(test_envelope(self.key.public_key(), b'two'))
        self.assertEqual(recover(source, None, self.key, verify_only=True), (1, 0))
        bad = bytearray((source/'one.pvfdbak').read_bytes()); bad[-1] ^= 1
        (source/'one.pvfdbak').write_bytes(bad)
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(recover(source, self.root/'never-created', self.key, verify_only=True), (0, 1))
        self.assertFalse((self.root/'never-created').exists())

    def test_cli_verify_only_and_wrong_passphrase_exit(self):
        phrase = 'synthetic-unlock-only'
        private = self.root/'test-private.pem'
        private.write_bytes(self.key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                                  serialization.BestAvailableEncryption(phrase.encode())))
        source = self.root/'test.pvfdbak'; source.write_bytes(test_envelope(self.key.public_key(), b'SYNTHETIC'))
        arguments = ['--private-key', str(private), '--input', str(source), '--verify-only']
        with patch('pvfd_recover.prompt', return_value=phrase), contextlib.redirect_stdout(io.StringIO()) as log:
            self.assertEqual(recover_main(arguments), 0)
        self.assertIn('Processed: 1; failed: 0', log.getvalue())
        with patch('pvfd_recover.prompt', return_value='wrong'), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(recover_main(arguments), 2)


if __name__ == '__main__':
    unittest.main()
