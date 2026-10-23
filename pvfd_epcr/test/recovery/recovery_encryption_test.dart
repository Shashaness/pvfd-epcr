import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pvfd_epcr/services/recovery/recovery_encryption_service.dart';
import 'development_public_key.dart';

Uint8List fixture(String id, int length) {
  final bytes = Uint8List(480 + length + 16);
  bytes.setAll(0, ascii.encode('PVFDBAK1'));
  bytes[8] = 1;
  bytes[9] = 1;
  bytes[14] = 12;
  bytes[15] = 16;
  ByteData.sublistView(bytes)
    ..setUint16(10, 64)
    ..setUint16(12, 384)
    ..setUint32(16, length);
  bytes.setAll(20, ascii.encode(id));
  return bytes;
}

Matcher fails(RecoveryError code) =>
    throwsA(isA<RecoveryException>().having((e) => e.code, 'code', code));
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.pvfd3.pvfd_epcr/recovery');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final service = AndroidRecoveryEncryptionService();
  setUp(() {
    messenger.setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments as Map;
      expect(args['publicKeyDer'], base64Decode(developmentSpkiBase64));
      expect(args['keyId'], developmentKeyId);
      if (call.method == 'validatePublicKey') {
        return {'keyId': developmentKeyId};
      }
      expect(call.method, 'encryptForRecovery');
      expect(args.keys.toSet(), {
        'keyId',
        'publicKeyDer',
        'bytes',
      }); // No AES key or caller IV.
      return fixture(developmentKeyId, (args['bytes'] as Uint8List).length);
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  test('explicit public provisioning and arbitrary byte encryption', () async {
    final key = await service.loadPublicKey(
      base64Decode(developmentSpkiBase64),
      developmentKeyId,
    );
    expect(key.id, developmentKeyId);
    for (final input in [
      Uint8List(0),
      Uint8List.fromList(utf8.encode('Synthetic Δ 🩺')),
      Uint8List.fromList(List.generate(256, (i) => i)),
    ]) {
      final envelope = RecoveryEnvelope.parse(
        await service.encryptForRecovery(input, key),
      );
      expect(envelope.payloadLength, input.length);
      expect(envelope.keyId, developmentKeyId);
    }
  });
  test('missing and invalid configurations never generate keys', () async {
    await expectLater(
      service.loadPublicKey(Uint8List(0), developmentKeyId),
      fails(RecoveryError.missingPublicKey),
    );
    await expectLater(
      service.loadPublicKey(Uint8List(1025), developmentKeyId),
      fails(RecoveryError.invalidPublicKey),
    );
    await expectLater(
      service.loadPublicKey(Uint8List(1), '../bad'),
      fails(RecoveryError.invalidKeyId),
    );
  });
  for (final code in RecoveryError.values) {
    test('safe native error ${code.name}', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async =>
            throw PlatformException(code: code.name, message: 'PRIVATE DETAIL'),
      );
      await expectLater(
        service.loadPublicKey(
          base64Decode(developmentSpkiBase64),
          developmentKeyId,
        ),
        fails(code),
      );
      expect(RecoveryException(code).toString(), isNot(contains('PRIVATE')));
    });
  }
  test('no platform means no fallback', () async {
    messenger.setMockMethodCallHandler(channel, null);
    await expectLater(
      service.loadPublicKey(
        base64Decode(developmentSpkiBase64),
        developmentKeyId,
      ),
      fails(RecoveryError.platformUnavailable),
    );
  });
  test(
    'wrong provisioning response and unknown failures are sanitized',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {'keyId': '0' * 64},
      );
      await expectLater(
        service.loadPublicKey(
          base64Decode(developmentSpkiBase64),
          developmentKeyId,
        ),
        fails(RecoveryError.keyIdMismatch),
      );
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'PRIVATE CODE'),
      );
      await expectLater(
        service.loadPublicKey(
          base64Decode(developmentSpkiBase64),
          developmentKeyId,
        ),
        fails(RecoveryError.cryptoFailure),
      );
    },
  );
  test('parser rejects every truncation and trailing bytes', () {
    final bytes = fixture(developmentKeyId, 4);
    for (var i = 0; i < bytes.length; i++) {
      expect(
        () => RecoveryEnvelope.parse(Uint8List.sublistView(bytes, 0, i)),
        fails(RecoveryError.truncatedEnvelope),
      );
    }
    expect(
      () => RecoveryEnvelope.parse(Uint8List.fromList([...bytes, 0])),
      fails(RecoveryError.malformedEnvelope),
    );
  });
  for (final entry in [
    (0, 0, RecoveryError.malformedEnvelope),
    (8, 2, RecoveryError.unsupportedVersion),
    (9, 2, RecoveryError.unsupportedAlgorithm),
    (14, 1, RecoveryError.malformedEnvelope),
    (20, 255, RecoveryError.invalidKeyId),
  ]) {
    test('parser rejects modified field ${entry.$1}', () {
      final bytes = fixture(developmentKeyId, 1)..[entry.$1] = entry.$2;
      expect(() => RecoveryEnvelope.parse(bytes), fails(entry.$3));
    });
  }
  test('reject declared oversize before allocating ciphertext', () {
    final bytes = fixture(developmentKeyId, 0);
    ByteData.sublistView(bytes).setUint32(16, RecoveryEnvelope.maxPayload + 1);
    expect(
      () => RecoveryEnvelope.parse(bytes),
      fails(RecoveryError.payloadTooLarge),
    );
  });
}
