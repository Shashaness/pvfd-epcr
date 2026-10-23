import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../../core/epcr_id.dart';
import '../../services/recovery/operational_recovery_key.dart';
import '../../services/recovery/recovery_encryption_service.dart';
import 'protected_storage_crypto.dart';

class PendingRecoveryUpload {
  const PendingRecoveryUpload(
    this.storageId,
    this.revision,
    this.operation,
    this.file,
    this.sha256Digest,
  );
  final String storageId;
  final int revision;
  final String operation;
  final File file;
  final String sha256Digest;
  // Immutable revision-specific object keys; no mutable cloud "latest" overwrite.
  String get objectKey => '$storageId/$revision.pvfdbak';
}

class DevelopmentResetPlan {
  DevelopmentResetPlan._(
    this.documentsPath,
    this._files,
    this._directories,
    this.confirmationToken,
  );
  final String documentsPath;
  final Map<String, String> _files;
  final List<String> _directories;
  final String confirmationToken;
  int get fileCount => _files.length;
  int get directoryCount => _directories.length;

  /// Metadata-only preview for the separately armed development harness.
  List<String> get relativeFiles => List.unmodifiable(
    _files.keys.map((p) => p.substring(documentsPath.length + 1)).toList()
      ..sort(),
  );
  List<String> get relativeDirectories => List.unmodifiable(
    _directories.map((p) => p.substring(documentsPath.length + 1)).toList()
      ..sort(),
  );
}

/// All three revision members become visible through one directory rename.
/// No serialized medical JSON is ever passed to a filesystem write.
class EpcrStorageService {
  EpcrStorageService({
    this.beforeReplace,
    this.beforeRecoveryStage,
    ProtectedStorageCrypto? crypto,
    DurableFileOperations? durability,
    this.recoveryKeyId = operationalRecoveryKeyId,
    this.allowDevelopmentReset = const bool.fromEnvironment(
      'PVFD_ALLOW_DEVELOPMENT_RESET',
    ),
  }) : crypto = crypto ?? RotatingStorageCrypto.android(),
       durability = durability ?? AndroidDurableFileOperations();
  final ProtectedStorageCrypto crypto;
  final DurableFileOperations durability;
  final bool allowDevelopmentReset;
  final String recoveryKeyId;
  final Future<void> Function(File temporary, File destination)? beforeReplace;
  final Future<void> Function()? beforeRecoveryStage;
  static final Map<String, Future<void>> _queues = {};
  static final _opaque = RegExp(r'^[0-9a-f]{32}$');
  static final _generation = RegExp(r'^rev_[0-9]{16}$');
  static const baseName = 'protected_epcr_v1';

  Future<void> _legacy(Directory directory) async {
    await for (final entry in directory.list(followLinks: false)) {
      if (entry.path.endsWith('.json')) {
        throw const ProtectedStorageException('legacyPlaintextRejected');
      }
    }
  }

  Future<T> _locked<T>(
    Directory documents,
    Future<T> Function(Directory) action, {
    bool checkLegacy = true,
  }) {
    final path = documents.absolute.path;
    final previous = _queues[path] ?? Future<void>.value();
    final result = previous.then((_) async {
      if (checkLegacy) await _legacy(documents);
      final base = Directory('$path/$baseName');
      if (await FileSystemEntity.type(base.path, followLinks: false) ==
          FileSystemEntityType.link) {
        throw const ProtectedStorageException('unsafeStoragePath');
      }
      await base.create();
      final lock = await File('${base.path}/.lock').open(mode: FileMode.append);
      await lock.lock(FileLock.exclusive);
      try {
        return await action(base);
      } finally {
        await lock.unlock();
        await lock.close();
      }
    });
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _queues[path] = tail;
    unawaited(
      tail.then((_) {
        if (identical(_queues[path], tail)) _queues.remove(path);
      }),
    );
    return result;
  }

