import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pvfd_epcr/data/repositories/epcr_repository.dart';
import 'package:pvfd_epcr/data/storage/epcr_storage_service.dart';
import 'package:pvfd_epcr/domain/models/epcr_record.dart';

void main() {
  late Directory dir;
  late LocalEpcrRepository repository;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('synthetic_repository_');
    repository = LocalEpcrRepository(documentsDirectory: () async => dir);
  });
  tearDown(() async => dir.delete(recursive: true));
  test(
    'create list load save preserves source path and unknown values',
    () async {
      final created = await repository.create(
        EpcrRecord.fromJson({
          'patient': {'firstName': 'Synthetic'},
          'future': true,
        }),
      );
      final path = created.sourcePath!;
      final before = await File(path).readAsString();
      final listed = (await repository.list()).single;
      expect(listed.sourcePath, path);
      expect(await File(path).readAsString(), before);
      final loaded = await repository.load(path);
      await repository.save(
        EpcrRecord.fromJson({
          ...loaded.toJson(),
          'patient': {'firstName': 'Synthetic edit'},
        }, sourcePath: path),
      );
      final saved = await repository.load(path);
      expect(saved.patient.firstName, 'Synthetic edit');
      expect(saved.toJson()['future'], true);
      expect(saved.id, created.id);
    },
  );
  test(
    'repository delegates collision reservations without overwriting',
    () async {
      final first = await repository.create(
        EpcrRecord.fromJson({}),
        idFactory: () => 'legacy',
      );
      var calls = 0;
      final second = await repository.create(
        EpcrRecord.fromJson({}),
        idFactory: () => calls++ == 0 ? 'legacy' : 'new-id',
      );
      expect(first.id, 'legacy');
      expect(second.id, 'new-id');
      expect((await repository.list()).length, 2);
    },
  );
  test(
    'repository preserves order across overlapping saves and instances',
    () async {
      final created = await repository.create(EpcrRecord.fromJson({}));
      final gate = Completer<void>();
      final entered = Completer<void>();
      final blocked = LocalEpcrRepository(
        documentsDirectory: () async => dir,
        storage: EpcrStorageService(
          beforeReplace: (_, destination) async {
            entered.complete();
            await gate.future;
          },
        ),
      );
      final older = blocked.save(
        EpcrRecord.fromJson({'value': 1}, sourcePath: created.sourcePath),
      );
      await entered.future;
      final newer = repository.save(
        EpcrRecord.fromJson({'value': 2}, sourcePath: created.sourcePath),
      );
      gate.complete();
      await Future.wait([older, newer]);
      expect((await repository.load(created.sourcePath!)).toJson()['value'], 2);
    },
  );
  test('repository reports failures and retains last committed file', () async {
    final created = await repository.create(
      EpcrRecord.fromJson({'value': 'committed'}),
    );
    final failing = LocalEpcrRepository(
      documentsDirectory: () async => dir,
      storage: EpcrStorageService(
        beforeReplace: (_, destination) async {
          throw const FileSystemException('Synthetic failure');
        },
      ),
    );
    await expectLater(
      failing.save(
        EpcrRecord.fromJson({
          'value': 'uncommitted',
        }, sourcePath: created.sourcePath),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(
      (await repository.load(created.sourcePath!)).toJson()['value'],
      'committed',
    );
    expect(() => repository.save(EpcrRecord.fromJson({})), throwsStateError);
  });
  test(
    'malformed files and interrupted files remain untouched and detectable',
    () async {
      final created = await repository.create(EpcrRecord.fromJson({}));
      final broken = File('${dir.path}/damaged.json');
      await broken.writeAsString('{broken');
      final orphan = File('${created.sourcePath}.epcr-tmp-orphan');
      await orphan.writeAsString('{incomplete');
      var errors = 0;
      expect((await repository.list(onUnreadable: () => errors++)).length, 1);
      expect(errors, 1);
      expect(await repository.orphanCount(), 1);
      await expectLater(repository.load(broken.path), throwsFormatException);
      expect(await broken.readAsString(), '{broken');
      expect(await orphan.readAsString(), '{incomplete');
    },
  );
}
