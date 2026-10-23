import 'dart:convert';
import 'dart:typed_data';

import 'encryption_types.dart';

/// Binary v1 codec; independent of JSON, storage, Flutter and patient schemas.
class EncryptedEnvelope {
  static const magic = <int>[0x50, 0x56, 0x46, 0x44, 0x45, 0x43, 0x52, 0x59];
  static const version = 1;
  static const algorithm = 1; // AES-256-GCM, 96-bit nonce, 128-bit tag.
  static const maxPayloadBytes = 16 * 1024 * 1024;
  static const fixedHeaderBytes = 16;
  static final _keyPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  static void validateKeyId(String keyId) {
    if (!_keyPattern.hasMatch(keyId)) {
      throw const EncryptionException(EncryptionError.invalidKeyId);
    }
  }

  static Uint8List header(String keyId, int length) {
    validateKeyId(keyId);
    if (length < 0 || length > maxPayloadBytes) {
      throw const EncryptionException(EncryptionError.payloadTooLarge);
    }
    final key = ascii.encode(keyId);
    final bytes = Uint8List(fixedHeaderBytes + key.length);
    bytes.setAll(0, magic);
    bytes[8] = version;
    bytes[9] = algorithm;
    ByteData.sublistView(bytes)
      ..setUint16(10, key.length)
      ..setUint32(12, length);
    bytes.setAll(fixedHeaderBytes, key);
    return bytes;
  }

  static Uint8List aad(Uint8List header, Uint8List context) {
    if (context.length > maxPayloadBytes) {
      throw const EncryptionException(EncryptionError.payloadTooLarge);
    }
    final length = ByteData(4)..setUint32(0, context.length);
    return (BytesBuilder(copy: false)
          ..add(ascii.encode('PVFD/ePCR/envelope/v1\x00'))
          ..add(header)
          ..add(length.buffer.asUint8List())
          ..add(context))
        .takeBytes();
  }

  static Uint8List encode(String keyId, GcmSealedBytes sealed) {
    if (sealed.nonce.length != 12 || sealed.tag.length != 16) {
      throw const EncryptionException(EncryptionError.malformedEnvelope);
    }
    return (BytesBuilder(copy: false)
          ..add(header(keyId, sealed.ciphertext.length))
          ..add(sealed.nonce)
          ..add(sealed.ciphertext)
          ..add(sealed.tag))
        .takeBytes();
  }

  static DecodedEnvelope decode(Uint8List bytes) {
    if (bytes.length < fixedHeaderBytes) {
      throw const EncryptionException(EncryptionError.truncatedEnvelope);
    }
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) {
        throw const EncryptionException(EncryptionError.malformedEnvelope);
      }
    }
    if (bytes[8] != version) {
      throw const EncryptionException(EncryptionError.unsupportedVersion);
    }
    if (bytes[9] != algorithm) {
      throw const EncryptionException(EncryptionError.unsupportedAlgorithm);
    }
    final view = ByteData.sublistView(bytes);
    final keyLength = view.getUint16(10);
    final length = view.getUint32(12);
    if (keyLength < 1 || keyLength > 64) {
      throw const EncryptionException(EncryptionError.invalidKeyId);
    }
    if (length > maxPayloadBytes) {
      throw const EncryptionException(EncryptionError.payloadTooLarge);
    }
    final headerEnd = fixedHeaderBytes + keyLength;
    final expected = headerEnd + 12 + length + 16;
    if (bytes.length < expected) {
      throw const EncryptionException(EncryptionError.truncatedEnvelope);
    }
    if (bytes.length != expected) {
      throw const EncryptionException(EncryptionError.malformedEnvelope);
    }
    final keyBytes = bytes.sublist(fixedHeaderBytes, headerEnd);
    if (keyBytes.any((b) => b > 127)) {
      throw const EncryptionException(EncryptionError.invalidKeyId);
    }
    final id = ascii.decode(keyBytes);
    validateKeyId(id);
    return DecodedEnvelope(
      id,
      Uint8List.fromList(bytes.sublist(0, headerEnd)),
      GcmSealedBytes(
        bytes.sublist(headerEnd, headerEnd + 12),
        bytes.sublist(headerEnd + 12, expected - 16),
        bytes.sublist(expected - 16),
      ),
    );
  }
}

class DecodedEnvelope {
  const DecodedEnvelope(this.keyId, this.header, this.sealed);
  final String keyId;
  final Uint8List header;
  final GcmSealedBytes sealed;
}
