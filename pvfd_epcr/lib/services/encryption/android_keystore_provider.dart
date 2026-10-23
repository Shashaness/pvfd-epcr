import 'package:flutter/services.dart';

import 'encrypted_envelope.dart';
import 'encryption_types.dart';

/// Android-only adapter. Key bytes never cross this channel.
class AndroidKeystoreProvider implements EncryptionKeyManager, AesGcmProvider {
  AndroidKeystoreProvider({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('com.pvfd3.pvfd_epcr/encryption');
  final MethodChannel _channel;

  Future<Map<Object?, Object?>> _invoke(
    String method,
    Map<String, Object> args,
  ) async {
    try {
      final value = await _channel.invokeMapMethod<Object?, Object?>(
        method,
        args,
      );
      if (value == null) {
        throw const EncryptionException(EncryptionError.cryptoFailure);
      }
      return value;
    } on TypeError {
      throw const EncryptionException(EncryptionError.cryptoFailure);
    } on MissingPluginException {
      throw const EncryptionException(EncryptionError.platformUnavailable);
    } on PlatformException catch (error) {
      // Discard provider messages/details; only known, safe codes may escape.
      final code = EncryptionError.values.where((e) => e.name == error.code);
      throw EncryptionException(
        code.isEmpty ? EncryptionError.cryptoFailure : code.first,
      );
    }
  }

  Future<EncryptionKeyInfo> _key(String method, String id) async {
    EncryptedEnvelope.validateKeyId(id);
    final value = await _invoke(method, {'keyId': id});
    final level = value['protection'];
    if (level is! String) {
      throw const EncryptionException(EncryptionError.cryptoFailure);
    }
    final protection = KeyProtection.values.where((p) => p.name == level);
    return EncryptionKeyInfo(
      id,
      protection.isEmpty ? KeyProtection.unknown : protection.first,
    );
  }

  Future<int> usedOperations(String keyId) async {
    EncryptedEnvelope.validateKeyId(keyId);
    final value = await _invoke('keyUsage', {'keyId': keyId});
    final count = value['used'];
    if (count is! int || count < 0 || count > 65536) {
      throw const EncryptionException(EncryptionError.keyUnavailable);
    }
    return count;
  }

  @override
  Future<EncryptionKeyInfo> create(String keyId) => _key('createKey', keyId);
  @override
  Future<EncryptionKeyInfo> lookup(String keyId) => _key('lookupKey', keyId);

  @override
  Future<GcmSealedBytes> encrypt(
    String keyId,
    Uint8List bytes,
    Uint8List aad,
  ) async {
    EncryptedEnvelope.header(keyId, bytes.length);
    final value = await _invoke('encrypt', {
      'keyId': keyId,
      'bytes': Uint8List.fromList(bytes),
      'aad': Uint8List.fromList(aad),
    });
    if (value['nonce'] is! Uint8List ||
        value['ciphertext'] is! Uint8List ||
        value['tag'] is! Uint8List) {
      throw const EncryptionException(EncryptionError.cryptoFailure);
    }
    final sealed = GcmSealedBytes(
      value['nonce'] as Uint8List,
      value['ciphertext'] as Uint8List,
      value['tag'] as Uint8List,
    );
    if (sealed.nonce.length != 12 ||
        sealed.tag.length != 16 ||
        sealed.ciphertext.length != bytes.length) {
      throw const EncryptionException(EncryptionError.cryptoFailure);
    }
    return sealed;
  }

  @override
  Future<Uint8List> decrypt(
    String keyId,
    GcmSealedBytes sealed,
    Uint8List aad,
  ) async {
    EncryptedEnvelope.encode(keyId, sealed); // Validate boundary dimensions.
    final value = await _invoke('decrypt', {
      'keyId': keyId,
      'nonce': Uint8List.fromList(sealed.nonce),
      'ciphertext': Uint8List.fromList(sealed.ciphertext),
      'tag': Uint8List.fromList(sealed.tag),
      'aad': Uint8List.fromList(aad),
    });
    final bytes = value['bytes'];
    if (bytes is! Uint8List || bytes.length != sealed.ciphertext.length) {
      throw const EncryptionException(EncryptionError.cryptoFailure);
    }
    return bytes;
  }
}
