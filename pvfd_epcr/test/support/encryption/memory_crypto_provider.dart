// TEST ONLY. Deterministic keys/nonces must never enter production code.
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:pvfd_epcr/services/encryption/encryption_types.dart';

class MemoryCryptoProvider implements EncryptionKeyManager, AesGcmProvider {
  final Map<String, SecretKey> material = {};
  final Set<String> invalidated = {};
  final Set<String> used = {};
  int nextNonce = 0;
  bool failRandom = false;
  Uint8List Function()? nonceSource;
  final algorithm = AesGcm.with256bits();
  @override
  Future<EncryptionKeyInfo> create(String keyId) async {
    if (material.containsKey(keyId)) {
      throw const EncryptionException(EncryptionError.keyAlreadyExists);
    }
    if (failRandom) {
      throw const EncryptionException(EncryptionError.randomFailure);
    }
    material[keyId] = SecretKey(
      List.generate(32, (i) => (i + material.length) % 256),
    );
    return lookup(keyId);
  }

  @override
  Future<EncryptionKeyInfo> lookup(String keyId) async {
    if (invalidated.contains(keyId)) {
      throw const EncryptionException(EncryptionError.keyInvalidated);
    }
    if (!material.containsKey(keyId)) {
      throw const EncryptionException(EncryptionError.keyMissing);
    }
    return EncryptionKeyInfo(keyId, KeyProtection.software);
  }

  @override
  Future<GcmSealedBytes> encrypt(
    String keyId,
    Uint8List bytes,
    Uint8List aad,
  ) async {
    await lookup(keyId);
    if (failRandom) {
      throw const EncryptionException(EncryptionError.randomFailure);
    }
    final nonce =
        nonceSource?.call() ??
        (Uint8List(12)..buffer.asByteData().setUint64(4, nextNonce++));
    if (nonce.length != 12) {
      throw const EncryptionException(EncryptionError.randomFailure);
    }
    if (!used.add('$keyId:${nonce.join(',')}')) {
      throw const EncryptionException(EncryptionError.nonceReuse);
    }
    final box = await algorithm.encrypt(
      bytes,
      secretKey: material[keyId]!,
      nonce: nonce,
      aad: aad,
    );
    return GcmSealedBytes(box.nonce, box.cipherText, box.mac.bytes);
  }

  @override
  Future<Uint8List> decrypt(
    String keyId,
    GcmSealedBytes sealed,
    Uint8List aad,
  ) async {
    await lookup(keyId);
    try {
      return Uint8List.fromList(
        await algorithm.decrypt(
          SecretBox(
            sealed.ciphertext,
            nonce: sealed.nonce,
            mac: Mac(sealed.tag),
          ),
          secretKey: material[keyId]!,
          aad: aad,
        ),
      );
    } on SecretBoxAuthenticationError {
      throw const EncryptionException(EncryptionError.authenticationFailed);
    }
  }
}
