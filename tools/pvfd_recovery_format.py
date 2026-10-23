"""PVFD portable backup v1. No application storage, network or logging operations."""
import hashlib
import hmac
import re
import struct
from dataclasses import dataclass

from cryptography.exceptions import InvalidTag, UnsupportedAlgorithm
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

MAGIC = b'PVFDBAK1'
DOMAIN = b'PVFD/ePCR/recovery-backup/v1\x00'
MAX_PAYLOAD = 16 * 1024 * 1024
# magic/version/algorithm/key-ID length/wrapped-key length/nonce length/tag length/N
FIXED = struct.Struct('>8sBBHHBBI')
KEY_ID_LENGTH = 64
WRAPPED_LENGTH = 384
HEADER_LENGTH = FIXED.size + KEY_ID_LENGTH + WRAPPED_LENGTH + 12
MAX_ENVELOPE = HEADER_LENGTH + MAX_PAYLOAD + 16
KEY_ID = re.compile(r'[0-9a-f]{64}\Z')


class RecoveryError(Exception):
    """Only fixed, non-sensitive codes; never attach original exceptions/paths."""
    def __init__(self, code):
        self.code = code
        super().__init__(code)


def public_der(key):
    if not isinstance(key, rsa.RSAPublicKey) or key.key_size != 3072 or key.public_numbers().e != 65537:
        raise RecoveryError('invalid_public_key')
    return key.public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)


def key_id(key):
    return hashlib.sha256(public_der(key)).hexdigest()


def load_public(data, expected_id):
    if not isinstance(expected_id, str) or not KEY_ID.fullmatch(expected_id):
        raise RecoveryError('invalid_key_id')
    try:
        if data.startswith(b'-----BEGIN PUBLIC KEY-----'):
            key = serialization.load_pem_public_key(data)
            canonical = key.public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo)
            if data.strip() != canonical.strip():
                raise RecoveryError('invalid_public_key')
        else:
            key = serialization.load_der_public_key(data)
            if public_der(key) != data:
                raise RecoveryError('invalid_public_key')
        if not hmac.compare_digest(key_id(key), expected_id):
            raise RecoveryError('key_id_mismatch')
        return key
    except (ValueError, TypeError, UnsupportedAlgorithm):
        raise RecoveryError('invalid_public_key') from None


def load_private(data, passphrase):
    # Reject cleartext and alternate formats even if the library could read them.
    if not data.startswith(b'-----BEGIN ENCRYPTED PRIVATE KEY-----') or len(data) > 32768:
        raise RecoveryError('invalid_private_key')
    try:
        key = serialization.load_pem_private_key(data, password=passphrase)
    except (ValueError, TypeError, UnsupportedAlgorithm):
        raise RecoveryError('private_key_unlock_failed') from None
    if not isinstance(key, rsa.RSAPrivateKey):
        raise RecoveryError('invalid_private_key')
    public_der(key.public_key())
    return key


@dataclass(frozen=True)
class Envelope:
    key_id: str
    wrapped_key: bytes
    nonce: bytes
    header: bytes
    sealed: bytes


def parse(data):
    if len(data) > MAX_ENVELOPE:
        raise RecoveryError('oversized_payload')
    if len(data) < FIXED.size:
        raise RecoveryError('truncated_envelope')
    magic, version, algorithm, k, w, n, t, length = FIXED.unpack_from(data)
    if magic != MAGIC:
        raise RecoveryError('malformed_envelope')
    if version != 1:
        raise RecoveryError('unsupported_version')
    if algorithm != 1:
        raise RecoveryError('unsupported_algorithm')
    if (k, w, n, t) != (64, 384, 12, 16):
        raise RecoveryError('malformed_envelope')
    if length > MAX_PAYLOAD:
        raise RecoveryError('oversized_payload')
    expected = HEADER_LENGTH + length + 16
    if len(data) < expected:
        raise RecoveryError('truncated_envelope')
    if len(data) != expected:
        raise RecoveryError('trailing_bytes')
    try:
        identifier = data[20:84].decode('ascii')
    except UnicodeDecodeError:
        raise RecoveryError('invalid_key_id') from None
    if not KEY_ID.fullmatch(identifier):
        raise RecoveryError('invalid_key_id')
    return Envelope(identifier, data[84:468], data[468:480], data[:480], data[480:])


def decrypt(data, private_key):
    envelope = parse(data)
    if not hmac.compare_digest(envelope.key_id, key_id(private_key.public_key())):
        raise RecoveryError('key_id_mismatch')
    try:
        dek = private_key.decrypt(envelope.wrapped_key, padding.OAEP(
            mgf=padding.MGF1(hashes.SHA256()), algorithm=hashes.SHA256(), label=None))
    except ValueError:
        raise RecoveryError('invalid_wrapped_key') from None
    if len(dek) != 32:
        raise RecoveryError('invalid_wrapped_key')
    try:
        return AESGCM(dek).decrypt(envelope.nonce, envelope.sealed, DOMAIN + envelope.header)
    except InvalidTag:
        raise RecoveryError('authentication_failed') from None