  Directory _documents(File handle) {
    final record = handle.parent;
    if (handle.uri.pathSegments.last != 'record.epcr' ||
        !_opaque.hasMatch(_name(record)) ||
        _name(record.parent) != baseName) {
      throw const ProtectedStorageException('legacyPlaintextRejected');
    }
    return record.parent.parent;
  }

  String _name(FileSystemEntity entity) =>
      entity.uri.pathSegments.where((p) => p.isNotEmpty).last;
  Future<List<Directory>> _generations(Directory record) async {
    if (await FileSystemEntity.type(record.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const ProtectedStorageException('recordUnavailable');
    }
    final result = <Directory>[];
    await for (final entry in record.list(followLinks: false)) {
      if (_generation.hasMatch(_name(entry))) {
        if (entry is! Directory) {
          throw const ProtectedStorageException('unsafeStoragePath');
        }
        result.add(entry);
      }
    }
    result.sort((a, b) => a.path.compareTo(b.path));
    return result;
  }

  Future<Uint8List> _bounded(File file, int limit) async {
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await file.length() > limit) {
      throw const ProtectedStorageException('invalidRevision');
    }
    return file.readAsBytes();
  }

  Uint8List _context(String storageId, Map<String, dynamic> metadata) =>
      Uint8List.fromList(
        utf8.encode('PVFD/local-store/v1/$storageId/${jsonEncode(metadata)}'),
      );
  Future<
    ({
      Map<String, dynamic> json,
      Map<String, dynamic> metadata,
      Directory generation,
    })
  >
  _read(Directory record) async {
    final generations = await _generations(record);
    if (generations.isEmpty) {
      throw const ProtectedStorageException('incompleteRecord');
    }
    final generation = generations.last;
    dynamic value;
    try {
      value = jsonDecode(
        utf8.decode(
          await _bounded(File('${generation.path}/pending.json'), 1024),
        ),
      );
    } on FormatException {
      throw const ProtectedStorageException('invalidRevision');
    }
    if (value is! Map<String, dynamic> ||
        value.length != 5 ||
        value['version'] != 1 ||
        value['revision'] is! int ||
        value['revision'] < 1 ||
        value['revision'] > 9007199254740991 ||
        !['save', 'delete'].contains(value['operation']) ||
        value['recoveryKeyId'] is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(value['recoveryKeyId'] as String) ||
        value['recoverySha256'] is! String ||
        !RegExp(
          r'^[0-9a-f]{64}$',
        ).hasMatch(value['recoverySha256'] as String) ||
        _name(generation) !=
            'rev_${value['revision'].toString().padLeft(16, '0')}') {
      throw const ProtectedStorageException('invalidRevision');
    }
    final metadata = <String, dynamic>{
      'version': 1,
      'revision': value['revision'],
      'operation': value['operation'],
      'recoveryKeyId': value['recoveryKeyId'],
      'recoverySha256': value['recoverySha256'],
    };
    final backup = await _bounded(
      File('${generation.path}/recovery.pvfdbak'),
      RecoveryEnvelope.maxPayload + 496,
    );
    final envelope = RecoveryEnvelope.parse(backup);
    if (envelope.keyId != metadata['recoveryKeyId'] ||
        sha256.convert(backup).toString() != metadata['recoverySha256']) {
      throw const ProtectedStorageException('backupMismatch');
    }
    final bytes = await crypto.decryptLocal(
      await _bounded(
        File('${generation.path}/local.enc'),
        16 * 1024 * 1024 + 108,
      ),
      _context(_name(record), metadata),
    );
    dynamic json;
    try {
      json = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const ProtectedStorageException('invalidRecord');
    }
    if (json is! Map<String, dynamic>) {
      throw const ProtectedStorageException('invalidRecord');
    }
    return (json: json, metadata: metadata, generation: generation);
  }

