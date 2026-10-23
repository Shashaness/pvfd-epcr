import 'dart:async';
import 'dart:io';
import 'support/protected_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pvfd_epcr/data/repositories/epcr_repository.dart';
import 'package:pvfd_epcr/domain/models/epcr_record.dart';

void main() {
  late Directory dir;
  late LocalEpcrRepository repository;
  late SyntheticStorageEnvironment environment;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('synthetic_repository_');
    environment = SyntheticStorageEnvironment();
    repository = LocalEpcrRepository(
      documentsDirectory: () async => dir,
      storage: environment.storage(),
    );
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
      final artifact = (await repository.storage.pendingUploads(dir)).single.file;
      final before = await artifact.readAsBytes();
      final listed = (await repository.list()).single;
      expect(listed.sourcePath, path);
      expect(await artifact.readAsBytes(), before);
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
        storage: environment.storage(
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
      storage: environment.storage(
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
  test('legacy plaintext blocks listing and is never rewritten', () async {
    final broken = File('${dir.path}/pcr_legacy.json');
    await broken.writeAsString('{broken');
    await expectLater(repository.list(), throwsA(anything));
    await expectLater(repository.load(broken.path), throwsA(anything));
    expect(await broken.readAsString(), '{broken');
  });
}
