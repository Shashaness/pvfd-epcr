import 'dart:typed_data';

import 'encrypted_envelope.dart';
import 'encryption_types.dart';

/// Byte-only encryption. Persistence and explicit key lifecycle belong to storage.
class RecordEncryptionService {
  const RecordEncryptionService({required this.keys, required this.cipher});
  final EncryptionKeyManager keys;
  final AesGcmProvider cipher;

  Future<Uint8List> encrypt(
    String keyId,
    Uint8List plaintext, {
    Uint8List? context,
  }) async {
    final header = EncryptedEnvelope.header(keyId, plaintext.length);
    final bytes = Uint8List.fromList(plaintext);
    final aad = EncryptedEnvelope.aad(
      header,
      Uint8List.fromList(context ?? const []),
    );
    await keys.lookup(keyId);
    final sealed = await cipher.encrypt(keyId, bytes, aad);
    if (sealed.ciphertext.length != bytes.length) {
      throw const EncryptionException(EncryptionError.cryptoFailure);
    }
    return EncryptedEnvelope.encode(keyId, sealed);
  }

  Future<Uint8List> decrypt(Uint8List envelope, {Uint8List? context}) async {
    final decoded = EncryptedEnvelope.decode(Uint8List.fromList(envelope));
    final aad = EncryptedEnvelope.aad(
      decoded.header,
      Uint8List.fromList(context ?? const []),
    );
    await keys.lookup(decoded.keyId);
    return cipher.decrypt(decoded.keyId, decoded.sealed, aad);
  }
}