  Future<void> _write(
    Directory base,
    Directory record,
    Uint8List plaintext, {
    required String operation,
  }) async {
    final generations = await record.exists()
        ? await _generations(record)
        : <Directory>[];
    var revision = 1;
    if (generations.isNotEmpty) {
      final current = await _read(
        record,
      ); // Never overwrite corrupted/unavailable old data.
      if (current.metadata['operation'] == 'delete') {
        throw const ProtectedStorageException('recordDeleted');
      }
      revision = (current.metadata['revision'] as int) + 1;
    }
    if (revision > 9007199254740991) {
      throw const ProtectedStorageException('revisionExhausted');
    }
    final backup = await crypto.encryptRecovery(plaintext);
    final parsed = RecoveryEnvelope.parse(backup);
    if (parsed.keyId != recoveryKeyId ||
        parsed.payloadLength != plaintext.length) {
      throw const ProtectedStorageException('backupMismatch');
    }
    final metadata = <String, dynamic>{
      'version': 1,
      'revision': revision,
      'operation': operation,
      'recoveryKeyId': recoveryKeyId,
      'recoverySha256': sha256.convert(backup).toString(),
    };
    final local = await crypto.encryptLocal(
      base,
      plaintext,
      _context(_name(record), metadata),
      durability,
    );
    await record.create();
    final handle = File('${record.path}/record.epcr');
    if (!await handle.exists()) {
      await handle.writeAsString('PVFDSTORE1', flush: true);
    }
    final stage = Directory('${record.path}/.stage_${opaqueStorageId()}');
    await stage.create();
    final destination = Directory(
      '${record.path}/rev_${revision.toString().padLeft(16, '0')}',
    );
    try {
      final localFile = File('${stage.path}/local.enc');
      await localFile.writeAsBytes(local, flush: true);
      await beforeRecoveryStage?.call();
      await File(
        '${stage.path}/recovery.pvfdbak',
      ).writeAsBytes(backup, flush: true);
      await File(
        '${stage.path}/pending.json',
      ).writeAsString(jsonEncode(metadata), flush: true);
      await durability.syncDirectory(stage);
      await beforeReplace?.call(
        localFile,
        File('${destination.path}/local.enc'),
      );
      await stage.rename(
        destination.path,
      ); // The only visibility/commit boundary.
      await File(
        '${record.path}/committed.marker',
      ).writeAsString('PVFDCOMMITTED1', flush: true);
      await durability.syncDirectory(record);
      await durability.syncDirectory(base);
      await durability.syncDirectory(base.parent);
      // Coalesce only after durable publication. No deletion on a failed commit.
      // Old ciphertext artifacts are retained if cleanup fails; not acknowledged uploads.
      for (final old in generations) {
        try {
          await _removeKnownGeneration(old);
        } catch (_) {
          /* Retained, inspect/reset later. */
        }
      }
    } finally {
      if (await stage.exists()) {
        try {
          await _removeKnownGeneration(stage);
        } catch (_) {
          /* Preserve unknown/interrupted artifacts. */
        }
      }
    }
  }

  Future<void> _removeKnownGeneration(Directory generation) async {
    final entries = await generation.list(followLinks: false).toList();
    if (entries.any(
      (e) =>
          e is! File ||
          ![
            'local.enc',
            'recovery.pvfdbak',
            'pending.json',
            '.uploaded',
          ].contains(_name(e)),
    )) {
      throw const ProtectedStorageException('unknownFilesRetained');
    }
    for (final entry in entries) {
      await entry.delete();
    }
    await generation.delete();
  }

  Future<void> save(File destination, Map<String, dynamic> record) {
    final bytes = Uint8List.fromList(
      utf8.encode(jsonEncode(record)),
    ); // Snapshot before queueing.
    final documents = _documents(destination);
    return _locked(documents, (base) async {
      if (!await destination.exists()) {
        throw const ProtectedStorageException('recordUnavailable');
      }
      await _write(base, destination.parent, bytes, operation: 'save');
    });
  }

