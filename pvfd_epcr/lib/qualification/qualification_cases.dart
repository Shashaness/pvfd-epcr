import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../application/controllers/epcr_controller.dart';
import '../data/repositories/epcr_repository.dart';
import '../data/storage/epcr_storage_service.dart';
import '../data/storage/protected_storage_crypto.dart';
import '../domain/models/epcr_record.dart';
import '../services/encryption/encryption_types.dart';

class QualificationCases {
  Completer<void>? pause;
  static const namespace = 'pvfd_qualification_v1';
  static const marker = 'PVFD_SYNTHETIC_QUALIFICATION_V1';
  Future<Directory> _root() async {
    final directory = Directory(
      '${(await getApplicationSupportDirectory()).path}/$namespace',
    );
    final flag = File('${directory.path}/QUALIFICATION_ONLY');
    if (await directory.exists()) {
      if (!await flag.exists() ||
          await flag.length() > 64 ||
          await flag.readAsString() != marker) {
        throw const ProtectedStorageException(
          'qualificationNamespaceUnrecognized',
        );
      }
    } else {
      await directory.create();
      await flag.writeAsString(marker, flush: true);
    }
    return directory;
  }

  Future<LocalEpcrRepository> _repository() async {
    final directory = Directory('${(await _root()).path}/documents');
    await directory.create();
    return LocalEpcrRepository(documentsDirectory: () async => directory);
  }

  Future<EpcrRecord> _basic(LocalEpcrRepository repository) async {
    final records = await repository.list();
    final matches = records.where(
      (r) => r.toJson()['qualificationScenario'] == 'basic',
    );
    if (matches.length != 1) {
      throw const ProtectedStorageException('qualificationBasicCaseRequired');
    }
    return matches.single;
  }

  Future<String> basic() async {
    final repository = await _repository();
    final records = await repository.list();
    final existing = records.where(
      (r) => r.toJson()['qualificationScenario'] == 'basic',
    );
    final record = existing.isEmpty
        ? await repository.create(
            EpcrRecord.fromJson({
              'synthetic': true,
              'qualificationScenario': 'basic',
              'qualificationSequence': 0,
              'patient': {
                'firstName': 'TEST ONLY — Fictitious',
                'lastName': 'Qualification',
              },
              'incident': {
                'incidentNumber': 'SYNTHETIC-0001',
                'incidentAddress': 'Fictitious training site',
              },
              'dateTimeCreated': '2026-10-22T12:00:00Z',
              'note': 'Synthetic Δ 日本語 🩺',
            }),
          )
        : existing.single;
    final next = (record.toJson()['qualificationSequence'] as int) + 1;
    await repository.save(
      EpcrRecord.fromJson({
        ...record.toJson(),
        'qualificationSequence': next,
      }, sourcePath: record.sourcePath),
    );
    final read = await repository.load(record.sourcePath!);
    if (read.toJson()['qualificationSequence'] != next ||
        read.toJson()['note'] != 'Synthetic Δ 日本語 🩺') {
      throw const ProtectedStorageException('qualificationReadMismatch');
    }
    return 'PASS create/read/update/offline path; revision sequence $next. Synthetic namespace only.';
  }

  Future<String> autosave() async {
    final repository = await _repository();
    final controller = EpcrController(repository: repository);
    try {
      controller.firstName.text = 'TEST ONLY — Autosave';
      controller.assessment.text = 'Synthetic autosave Δ 日本語 🩺';
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (!await controller.flush()) {
        throw const ProtectedStorageException('qualificationAutosaveFailed');
      }
      final records = await repository.list();
      if (!records.any((r) => r.patient.firstName == 'TEST ONLY — Autosave')) {
        throw const ProtectedStorageException('qualificationAutosaveMissing');
      }
      return 'PASS 750 ms autosave and awaited flush; synthetic record persisted.';
    } finally {
      controller.dispose();
    }
  }

  Future<String> verifyRestart() async {
    final repository = await _repository();
    await _basic(repository);
    final documents = await repository.documentsDirectory();
    final pending = await repository.storage.pendingUploads(documents);
    if (pending.isEmpty) {
      throw const ProtectedStorageException('qualificationQueueMissing');
    }
    final checkpoint = File('${(await _root()).path}/checkpoint.json');
    if (await checkpoint.exists()) {
      final expected = jsonDecode(await checkpoint.readAsString()) as Map;
      final matches = pending.where(
        (p) => p.storageId == expected['storageId'],
      );
      if (matches.length != 1 ||
          matches.single.revision != expected['revision'] ||
          matches.single.sha256Digest != expected['sha256']) {
        throw const ProtectedStorageException(
          'qualificationUnexpectedPublication',
        );
      }
      if (await repository.orphanCount() < 1) {
        throw const ProtectedStorageException('qualificationOrphanMissing');
      }
    }
    return 'PASS restart/authenticated reads; ${pending.length} pending bundles; ${await repository.orphanCount()} retained orphans.';
  }

