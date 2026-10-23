import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import '../../services/encryption/android_keystore_provider.dart';
import '../../services/encryption/encryption_types.dart';
import '../../services/encryption/record_encryption_service.dart';
import '../../services/recovery/operational_recovery_key.dart';
import '../../services/recovery/recovery_encryption_service.dart';

class ProtectedStorageException implements Exception {
  const ProtectedStorageException(this.code);
  final String code;
  @override
  String toString() => 'ProtectedStorageException($code)';
}

String opaqueStorageId() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

abstract interface class DurableFileOperations {
  Future<void> syncDirectory(Directory directory);
}

class AndroidDurableFileOperations implements DurableFileOperations {
  static const _channel = MethodChannel('com.pvfd3.pvfd_epcr/durability');
  @override
  Future<void> syncDirectory(Directory directory) async {
    try {
      await _channel.invokeMethod<void>('syncDirectory', {
        'path': directory.absolute.path,
      });
    } catch (_) {
      throw const ProtectedStorageException('directorySyncFailed');
    }
  }
}

abstract interface class ProtectedStorageCrypto {
  Future<Uint8List> encryptLocal(
    Directory base,
    Uint8List plaintext,
    Uint8List context,
    DurableFileOperations durability,
  );
  Future<Uint8List> decryptLocal(Uint8List envelope, Uint8List context);
  Future<Uint8List> encryptRecovery(Uint8List plaintext);
}

/// Key creation occurs only on a protected write, never as a decryption fallback.
class RotatingStorageCrypto implements ProtectedStorageCrypto {
  RotatingStorageCrypto({
    required this.keys,
    required this.local,
    required this.usage,
    required this.recovery,
  });
  factory RotatingStorageCrypto.android() {
    final provider = AndroidKeystoreProvider();
    final recovery = AndroidRecoveryEncryptionService();
    return RotatingStorageCrypto(
      keys: provider,
      local: RecordEncryptionService(keys: provider, cipher: provider),
      usage: provider.usedOperations,
      recovery: (bytes) async => recovery.encryptForRecovery(
        bytes,
        await loadOperationalRecoveryKey(recovery),
      ),
    );
  }
  final EncryptionKeyManager keys;
  final RecordEncryptionService local;
  final Future<int> Function(String) usage;
  final Future<Uint8List> Function(Uint8List) recovery;
  static const rotateAt = 60000;
  Future<String> _newKey(
    Directory base,
    DurableFileOperations durability,
  ) async {
    final id = 'local_${opaqueStorageId()}';
    await keys.create(id);
    await keys.lookup(id);
    final temporary = File('${base.path}/.key-tmp-${opaqueStorageId()}');
    try {
      await temporary.writeAsString(
        jsonEncode({'version': 1, 'active': id}),
        flush: true,
      );
      await temporary.rename('${base.path}/keys.json');
      await durability.syncDirectory(base);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
    return id;
  }

  @override
  Future<Uint8List> encryptLocal(
    Directory base,
    Uint8List plaintext,
    Uint8List context,
    DurableFileOperations durability,
  ) async {
    final index = File('${base.path}/keys.json');
    String id;
    if (!await index.exists()) {
      // Existing record handles (including interrupted creation) prohibit silent
      // re-provisioning after key-index loss. An orphan key is never overwritten.
      if (await base
          .list(followLinks: false)
          .any(
            (e) =>
                e is Directory &&
                RegExp(
                  r'^[0-9a-f]{32}$',
                ).hasMatch(e.uri.pathSegments.where((p) => p.isNotEmpty).last),
          )) {
        throw const ProtectedStorageException('keyIndexMissing');
      }
      id = await _newKey(base, durability);
    } else {
      try {
        final value = jsonDecode(await index.readAsString());
        if (value is! Map ||
            value['version'] != 1 ||
            value['active'] is! String ||
            !RegExp(
              r'^local_[0-9a-f]{32}$',
            ).hasMatch(value['active'] as String)) {
          throw const ProtectedStorageException('keyIndexInvalid');
        }
        id = value['active'] as String;
      } catch (_) {
        throw const ProtectedStorageException('keyIndexInvalid');
      }
      await keys.lookup(
        id,
      ); // Lost/inaccessible keys are incidents, not rotation.
    }
    final used = await usage(id);
    if (used < 0 || used > 65536) {
      throw const ProtectedStorageException('keyUsageInvalid');
    }
    if (used >= rotateAt) id = await _newKey(base, durability);
    return local.encrypt(id, plaintext, context: context);
  }

  @override
  Future<Uint8List> decryptLocal(Uint8List envelope, Uint8List context) =>
      local.decrypt(envelope, context: context);
  @override
  Future<Uint8List> encryptRecovery(Uint8List plaintext) => recovery(plaintext);
}
