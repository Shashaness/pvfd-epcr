import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pvfd_epcr/services/epcr_storage_service.dart';

void main() {
  late Directory dir;
  late File file;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('synthetic_epcr_');
    file = File('${dir.path}/pcr_20261022141530.json');
  });
  tearDown(() async => dir.delete(recursive: true));

  test(
    'save and overwrite valid JSON; legacy filename remains readable',
    () async {
      final service = EpcrStorageService();
      await service.save(file, {'epcrNumber': '20261022141530', 'value': 1});
      expect((await service.read(file))['value'], 1);
      await service.save(file, {'value': 2});
      expect((await service.read(file))['value'], 2);
    },
  );
  test('serialization failure never touches committed data', () async {
    final service = EpcrStorageService();
    await service.save(file, {'value': 1});
    expect(() => service.save(file, {'invalid': Object()}), throwsA(anything));
    expect((await service.read(file))['value'], 1);
  });
  test('write failure reports error without a committed file', () async {
    final target = File('${dir.path}/missing/pcr.json');
    await expectLater(
      EpcrStorageService().save(target, {'value': 1}),
      throwsA(isA<FileSystemException>()),
    );
    expect(await target.exists(), false);
  });
  test(
    'interruption before rename preserves last valid copy and cleans temp',
    () async {
      await EpcrStorageService().save(file, {'value': 1});
      final service = EpcrStorageService(
        beforeReplace: (temp, target) async {
          expect(jsonDecode(await temp.readAsString()), {'value': 2});
          throw const FileSystemException('Simulated interruption');
        },
      );
      await expectLater(
        service.save(file, {'value': 2}),
        throwsA(isA<FileSystemException>()),
      );
      expect(jsonDecode(await file.readAsString()), {'value': 1});
      expect(await service.orphanCount(dir), 0);
    },
  );
  test(
    'actual rename failure preserves existing directory and valid copy',
    () async {
      await file.writeAsString('{"value":1}');
      final service = EpcrStorageService(
        beforeReplace: (temp, target) async {
          // Rename to a directory fails, independently of the old report.
          await temp.rename(dir.path);
        },
      );
      await expectLater(
        service.save(file, {'value': 2}),
        throwsA(isA<FileSystemException>()),
      );
      expect(jsonDecode(await file.readAsString()), {'value': 1});
    },
  );
  test(
    'overlapping rapid saves are ordered and snapshots are immutable',
    () async {
      final gate = Completer<void>();
      var calls = 0;
      final service = EpcrStorageService(
        beforeReplace: (_, destination) async {
          if (calls++ == 0) await gate.future;
        },
      );
      final first = service.save(file, {'value': -1});
      final mutable = <String, dynamic>{'value': 0};
      final second = service.save(file, mutable);
      mutable['value'] = 999;
      gate.complete();
      await Future.wait([first, second]);
      expect((await service.read(file))['value'], 0);
      await Future.wait(
        List.generate(50, (i) => service.save(file, {'value': i})),
      );
      expect((await service.read(file))['value'], 49);
    },
  );
  test('failed write does not poison later queued saves', () async {
    var calls = 0;
    final service = EpcrStorageService(
      beforeReplace: (_, destination) async {
        if (calls++ == 0) throw const FileSystemException('Synthetic failure');
      },
    );
    await expectLater(service.save(file, {'value': 1}), throwsA(anything));
    await service.save(file, {'value': 2});
    expect((await service.read(file))['value'], 2);
  });
  test(
    'creation retries collision and cannot overwrite historical report',
    () async {
      await file.writeAsString('{"value":"original"}');
      var attempts = 0;
      final created = await EpcrStorageService().create(
        dir,
        {'value': 'new'},
        idFactory: () =>
            attempts++ == 0 ? '20261022141530' : '20261022141530-ABC',
      );
      expect(created.path, endsWith('-ABC.json'));
      expect(jsonDecode(await file.readAsString())['value'], 'original');
      await expectLater(
        EpcrStorageService().create(dir, {}, idFactory: () => '20261022141530'),
        throwsA(anything),
      );
    },
  );
  test(
    'secure identifiers unique across service restarts, timestamp interpretable',
    () async {
      final time = DateTime(2026, 10, 22, 14, 15, 30);
      final ids = List.generate(1000, (_) => newEpcrId(time));
      expect(ids.toSet().length, 1000);
      expect(
        ids.every(
          (id) => RegExp(r'^20261022141530-[A-F0-9]{32}$').hasMatch(id),
        ),
        true,
      );
      final a = await EpcrStorageService().create(dir, {});
      final b = await EpcrStorageService().create(dir, {});
      expect(a.path, isNot(b.path));
    },
  );
  test(
    'listing isolates malformed files, changes none, retains orphan for recovery',
    () async {
      await file.writeAsString('{"epcrNumber":"legacy","patient":42}');
      final broken = File('${dir.path}/broken.json');
      await broken.writeAsString('{broken');
      await File('${dir.path}/array.json').writeAsString('[]');
      final orphan = File('${file.path}.epcr-tmp-interrupted');
      await orphan.writeAsString('{"value":"uncommitted"}');
      var errors = 0;
      final service = EpcrStorageService();
      expect((await service.list(dir, onUnreadable: () => errors++)).length, 1);
      expect(errors, 2);
      expect(await broken.readAsString(), '{broken');
      expect(await service.orphanCount(dir), 1);
      expect(await orphan.exists(), true);
      expect((await service.read(file))['epcrNumber'], 'legacy');
    },
  );
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
