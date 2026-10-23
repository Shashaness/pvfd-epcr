import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pvfd_epcr/services/epcr_storage_service.dart';
import 'package:pvfd_epcr/data/storage/protected_storage_crypto.dart';
import 'package:pvfd_epcr/services/encryption/encrypted_envelope.dart';
import 'package:pvfd_epcr/services/encryption/encryption_types.dart';
import 'support/protected_storage.dart';

void main() {
  late Directory dir;
  late SyntheticStorageEnvironment environment;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('synthetic_protected_');
    environment = SyntheticStorageEnvironment();
  });
  tearDown(() async => dir.delete(recursive: true));
  test(
    'encrypted create read update delete and durable tombstone queue',
    () async {
      final service = environment.storage();
      final file = await service.create(dir, {
        'patient': {'firstName': 'SYNTHETIC SECRET'},
        'future': 42,
      });
      expect((await service.read(file))['future'], 42);
      await service.save(file, {'future': 43});
      expect((await service.read(file))['future'], 43);
      await service.delete(file);
      expect(await service.list(dir), isEmpty);
      await expectLater(service.read(file), throwsA(anything));
      expect((await service.pendingUploads(dir)).single.operation, 'delete');
    },
  );
  test(
    'no plaintext in local files, temporary files or queue metadata',
    () async {
      const secret = 'SYNTHETIC_PRIVATE_NARRATIVE_Δ_日本語';
      final service = environment.storage(
        beforeReplace: (temporary, destination) async {
          expect(
            utf8.decode(await temporary.readAsBytes(), allowMalformed: true),
            isNot(contains(secret)),
          );
        },
      );
      await service.create(dir, {
        'patient': {'firstName': secret},
        'epcrNumber': 'IDENTIFYING-REPORT',
      });
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) {
          final bytes = await entity.readAsBytes();
          expect(
            utf8.decode(bytes, allowMalformed: true),
            isNot(contains(secret)),
          );
          expect(entity.path, isNot(contains('IDENTIFYING-REPORT')));
          if (entity.path.endsWith('pending.json')) {
            final map = jsonDecode(utf8.decode(bytes)) as Map;
            expect(map.keys.toSet(), {
              'version',
              'revision',
              'operation',
              'recoveryKeyId',
              'recoverySha256',
            });
          }
        }
      }
    },
  );
  test('serialization failure never touches committed data', () async {
    final service = environment.storage();
    final file = await service.create(dir, {'value': 1});
    expect(() => service.save(file, {'invalid': Object()}), throwsA(anything));
    expect((await service.read(file))['value'], 1);
  });
  test(
    'interrupted atomic replacement retains prior complete revision',
    () async {
      final file = await environment.storage().create(dir, {'value': 1});
      final failing = environment.storage(
        beforeReplace: (temporary, target) async {
          expect(
            (await temporary.readAsBytes()).take(8),
            EncryptedEnvelope.magic,
          );
          throw const FileSystemException('synthetic interruption');
        },
      );
      await expectLater(failing.save(file, {'value': 2}), throwsA(anything));
      expect((await environment.storage().read(file))['value'], 1);
      expect(
        (await environment.storage().pendingUploads(dir)).single.revision,
        1,
      );
    },
  );
  test(
    'interrupted backup staging and recovery encryption never acknowledge save',
    () async {
      final file = await environment.storage().create(dir, {'value': 1});
      final failing = environment.storage(
        beforeRecoveryStage: () async =>
            throw const FileSystemException('synthetic staging interruption'),
      );
      await expectLater(failing.save(file, {'value': 2}), throwsA(anything));
      environment.failRecovery = true;
      await expectLater(
        environment.storage().save(file, {'value': 3}),
        throwsA(anything),
      );
      environment.failRecovery = false;
      expect((await environment.storage().read(file))['value'], 1);
      expect(
        (await environment.storage().pendingUploads(dir)).single.revision,
        1,
      );
    },
  );
  test(
    'concurrent rapid updates and instances preserve requested order/snapshots',
    () async {
      final file = await environment.storage().create(dir, {'value': -1});
      final gate = Completer<void>();
      final entered = Completer<void>();
      final blocked = environment.storage(
        beforeReplace: (_, _) async {
          entered.complete();
          await gate.future;
        },
      );
      final first = blocked.save(file, {'value': 0});
      await entered.future;
      final mutable = <String, dynamic>{'value': 1};
      final second = environment.storage().save(file, mutable);
      mutable['value'] = 999;
      gate.complete();
      await Future.wait([first, second]);
      expect((await environment.storage().read(file))['value'], 1);
      await Future.wait(
        List.generate(
          20,
          (i) => environment.storage().save(file, {'value': i}),
        ),
      );
      expect((await environment.storage().read(file))['value'], 19);
      final queue = await environment.storage().pendingUploads(dir);
      expect(queue.length, 1);
      expect(queue.single.revision, 23);
      expect(
        (await file.parent.list().toList()).whereType<Directory>().length,
        1,
      );
    },
  );
  test(
    'queue survives restart, stale upload cannot acknowledge newest revision',
    () async {
      final service = environment.storage();
      final file = await service.create(dir, {'value': 1});
      final prior = (await service.pendingUploads(dir)).single;
      final bytes = await service.readPendingUpload(dir, prior);
      expect(bytes, isNotNull);
      await service.save(file, {'value': 2});
      final restarted = environment.storage();
      expect(await restarted.acknowledgeUpload(dir, prior), false);
      expect(await restarted.readPendingUpload(dir, prior), isNull);
      final newest = (await restarted.pendingUploads(dir)).single;
      expect(newest.objectKey, isNot(prior.objectKey));
      expect(await restarted.acknowledgeUpload(dir, newest), true);
      expect(await environment.storage().pendingUploads(dir), isEmpty);
      expect((await restarted.read(file))['value'], 2);
    },
  );
  test(
    'corrupted ciphertext blocks reads, lists and writes; never fallback',
    () async {
      final service = environment.storage();
      final file = await service.create(dir, {'value': 1});
      final pending = (await service.pendingUploads(dir)).single;
      final local = File('${pending.file.parent.path}/local.enc');
      final bytes = await local.readAsBytes();
      bytes[bytes.length - 1] ^= 1;
      await local.writeAsBytes(bytes, flush: true);
      await expectLater(
        service.read(file),
        throwsA(isA<EncryptionException>()),
      );
      await expectLater(service.list(dir), throwsA(anything));
      await expectLater(service.save(file, {'value': 2}), throwsA(anything));
      expect(await local.readAsBytes(), bytes);
    },
  );
  test('backup tampering cannot be queued or silently overwritten', () async {
    final service = environment.storage();
    final file = await service.create(dir, {'value': 1});
    final pending = (await service.pendingUploads(dir)).single;
    final bytes = await pending.file.readAsBytes();
    bytes[bytes.length - 1] ^= 1;
    await pending.file.writeAsBytes(bytes);
    await expectLater(service.pendingUploads(dir), throwsA(anything));
    await expectLater(service.save(file, {'value': 2}), throwsA(anything));
  });
  test(
    'missing/inaccessible key retains ciphertext and queue artifacts',
    () async {
      final service = environment.storage();
      final file = await service.create(dir, {'value': 1});
      final keys = Map.of(environment.keys.material);
      environment.keys.material.clear();
      await expectLater(
        service.read(file),
        throwsA(isA<EncryptionException>()),
      );
      await expectLater(service.save(file, {'value': 2}), throwsA(anything));
      expect(environment.keys.material, isEmpty);
      environment.keys.material.addAll(keys);
      environment.keys.invalidated.addAll(keys.keys);
      await expectLater(
        service.read(file),
        throwsA(isA<EncryptionException>()),
      );
      environment.keys.invalidated.clear();
      expect((await service.read(file))['value'], 1);
    },
  );
  test(
    'rotate before limit; old key retained; exhausted key rotates without loss',
    () async {
      final service = environment.storage();
      final first = await service.create(dir, {'value': 1});
      final original = environment.keys.material.keys.single;
      environment.countOverride = 60000;
      final second = await service.create(dir, {'value': 2});
      expect(environment.keys.material.length, 2);
      expect(environment.keys.material, contains(original));
      expect((await service.read(first))['value'], 1);
      expect((await service.read(second))['value'], 2);
      environment.countOverride = 65536;
      await service.save(second, {'value': 3});
      expect(environment.keys.material.length, 3);
      expect((await service.read(first))['value'], 1);
    },
  );
  test(
    'failed rotation and missing key index cannot silently reset keys',
    () async {
      final service = environment.storage();
      final file = await service.create(dir, {'value': 1});
      environment.countOverride = 60000;
      environment.keys.failRandom = true;
      await expectLater(service.save(file, {'value': 2}), throwsA(anything));
      expect(environment.keys.material.length, 1);
      expect((await service.read(file))['value'], 1);
      environment.keys.failRandom = false;
      await File('${dir.path}/protected_epcr_v1/keys.json').delete();
      await expectLater(service.save(file, {'value': 2}), throwsA(anything));
      expect(environment.keys.material.length, 1);
      expect((await service.read(file))['value'], 1);
    },
  );
  test(
    'legacy plaintext rejected explicitly without reading or migration',
    () async {
      final legacy = File('${dir.path}/pcr_legacy.json');
      await legacy.writeAsString('{synthetic legacy}');
      final service = environment.storage();
      await expectLater(
        service.list(dir),
        throwsA(
          isA<ProtectedStorageException>().having(
            (e) => e.code,
            'code',
            'legacyPlaintextRejected',
          ),
        ),
      );
      await expectLater(service.create(dir, {}), throwsA(anything));
      expect(() => service.read(legacy), throwsA(anything));
      expect(await legacy.readAsString(), '{synthetic legacy}');
      expect(environment.keys.material, isEmpty);
    },
  );
  test(
    'uncommitted stage is retained/diagnosed, never promoted after restart',
    () async {
      final service = environment.storage();
      final file = await service.create(dir, {'value': 1});
      final stage = Directory(
        '${file.parent.path}/.stage_00000000000000000000000000000000',
      );
      await stage.create();
      await File('${stage.path}/local.enc').writeAsBytes([1, 2, 3]);
      expect(await environment.storage().orphanCount(dir), 1);
      expect((await environment.storage().read(file))['value'], 1);
      expect(await stage.exists(), true);
    },
  );
  test(
    'directory sync failure is not acknowledged and retains prior record',
    () async {
      final service = environment.storage();
      final file = await service.create(dir, {'value': 1});
      environment.durability.fail = true;
      await expectLater(service.save(file, {'value': 2}), throwsA(anything));
      environment.durability.fail = false;
      expect((await service.read(file))['value'], 1);
    },
  );
  test(
    'development reset needs armed debug build, exact confirmation, preserves keys and unrelated files',
    () async {
      final disabled = environment.storage();
      expect(() => disabled.prepareDevelopmentReset(dir), throwsA(anything));
      final service = environment.storage(allowDevelopmentReset: true);
      await service.create(dir, {'value': 1});
      final index = File('${dir.path}/protected_epcr_v1/keys.json');
      final keyData = await index.readAsString();
      final legacy = File('${dir.path}/pcr_dev.json');
      await legacy.writeAsString('SYNTHETIC');
      final unrelated = File('${dir.path}/unrelated.txt');
      await unrelated.writeAsString('KEEP');
      final plan = await service.prepareDevelopmentReset(dir);
      expect(plan.relativeFiles.length, plan.fileCount);
      expect(plan.relativeDirectories.length, plan.directoryCount);
      expect(plan.relativeFiles, contains('pcr_dev.json'));
      expect(plan.relativeFiles.any((p) => p.contains('keys.json')), false);
      expect(plan.relativeFiles.any((p) => p.contains('KEEP')), false);
      await expectLater(
        service.executeDevelopmentReset(plan, confirmation: 'yes'),
        throwsA(anything),
      );
      await service.executeDevelopmentReset(
        plan,
        confirmation:
            'DELETE CONFIRMED DEVELOPMENT DATA ONLY ${plan.confirmationToken}',
      );
      expect(await legacy.exists(), false);
      expect(await unrelated.readAsString(), 'KEEP');
      expect(await index.readAsString(), keyData);
      expect(environment.keys.material.length, 1);
      expect(await service.list(dir), isEmpty);
    },
  );
  test('development reset refuses unknown files and changed plans', () async {
    final service = environment.storage(allowDevelopmentReset: true);
    final file = await service.create(dir, {'value': 1});
    final plan = await service.prepareDevelopmentReset(dir);
    await service.save(file, {'value': 2});
    await expectLater(
      service.executeDevelopmentReset(
        plan,
        confirmation:
            'DELETE CONFIRMED DEVELOPMENT DATA ONLY ${plan.confirmationToken}',
      ),
      throwsA(anything),
    );
    await File('${file.parent.path}/unrelated.bin').writeAsBytes([1]);
    await expectLater(service.prepareDevelopmentReset(dir), throwsA(anything));
    expect((await service.read(file))['value'], 2);
  });
  test(
    'post-publication sync failure retains a complete queued revision and retries safely',
    () async {
      final service = environment.storage();
      final file = await service.create(dir, {'value': 1});
      environment.durability.failOnCall =
          environment.durability.calls +
          2; // Stage sync succeeds; parent sync fails.
      await expectLater(service.save(file, {'value': 2}), throwsA(anything));
      expect(
        (await service.read(file))['value'],
        2,
      ); // Visible but never falsely acknowledged.
      expect((await service.pendingUploads(dir)).single.revision, 2);
      await service.save(file, {'value': 3});
      expect((await service.read(file))['value'], 3);
      expect((await service.pendingUploads(dir)).single.revision, 3);
    },
  );
  test(
    'ambiguous create retry binds the same controller-owned record',
    () async {
      final service = environment.storage();
      final snapshot = {
        'epcrNumber': 'TEST-RETRY',
        'appRecordId': 'TEST-RETRY',
        'value': 1,
      };
      environment.durability.failOnCall = 3;
      await expectLater(
        service.create(dir, snapshot, idFactory: () => 'TEST-RETRY'),
        throwsA(anything),
      );
      final file = await service.create(
        dir,
        snapshot,
        idFactory: () => 'TEST-RETRY',
      );
      expect((await service.list(dir)).length, 1);
      expect((await service.read(file))['value'], 1);
    },
  );
  test(
    'authenticated metadata changes cannot hide a live record as deleted',
    () async {
      final service = environment.storage();
      final file = await service.create(dir, {'value': 1});
      final upload = (await service.pendingUploads(dir)).single;
      final metadata = File('${upload.file.parent.path}/pending.json');
      final value =
          jsonDecode(await metadata.readAsString()) as Map<String, dynamic>;
      value['operation'] = 'delete';
      await metadata.writeAsString(jsonEncode(value));
      await expectLater(
        service.read(file),
        throwsA(isA<EncryptionException>()),
      );
      await expectLater(service.list(dir), throwsA(anything));
    },
  );
  test(
    'missing committed generation is an error rather than an empty database',
    () async {
      final service = environment.storage();
      final file = await service.create(dir, {'value': 1});
      final upload = (await service.pendingUploads(dir)).single;
      await upload.file.parent.delete(
        recursive: true,
      ); // Synthetic data-loss injection only.
      await expectLater(service.list(dir), throwsA(anything));
      expect(await File('${file.parent.path}/committed.marker').exists(), true);
    },
  );
  test('protected persistence works with all HTTP clients forbidden', () async {
    await HttpOverrides.runZoned(() async {
      final service = environment.storage();
      final file = await service.create(dir, {'offline': true});
      await service.save(file, {'offline': true, 'revision': 2});
      expect((await service.read(file))['revision'], 2);
      expect((await service.pendingUploads(dir)).length, 1);
    }, createHttpClient: (_) => throw StateError('Network is forbidden'));
  });
  test('PMH handles null malformed legacy and preferred clinical values', () {
    for (final value in [
      null,
      42,
      'bad',
      {},
      [42],
    ]) {
      expect(
        readPmh({
          'clinical': {'pmh': value},
        }),
        isEmpty,
      );
    }
    expect(
      readPmh({
        'incident': {
          'pmh': ['Asthma'],
        },
      }),
      ['Asthma'],
    );
    expect(
      readPmh({
        'clinical': {'pmh': []},
        'incident': {
          'pmh': ['Asthma'],
        },
      }),
      isEmpty,
    );
    expect(
      readPmh({
        'clinical': {
          'pmh': ['None'],
        },
        'incident': {
          'pmh': ['Asthma'],
        },
      }),
      ['None'],
    );
  });
  test(
    'differential merge retains unknown and malformed fields on unrelated edits',
    () {
      final original = {
        'clinical': {
          'pmh': ['Future'],
          'vitals': 'unsupported',
          'future': 42,
        },
        'future': true,
      };
      final baseline = {
        'clinical': {
          'pmh': ['Future'],
          'vitals': [],
          'assessment': '',
        },
      };
      final current = {
        'clinical': {
          'pmh': ['Future'],
          'vitals': [],
          'assessment': 'Synthetic edit',
        },
      };
      final result = mergeRecord(original, baseline, current);
      expect(recordMap(result['clinical'])['vitals'], 'unsupported');
      expect(recordMap(result['clinical'])['future'], 42);
      expect(result['future'], true);
    },
  );
}
