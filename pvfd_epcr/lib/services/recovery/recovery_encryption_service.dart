import 'dart:convert';
import 'package:flutter/services.dart';

enum RecoveryError {
  missingPublicKey,
  invalidPublicKey,
  invalidKeyId,
  keyIdMismatch,
  payloadTooLarge,
  malformedEnvelope,
  truncatedEnvelope,
  unsupportedVersion,
  unsupportedAlgorithm,
  randomFailure,
  platformUnavailable,
  cryptoFailure,
}

class RecoveryException implements Exception {
  const RecoveryException(this.code);
  final RecoveryError code;
  @override
  String toString() => 'RecoveryException(${code.name})';
}

/// Constructed only after native SPKI/RSA/fingerprint validation. No private key.
class PublicRecoveryKey {
  PublicRecoveryKey._(this.id, Uint8List der) : _der = Uint8List.fromList(der);
  final String id;
  final Uint8List _der;
}

abstract interface class RecoveryEncryptionService {
  Future<PublicRecoveryKey> loadPublicKey(Uint8List spkiDer, String expectedId);
  Future<Uint8List> encryptForRecovery(
    Uint8List plaintext,
    PublicRecoveryKey key,
  );
}

/// Passive, Android-only byte adapter; never called by storage or startup.
class AndroidRecoveryEncryptionService implements RecoveryEncryptionService {
  AndroidRecoveryEncryptionService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.pvfd3.pvfd_epcr/recovery');
  final MethodChannel _channel;
  Future<T> _invoke<T>(String method, Map<String, Object> args) async {
    try {
      final result = await _channel.invokeMethod<T>(method, args);
      if (result == null) {
        throw const RecoveryException(RecoveryError.cryptoFailure);
      }
      return result;
    } on MissingPluginException {
      throw const RecoveryException(RecoveryError.platformUnavailable);
    } on TypeError {
      throw const RecoveryException(RecoveryError.cryptoFailure);
    } on PlatformException catch (error) {
      final codes = RecoveryError.values.where((v) => v.name == error.code);
      throw RecoveryException(
        codes.isEmpty ? RecoveryError.cryptoFailure : codes.first,
      );
    }
  }

  @override
  Future<PublicRecoveryKey> loadPublicKey(
    Uint8List spkiDer,
    String expectedId,
  ) async {
    if (spkiDer.isEmpty) {
      throw const RecoveryException(RecoveryError.missingPublicKey);
    }
    if (spkiDer.length > 1024) {
      throw const RecoveryException(RecoveryError.invalidPublicKey);
    }
    RecoveryEnvelope.validateId(expectedId);
    final der = Uint8List.fromList(spkiDer);
    final value = await _invoke<Map<Object?, Object?>>('validatePublicKey', {
      'publicKeyDer': der,
      'keyId': expectedId,
    });
    if (value['keyId'] != expectedId) {
      throw const RecoveryException(RecoveryError.keyIdMismatch);
    }
    return PublicRecoveryKey._(expectedId, der);
  }

  @override
  Future<Uint8List> encryptForRecovery(
    Uint8List plaintext,
    PublicRecoveryKey key,
  ) async {
    if (plaintext.length > RecoveryEnvelope.maxPayload) {
      throw const RecoveryException(RecoveryError.payloadTooLarge);
    }
    final result = await _invoke<Uint8List>('encryptForRecovery', {
      'bytes': Uint8List.fromList(plaintext),
      'publicKeyDer': Uint8List.fromList(key._der),
      'keyId': key.id,
    });
    final envelope = RecoveryEnvelope.parse(result);
    if (envelope.keyId != key.id ||
        envelope.payloadLength != plaintext.length) {
      throw const RecoveryException(RecoveryError.cryptoFailure);
    }
    return Uint8List.fromList(result);
  }
}

/// Structural validation only. Python authenticates before returning plaintext.
class RecoveryEnvelope {
  RecoveryEnvelope._(this.keyId, this.payloadLength);
  static const maxPayload = 16 * 1024 * 1024;
  static const headerLength = 480;
  static final _id = RegExp(r'^[0-9a-f]{64}$');
  final String keyId;
  final int payloadLength;
  static void validateId(String value) {
    if (!_id.hasMatch(value) || value.length != 64) {
      throw const RecoveryException(RecoveryError.invalidKeyId);
    }
  }

  static RecoveryEnvelope parse(Uint8List bytes) {
    if (bytes.length > headerLength + maxPayload + 16) {
      throw const RecoveryException(RecoveryError.payloadTooLarge);
    }
    if (bytes.length < 20) {
      throw const RecoveryException(RecoveryError.truncatedEnvelope);
    }
    if (ascii.decode(bytes.sublist(0, 8), allowInvalid: true) != 'PVFDBAK1') {
      throw const RecoveryException(RecoveryError.malformedEnvelope);
    }
    if (bytes[8] != 1) {
      throw const RecoveryException(RecoveryError.unsupportedVersion);
    }
    if (bytes[9] != 1) {
      throw const RecoveryException(RecoveryError.unsupportedAlgorithm);
    }
    final data = ByteData.sublistView(bytes);
    if (data.getUint16(10) != 64 ||
        data.getUint16(12) != 384 ||
        bytes[14] != 12 ||
        bytes[15] != 16) {
      throw const RecoveryException(RecoveryError.malformedEnvelope);
    }
    final length = data.getUint32(16);
    if (length > maxPayload) {
      throw const RecoveryException(RecoveryError.payloadTooLarge);
    }
    if (bytes.length < headerLength + length + 16) {
      throw const RecoveryException(RecoveryError.truncatedEnvelope);
    }
    if (bytes.length != headerLength + length + 16) {
      throw const RecoveryException(RecoveryError.malformedEnvelope);
    }
    final id = ascii.decode(bytes.sublist(20, 84), allowInvalid: true);
    validateId(id);
    return RecoveryEnvelope._(id, length);
  }
}
