import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pvfd_epcr/services/encryption/android_keystore_provider.dart';
import 'package:pvfd_epcr/services/encryption/encryption_types.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.pvfd3.pvfd_epcr/encryption');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final provider = AndroidKeystoreProvider();
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  test('create and lookup expose verified protection only', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      expect(call.arguments, {'keyId': 'test-key'});
      return {'protection': 'trustedEnvironment'};
    });
    expect(
      (await provider.create('test-key')).protection,
      KeyProtection.trustedEnvironment,
    );
    expect((await provider.lookup('test-key')).id, 'test-key');
    expect(calls, ['createKey', 'lookupKey']);
  });
  for (final code in EncryptionError.values) {
    test('sanitized native error ${code.name}', () async {
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(
          code: code.name,
          message: 'DO NOT EXPOSE PROVIDER DETAILS',
          details: 'PRIVATE',
        );
      });
      try {
        await provider.lookup('test-key');
        fail('must throw');
      } on EncryptionException catch (error) {
        expect(error.code, code);
        expect(error.toString(), isNot(contains('PRIVATE')));
        expect(error.toString(), isNot(contains('PROVIDER')));
      }
    });
  }
  test('unknown native failure is sanitized', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'unknownPrivateDetails'),
    );
    await expectLater(
      provider.lookup('test-key'),
      throwsA(
        isA<EncryptionException>().having(
          (e) => e.code,
          'code',
          EncryptionError.cryptoFailure,
        ),
      ),
    );
  });
  test('missing platform never falls back or generates keys', () async {
    await expectLater(
      provider.lookup('test-key'),
      throwsA(
        isA<EncryptionException>().having(
          (e) => e.code,
          'code',
          EncryptionError.platformUnavailable,
        ),
      ),
    );
  });
  test('encrypt channel has no caller-supplied nonce', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'encrypt');
      expect((call.arguments as Map).containsKey('nonce'), isFalse);
      return {
        'nonce': Uint8List(12),
        'ciphertext': Uint8List(2),
        'tag': Uint8List(16),
      };
    });
    expect(
      (await provider.encrypt(
        'test-key',
        Uint8List(2),
        Uint8List(0),
      )).tag.length,
      16,
    );
  });
  test('malformed platform response fails closed', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {
        'nonce': Uint8List(1),
        'ciphertext': Uint8List(0),
        'tag': Uint8List(16),
      },
    );
    await expectLater(
      provider.encrypt('test-key', Uint8List(0), Uint8List(0)),
      throwsA(isA<EncryptionException>()),
    );
  });
  test(
    'invalid descriptor or non-map response is typed and sanitized',
    () async {
      for (final value in [<String, Object>{}, 'PRIVATE RESPONSE']) {
        messenger.setMockMethodCallHandler(channel, (_) async => value);
        await expectLater(
          provider.lookup('test-key'),
          throwsA(
            isA<EncryptionException>().having(
              (e) => e.code,
              'code',
              EncryptionError.cryptoFailure,
            ),
          ),
        );
      }
    },
  );
  test('decrypt adapter carries exact authenticated components', () async {
    final sealed = GcmSealedBytes(List.filled(12, 1), [
      2,
      3,
    ], List.filled(16, 4));
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'decrypt');
      final args = call.arguments as Map;
      expect(args['keyId'], 'test-key');
      expect(args['nonce'], sealed.nonce);
      expect(args['ciphertext'], sealed.ciphertext);
      expect(args['tag'], sealed.tag);
      expect(args['aad'], [5]);
      return {
        'bytes': Uint8List.fromList([6, 7]),
      };
    });
    expect(
      await provider.decrypt('test-key', sealed, Uint8List.fromList([5])),
      [6, 7],
    );
  });
}