  Future<String> boundedSpaceFailure() async {
    final repository = await _repository();
    final record = await _basic(repository);
    final documents = await repository.documentsDirectory();
    final prior = (await repository.storage.pendingUploads(documents))
        .firstWhere(
          (p) =>
              p.file.parent.parent.path == File(record.sourcePath!).parent.path,
        );
    final snapshot = {
      ...record.toJson(),
      'qualificationFailure': 'SYNTHETIC ENOSPC',
    };
    if (utf8.encode(jsonEncode(snapshot)).length > 16384) {
      throw const ProtectedStorageException('qualificationSizeLimit');
    }
    final failing = EpcrStorageService(
      beforeRecoveryStage: () async {
        throw const FileSystemException(
          'Synthetic ENOSPC injection',
          null,
          OSError('synthetic quota', 28),
        );
      },
    );
    var rejected = false;
    try {
      await failing.save(File(record.sourcePath!), snapshot);
    } on FileSystemException catch (e) {
      rejected = e.osError?.errorCode == 28;
    }
    if (!rejected) {
      throw const ProtectedStorageException('qualificationFailureNotRejected');
    }
    final current = (await repository.storage.pendingUploads(
      documents,
    )).firstWhere((p) => p.storageId == prior.storageId);
    if (current.revision != prior.revision ||
        current.sha256Digest != prior.sha256Digest) {
      throw const ProtectedStorageException(
        'qualificationPriorRevisionChanged',
      );
    }
    return 'PASS injected ENOSPC at bounded staging point (<=16 KiB payload); prior bundle/queue intact. Not a physical full-volume test.';
  }

  Future<String> tamper() async {
    final repository = await _repository();
    final record = await _basic(repository);
    final queue = await repository.storage.pendingUploads(
      await repository.documentsDirectory(),
    );
    final own = queue.firstWhere(
      (p) => p.file.parent.parent.path == File(record.sourcePath!).parent.path,
    );
    final file = File('${own.file.parent.path}/local.enc');
    final original = await file.readAsBytes();
    final changed = original.toList();
    changed[changed.length - 1] ^= 1;
    var rejected = false;
    try {
      await file.writeAsBytes(changed, flush: true);
      try {
        await repository.load(record.sourcePath!);
      } on EncryptionException catch (e) {
        rejected = e.code == EncryptionError.authenticationFailed;
      }
    } finally {
      await file.writeAsBytes(original, flush: true);
      await AndroidDurableFileOperations().syncDirectory(file.parent);
    }
    if (!rejected) {
      throw const ProtectedStorageException('qualificationTamperNotRejected');
    }
    await repository.load(record.sourcePath!);
    return 'PASS synthetic ciphertext tampering rejected; original ciphertext restored and directory synced.';
  }

  Future<String> pauseBeforePublication(void Function(String) status) async {
    final repository = await _repository();
    final record = await _basic(repository);
    final documents = await repository.documentsDirectory();
    final prior = (await repository.storage.pendingUploads(documents))
        .firstWhere(
          (p) =>
              p.file.parent.parent.path == File(record.sourcePath!).parent.path,
        );
    await File('${(await _root()).path}/checkpoint.json').writeAsString(
      jsonEncode({
        'storageId': prior.storageId,
        'revision': prior.revision,
        'sha256': prior.sha256Digest,
      }),
      flush: true,
    );
    pause = Completer<void>();
    try {
      await EpcrStorageService(
        beforeReplace: (_, _) async {
          status(
            'READY_TO_TERMINATE: complete staged bundle, before rename. Operator may now force-stop only the confirmed test session.',
          );
          await pause!.future;
        },
      ).save(File(record.sourcePath!), {
        ...record.toJson(),
        'qualificationInterrupted': true,
      });
      throw const ProtectedStorageException(
        'qualificationPauseUnexpectedlyReleased',
      );
    } on ProtectedStorageException catch (e) {
      if (e.code == 'qualificationPauseCancelled') {
        await File('${(await _root()).path}/checkpoint.json').delete();
      }
      rethrow;
    } finally {
      pause = null;
    }
  }

  void cancelPause() => pause?.completeError(
    const ProtectedStorageException('qualificationPauseCancelled'),
  );
}
