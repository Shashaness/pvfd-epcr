import 'dart:typed_data';

/// Safe codes only: never attach provider exceptions or record content.
enum EncryptionError {
  malformedEnvelope,
  truncatedEnvelope,
  unsupportedVersion,
  unsupportedAlgorithm,
  invalidKeyId,
  payloadTooLarge,
  keyMissing,
  keyInvalidated,
  keyUnavailable,
  keyAlreadyExists,
  authenticationFailed,
  randomFailure,
  nonceReuse,
  keyExhausted,
  platformUnavailable,
  cryptoFailure,
}

class EncryptionException implements Exception {
  const EncryptionException(this.code);
  final EncryptionError code;
  @override
  String toString() => 'EncryptionException(${code.name})';
}

enum KeyProtection {
  software,
  trustedEnvironment,
  strongBox,
  hardwareBacked,
  unknown,
}

class EncryptionKeyInfo {
  const EncryptionKeyInfo(this.id, this.protection);
  final String id;
  final KeyProtection protection;
}

abstract interface class EncryptionKeyManager {
  /// Explicit provisioning only. An existing identifier must never be replaced.
  Future<EncryptionKeyInfo> create(String keyId);
  Future<EncryptionKeyInfo> lookup(String keyId);
}

class GcmSealedBytes {
  GcmSealedBytes(List<int> nonce, List<int> ciphertext, List<int> tag)
    : nonce = Uint8List.fromList(nonce),
      ciphertext = Uint8List.fromList(ciphertext),
      tag = Uint8List.fromList(tag);
  final Uint8List nonce;
  final Uint8List ciphertext;
  final Uint8List tag;
}

abstract interface class AesGcmProvider {
  /// Provider generates/reserves the nonce. Callers cannot supply an encrypt IV.
  Future<GcmSealedBytes> encrypt(String keyId, Uint8List bytes, Uint8List aad);
  Future<Uint8List> decrypt(String keyId, GcmSealedBytes sealed, Uint8List aad);
}