  Future<File> create(
    Directory directory,
    Map<String, dynamic> record, {
    String Function()? idFactory,
  }) {
    final snapshot = jsonDecode(jsonEncode(record)) as Map<String, dynamic>;
    return _locked(directory, (base) async {
      final existing = await _list(base);
      for (var attempt = 0; attempt < 20; attempt++) {
        final id = idFactory?.call() ?? newEpcrId(DateTime.now());
        if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id)) {
          throw const ProtectedStorageException('invalidRecordId');
        }
        final matches = existing.where(
          (r) => r['appRecordId'] == id || r['epcrNumber'] == id,
        );
        if (matches.isNotEmpty) {
          // Idempotent retry of a controller-owned record after an ambiguous commit.
          if (snapshot['appRecordId'] == id && snapshot['epcrNumber'] == id) {
            final file = File(matches.first['_filePath'] as String);
            await _write(
              base,
              file.parent,
              Uint8List.fromList(
                utf8.encode(
                  jsonEncode({
                    ...snapshot,
                    'epcrNumber': id,
                    'appRecordId': id,
                  }),
                ),
              ),
              operation: 'save',
            );
            return file;
          }
          continue;
        }
        Directory target;
        do {
          target = Directory('${base.path}/${opaqueStorageId()}');
        } while (await target.exists());
        await _write(
          base,
          target,
          Uint8List.fromList(
            utf8.encode(
              jsonEncode({...snapshot, 'epcrNumber': id, 'appRecordId': id}),
            ),
          ),
          operation: 'save',
        );
        return File('${target.path}/record.epcr');
      }
      throw const ProtectedStorageException('recordAllocationFailed');
    });
  }

  Future<Map<String, dynamic>> read(File file) =>
      _locked(_documents(file), (base) async {
        final value = await _read(file.parent);
        if (value.metadata['operation'] == 'delete') {
          throw const ProtectedStorageException('recordDeleted');
        }
        return value.json;
      });
  Future<List<Map<String, dynamic>>> _list(
    Directory base, {
    void Function()? onUnreadable,
  }) async {
    final records = <Map<String, dynamic>>[];
    await for (final entry in base.list(followLinks: false)) {
      if (!_opaque.hasMatch(_name(entry))) continue;
      try {
        if (entry is! Directory) {
          throw const ProtectedStorageException('unsafeStoragePath');
        }
        if ((await _generations(entry)).isEmpty &&
            !await File('${entry.path}/committed.marker').exists()) {
          continue; // Uncommitted creation; never promote staging.
        }
        final current = await _read(entry);
        if (current.metadata['operation'] != 'delete') {
          records.add({
            ...current.json,
            '_filePath': '${entry.path}/record.epcr',
          });
        }
      } catch (_) {
        // Never present an unreadable database as an empty successful list.
        onUnreadable?.call();
        rethrow;
      }
    }
    records.sort(
      (a, b) => '${b['epcrNumber']}'.compareTo('${a['epcrNumber']}'),
    );
    return records;
  }

  Future<List<Map<String, dynamic>>> list(
    Directory directory, {
    void Function()? onUnreadable,
  }) => _locked(directory, (base) => _list(base, onUnreadable: onUnreadable));
  Future<void> delete(File file) => _locked(_documents(file), (base) async {
    final current = await _read(file.parent);
    if (current.metadata['operation'] == 'delete') return;
    await _write(
      base,
      file.parent,
      Uint8List.fromList(utf8.encode(jsonEncode({'deleted': true}))),
      operation: 'delete',
    );
  });
  Future<List<PendingRecoveryUpload>> pendingUploads(Directory directory) =>
      _locked(directory, (base) async {
        final result = <PendingRecoveryUpload>[];
        await for (final entry in base.list(followLinks: false)) {
          if (!_opaque.hasMatch(_name(entry))) continue;
          if (entry is! Directory) {
            throw const ProtectedStorageException('unsafeStoragePath');
          }
          if ((await _generations(entry)).isEmpty &&
              !await File('${entry.path}/committed.marker').exists()) {
            continue;
          }
          final current = await _read(entry);
          if (await File('${current.generation.path}/.uploaded').exists()) {
            continue;
          }
          result.add(
            PendingRecoveryUpload(
              _name(entry),
              current.metadata['revision'] as int,
              current.metadata['operation'] as String,
              File('${current.generation.path}/recovery.pvfdbak'),
              current.metadata['recoverySha256'] as String,
            ),
          );
        }
        return result;
      });
  Future<Uint8List?> readPendingUpload(
    Directory directory,
    PendingRecoveryUpload upload,
  ) => _locked(directory, (base) async {
    if (!_opaque.hasMatch(upload.storageId)) {
      throw const ProtectedStorageException('invalidQueueEntry');
    }
    final current = await _read(Directory('${base.path}/${upload.storageId}'));
    if (current.metadata['revision'] != upload.revision ||
        current.metadata['recoverySha256'] != upload.sha256Digest) {
      return null;
    }
    return _bounded(
      File('${current.generation.path}/recovery.pvfdbak'),
      RecoveryEnvelope.maxPayload + 496,
    );
  });
  Future<bool> acknowledgeUpload(
    Directory directory,
    PendingRecoveryUpload upload,
  ) => _locked(directory, (base) async {
    if (!_opaque.hasMatch(upload.storageId)) {
      throw const ProtectedStorageException('invalidQueueEntry');
    }
    final current = await _read(Directory('${base.path}/${upload.storageId}'));
    if (current.metadata['revision'] != upload.revision ||
        current.metadata['recoverySha256'] != upload.sha256Digest) {
      return false;
    }
    await File(
      '${current.generation.path}/.uploaded',
    ).writeAsString('uploaded', flush: true);
    await durability.syncDirectory(current.generation);
    return true;
  });
  Future<int> orphanCount(Directory directory) => _locked(directory, (
    base,
  ) async {
    var count = 0;
    await for (final entry in base.list(recursive: true, followLinks: false)) {
      if (entry is Directory &&
          _opaque.hasMatch(_name(entry)) &&
          (await _generations(entry)).isEmpty) {
        count++;
      }
      if (_name(entry).startsWith('.stage_') ||
          _name(entry).startsWith('.key-tmp-')) {
        count++;
      }
    }
    return count;
  });
  void _resetAllowed() {
    if (!kDebugMode || !allowDevelopmentReset) {
      throw const ProtectedStorageException('developmentResetDisabled');
    }
  }

  Future<DevelopmentResetPlan> prepareDevelopmentReset(Directory documents) {
    _resetAllowed();
    return _locked(documents, (base) async {
      final files = <String, String>{};
      final directories = <String>[];
      Future<void> capture(File file) async {
        final data = await _bounded(file, 16 * 1024 * 1024 + 496);
        files[file.absolute.path] = sha256.convert(data).toString();
      }

      final legacy = RegExp(
        r'^pcr_[A-Za-z0-9_-]+\.json(?:\.reserve|\.epcr-tmp-[A-Za-z0-9_-]+)?$',
      );
      await for (final entry in documents.list(followLinks: false)) {
        if (legacy.hasMatch(_name(entry))) {
          if (entry is! File) {
            throw const ProtectedStorageException('unknownFilesRetained');
          }
          await capture(entry);
        }
      }
      await for (final entry in base.list(followLinks: false)) {
        if (entry is File &&
            RegExp(r'^\.key-tmp-[0-9a-f]{32}$').hasMatch(_name(entry))) {
          await capture(entry);
          continue;
        }
        if (!_opaque.hasMatch(_name(entry))) continue;
        if (entry is! Directory) {
          throw const ProtectedStorageException('unknownFilesRetained');
        }
        directories.add(entry.absolute.path);
        await for (final child in entry.list(followLinks: false)) {
          if (child is File &&
              ['record.epcr', 'committed.marker'].contains(_name(child))) {
            if (await child.readAsString() !=
                (_name(child) == 'record.epcr'
                    ? 'PVFDSTORE1'
                    : 'PVFDCOMMITTED1')) {
              throw const ProtectedStorageException('unknownFilesRetained');
            }
            await capture(child);
          } else if (child is Directory &&
              (_generation.hasMatch(_name(child)) ||
                  RegExp(r'^\.stage_[0-9a-f]{32}$').hasMatch(_name(child)))) {
            directories.add(child.absolute.path);
            await for (final file in child.list(followLinks: false)) {
              if (file is! File ||
                  ![
                    'local.enc',
                    'recovery.pvfdbak',
                    'pending.json',
                    '.uploaded',
                  ].contains(_name(file))) {
                throw const ProtectedStorageException('unknownFilesRetained');
              }
              await capture(file);
            }
          } else {
            throw const ProtectedStorageException('unknownFilesRetained');
          }
        }
      }
      final sorted = files.keys.toList()..sort();
      directories.sort();
      final token = sha256
          .convert(
            utf8.encode(
              jsonEncode({
                'files': {for (final path in sorted) path: files[path]},
                'directories': directories,
              }),
            ),
          )
          .toString();
      return DevelopmentResetPlan._(
        documents.absolute.path,
        files,
        directories,
        token,
      );
    }, checkLegacy: false);
  }

  Future<void> executeDevelopmentReset(
    DevelopmentResetPlan plan, {
    required String confirmation,
  }) async {
    _resetAllowed();
    if (confirmation !=
        'DELETE CONFIRMED DEVELOPMENT DATA ONLY ${plan.confirmationToken}') {
      throw const ProtectedStorageException('developmentConfirmationRequired');
    }
    // Rebuild and compare before acquiring the final transaction, then recheck
    // every file under the lock. This does not authorize removing unknown files.
    final current = await prepareDevelopmentReset(
      Directory(plan.documentsPath),
    );
    if (current.confirmationToken != plan.confirmationToken) {
      throw const ProtectedStorageException('resetPlanChanged');
    }
    await _locked(Directory(plan.documentsPath), (base) async {
      final legacy = RegExp(
        r'^pcr_[A-Za-z0-9_-]+\.json(?:\.reserve|\.epcr-tmp-[A-Za-z0-9_-]+)?$',
      );
      await for (final entry in Directory(
        plan.documentsPath,
      ).list(followLinks: false)) {
        if (legacy.hasMatch(_name(entry)) &&
            !plan._files.containsKey(entry.absolute.path)) {
          throw const ProtectedStorageException('resetPlanChanged');
        }
      }
      // Enumerate again to detect additions, not merely changes to planned files.
      final entries = await base
          .list(recursive: true, followLinks: false)
          .toList();
      for (final entry in entries) {
        if (entry is Link) {
          throw const ProtectedStorageException('unknownFilesRetained');
        }
        if (entry is Directory &&
            _opaque.hasMatch(_name(entry)) &&
            !plan._directories.contains(entry.absolute.path)) {
          throw const ProtectedStorageException('resetPlanChanged');
        }
        final owner = plan._directories.any(
          (d) => entry.absolute.path.startsWith('$d/'),
        );
        if (owner &&
            entry is File &&
            !plan._files.containsKey(entry.absolute.path)) {
          throw const ProtectedStorageException('resetPlanChanged');
        }
        if (owner &&
            entry is Directory &&
            !plan._directories.contains(entry.absolute.path)) {
          throw const ProtectedStorageException('resetPlanChanged');
        }
      }
      for (final path in plan._files.keys) {
        if (sha256
                .convert(await _bounded(File(path), 16 * 1024 * 1024 + 496))
                .toString() !=
            plan._files[path]) {
          throw const ProtectedStorageException('resetPlanChanged');
        }
      }
      for (final path in plan._files.keys) {
        await File(path).delete();
      }
      final dirs = plan._directories.toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      for (final path in dirs) {
        await Directory(path).delete();
      }
      await durability.syncDirectory(base);
      await durability.syncDirectory(base.parent);
      // keys.json, Android Keystore aliases and nonce ledger are never removed.
    }, checkLegacy: false);
  }
}
