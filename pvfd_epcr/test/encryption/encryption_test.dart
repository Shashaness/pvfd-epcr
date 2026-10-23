import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pvfd_epcr/services/encryption/encrypted_envelope.dart';
import 'package:pvfd_epcr/services/encryption/encryption_types.dart';
import 'package:pvfd_epcr/services/encryption/record_encryption_service.dart';
import '../support/encryption/memory_crypto_provider.dart';

Matcher fails(EncryptionError code) =>
    throwsA(isA<EncryptionException>().having((e) => e.code, 'code', code));
Uint8List bytes(List<int> values) => Uint8List.fromList(values);
Uint8List hex(String value) => bytes([
  for (var i = 0; i < value.length; i += 2)
    int.parse(value.substring(i, i + 2), radix: 16),
]);
void main() {
  late MemoryCryptoProvider provider;
  late RecordEncryptionService service;
  setUp(() async {
    provider = MemoryCryptoProvider();
    await provider.create('synthetic-key-1');
    service = RecordEncryptionService(keys: provider, cipher: provider);
  });
  for (final entry in <String, Uint8List>{
    'synthetic': bytes(utf8.encode('SYNTHETIC RECORD: not a patient')),
    'empty': Uint8List(0),
    'large 1 MiB': bytes(List.generate(1024 * 1024, (i) => i % 256)),
    'Unicode': bytes(utf8.encode('Synthetic Δοκιμή 日本語 🩺\u0000')),
    'all binary values': bytes(List.generate(256, (i) => i)),
  }.entries) {
    test('round trip ${entry.key}', () async {
      final sealed = await service.encrypt('synthetic-key-1', entry.value);
      expect(await service.decrypt(sealed), entry.value);
      expect(EncryptedEnvelope.decode(sealed).sealed.tag, hasLength(16));
    });
  }
  test('different nonces with one key', () async {
    final first = await service.encrypt('synthetic-key-1', bytes([1, 2]));
    final second = await service.encrypt('synthetic-key-1', bytes([1, 2]));
    expect(
      EncryptedEnvelope.decode(first).sealed.nonce,
      isNot(EncryptedEnvelope.decode(second).sealed.nonce),
    );
  });
  for (final part in ['ciphertext', 'tag', 'nonce']) {
    test('reject $part tampering', () async {
      final sealed = await service.encrypt('synthetic-key-1', bytes([1, 2, 3]));
      final end = EncryptedEnvelope.fixedHeaderBytes + 'synthetic-key-1'.length;
      final offset = switch (part) {
        'ciphertext' => end + 12,
        'nonce' => end,
        _ => sealed.length - 1,
      };
      sealed[offset] ^= 1;
      await expectLater(
        service.decrypt(sealed),
        fails(EncryptionError.authenticationFailed),
      );
    });
  }
  test('external AAD is required and authenticated', () async {
    final sealed = await service.encrypt(
      'synthetic-key-1',
      bytes([1]),
      context: bytes([42]),
    );
    expect(await service.decrypt(sealed, context: bytes([42])), [1]);
    await expectLater(
      service.decrypt(sealed, context: bytes([43])),
      fails(EncryptionError.authenticationFailed),
    );
    await expectLater(
      service.decrypt(sealed),
      fails(EncryptionError.authenticationFailed),
    );
  });
  test(
    'key-id metadata authenticated even with same key under different id',
    () async {
      provider.material['synthetic-key-2'] =
          provider.material['synthetic-key-1']!;
      final sealed = await service.encrypt('synthetic-key-1', bytes([1]));
      sealed[16 + 'synthetic-key-1'.length - 1] = '2'.codeUnitAt(0);
      await expectLater(
        service.decrypt(sealed),
        fails(EncryptionError.authenticationFailed),
      );
    },
  );
  test('wrong key rejects', () async {
    final sealed = await service.encrypt('synthetic-key-1', bytes([1]));
    provider.material['synthetic-key-1'] = SecretKey(List.filled(32, 42));
    await expectLater(
      service.decrypt(sealed),
      fails(EncryptionError.authenticationFailed),
    );
  });
  test('missing keys never trigger creation', () async {
    final sealed = await service.encrypt('synthetic-key-1', bytes([1]));
    provider.material.clear();
    await expectLater(
      service.decrypt(sealed),
      fails(EncryptionError.keyMissing),
    );
    await expectLater(
      service.encrypt('synthetic-key-1', bytes([1])),
      fails(EncryptionError.keyMissing),
    );
    expect(provider.material, isEmpty);
  });
  test('invalidated keys fail closed', () async {
    final sealed = await service.encrypt('synthetic-key-1', bytes([1]));
    provider.invalidated.add('synthetic-key-1');
    await expectLater(
      service.decrypt(sealed),
      fails(EncryptionError.keyInvalidated),
    );
    await expectLater(
      service.encrypt('synthetic-key-1', bytes([1])),
      fails(EncryptionError.keyInvalidated),
    );
  });
  test('duplicate create cannot replace key', () async {
    final original = provider.material['synthetic-key-1'];
    await expectLater(
      provider.create('synthetic-key-1'),
      fails(EncryptionError.keyAlreadyExists),
    );
    expect(identical(original, provider.material['synthetic-key-1']), isTrue);
  });
  test('random failure and nonce reuse produce no ciphertext', () async {
    provider.failRandom = true;
    await expectLater(
      service.encrypt('synthetic-key-1', bytes([1])),
      fails(EncryptionError.randomFailure),
    );
    await expectLater(
      provider.create('another-key'),
      fails(EncryptionError.randomFailure),
    );
    provider.failRandom = false;
    provider.nonceSource = () => Uint8List(12);
    await service.encrypt('synthetic-key-1', bytes([1]));
    await expectLater(
      service.encrypt('synthetic-key-1', bytes([2])),
      fails(EncryptionError.nonceReuse),
    );
  });
  test('every truncation is rejected', () async {
    final sealed = await service.encrypt('synthetic-key-1', bytes([1, 2]));
    for (var length = 0; length < sealed.length; length++) {
      await expectLater(
        service.decrypt(bytes(sealed.sublist(0, length))),
        fails(EncryptionError.truncatedEnvelope),
      );
    }
  });
  test('unsupported version and algorithm have explicit errors', () async {
    final sealed = await service.encrypt('synthetic-key-1', bytes([1]));
    sealed[8] = 2;
    await expectLater(
      service.decrypt(sealed),
      fails(EncryptionError.unsupportedVersion),
    );
    sealed[8] = 1;
    sealed[9] = 2;
    await expectLater(
      service.decrypt(sealed),
      fails(EncryptionError.unsupportedAlgorithm),
    );
  });
  test(
    'magic, trailing bytes, impossible lengths and key ids rejected',
    () async {
      final sealed = await service.encrypt('synthetic-key-1', bytes([1]));
      await expectLater(
        service.decrypt(bytes([...sealed, 0])),
        fails(EncryptionError.malformedEnvelope),
      );
      await expectLater(
        service.decrypt(bytes(sealed)..[0] = 0),
        fails(EncryptionError.malformedEnvelope),
      );
      await expectLater(
        service.decrypt(bytes(sealed)..[16] = 255),
        fails(EncryptionError.invalidKeyId),
      );
      final badLength = bytes(sealed);
      ByteData.sublistView(badLength).setUint32(12, 0xffffffff);
      await expectLater(
        service.decrypt(badLength),
        fails(EncryptionError.payloadTooLarge),
      );
      final noKey = bytes(sealed);
      ByteData.sublistView(noKey).setUint16(10, 0);
      await expectLater(
        service.decrypt(noKey),
        fails(EncryptionError.invalidKeyId),
      );
      await expectLater(
        service.encrypt('../bad', bytes([1])),
        fails(EncryptionError.invalidKeyId),
      );
    },
  );
  test('codec has stable big-endian layout', () {
    final encoded = EncryptedEnvelope.encode(
      'k',
      GcmSealedBytes(List.filled(12, 1), [2, 3], List.filled(16, 4)),
    );
    expect(encoded.sublist(0, 17), [
      ...ascii.encode('PVFDECRY'),
      1,
      1,
      0,
      1,
      0,
      0,
      0,
      2,
      107,
    ]);
    expect(EncryptedEnvelope.decode(encoded).sealed.ciphertext, [2, 3]);
    expect(
      () => EncryptedEnvelope.encode('k', GcmSealedBytes([], [], [])),
      fails(EncryptionError.malformedEnvelope),
    );
  });
  test('caller mutation cannot change captured bytes or AAD', () async {
    final input = bytes([1, 2]);
    final context = bytes([3]);
    final pending = service.encrypt('synthetic-key-1', input, context: context);
    input.fillRange(0, input.length, 9);
    context[0] = 9;
    expect(await service.decrypt(await pending, context: bytes([3])), [1, 2]);
  });
  test('encryption layer makes no filesystem calls', () async {
    var calls = 0;
    final result = await IOOverrides.runZoned(
      () async {
        final sealed = await service.encrypt(
          'synthetic-key-1',
          bytes([1, 2, 3]),
        );
        return service.decrypt(sealed);
      },
      createFile: (_) {
        calls++;
        throw StateError('Unexpected file access');
      },
      createDirectory: (_) {
        calls++;
        throw StateError('Unexpected directory access');
      },
      createLink: (_) {
        calls++;
        throw StateError('Unexpected link access');
      },
    );
    expect(result, [1, 2, 3]);
    expect(calls, 0);
  });
  // NIST CAVP gcmEncryptExtIV256.rsp, PTlen=0, AADlen=0, Taglen=128, Count=0.
  test('NIST AES-256-GCM known-answer vector', () async {
    final cipher = AesGcm.with256bits();
    final key = SecretKey(
      hex('b52c505a37d78eda5dd34f20c22540ea1b58963cf8e5bf8ffa85f9f2492505b4'),
    );
    final nonce = hex('516c33929df5a3284ff463d7');
    final tag = hex('bdc1ac884d332457a1d2664f168c76f0');
    final sealed = await cipher.encrypt([], secretKey: key, nonce: nonce);
    expect(sealed.cipherText, isEmpty);
    expect(sealed.mac.bytes, tag);
    expect(
      await cipher.decrypt(
        SecretBox([], nonce: nonce, mac: Mac(tag)),
        secretKey: key,
      ),
      isEmpty,
    );
  });
  // Same official response file, PTlen=128/AADlen=128/Taglen=128, Count=0.
  test('NIST nonempty plaintext and AAD interoperability', () async {
    final algorithm = AesGcm.with256bits();
    final key = SecretKey(
      hex('92e11dcdaa866f5ce790fd24501f92509aacf4cb8b1339d50c9c1240935dd08b'),
    );
    final nonce = hex('ac93a1a6145299bde902f21a');
    final plaintext = hex('2d71bcfa914e4ac045b2aa60955fad24');
    final aad = hex('1e0889016f67601c8ebea4943bc23ad6');
    final ciphertext = hex('8995ae2e6df3dbf96fac7b7137bae67f');
    final tag = hex('eca5aa77d51d4a0a14d9c51e1da474ab');
    final sealed = await algorithm.encrypt(
      plaintext,
      secretKey: key,
      nonce: nonce,
      aad: aad,
    );
    expect(sealed.cipherText, ciphertext);
    expect(sealed.mac.bytes, tag);
    expect(
      await algorithm.decrypt(
        SecretBox(ciphertext, nonce: nonce, mac: Mac(tag)),
        secretKey: key,
        aad: aad,
      ),
      plaintext,
    );
  });
}
