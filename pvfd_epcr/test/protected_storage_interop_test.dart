import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pvfd_epcr/data/storage/epcr_storage_service.dart';
import 'package:pvfd_epcr/data/storage/protected_storage_crypto.dart';
import 'package:pvfd_epcr/services/encryption/record_encryption_service.dart';
import 'support/protected_storage.dart';
import 'support/encryption/memory_crypto_provider.dart';

void main() {
  const publicPath = String.fromEnvironment('PVFD_TEST_PUBLIC_DER');
  if (publicPath.isEmpty) {
    return; // Explicit host harness supplies test-only configuration.
  }
  const id = String.fromEnvironment('PVFD_TEST_RECOVERY_ID');
  const java = String.fromEnvironment('PVFD_TEST_JAVA');
  const classpath = String.fromEnvironment('PVFD_TEST_JAVA_CP');
  const output = String.fromEnvironment('PVFD_TEST_OUTPUT');
  test(
    'committed pending artifact from production Kotlin recovers independently in Python',
    () async {
      final documents = await Directory.systemTemp.createTemp(
        'synthetic_interop_store_',
      );
      try {
        final keys = MemoryCryptoProvider();
        final crypto = RotatingStorageCrypto(
          keys: keys,
          local: RecordEncryptionService(keys: keys, cipher: keys),
          usage: (_) async => 0,
          recovery: (plaintext) async {
            final process = await Process.start(java, [
              '-cp',
              classpath,
              'NativeRecoveryEncrypt',
              publicPath,
              id,
            ]);
            final result = process.stdout.fold<List<int>>(
              [],
              (a, b) => a..addAll(b),
            );
            final errors = process.stderr.drain<void>();
            process.stdin.add(plaintext);
            await process.stdin.close();
            final bytes = await result;
            await errors;
            expect(await process.exitCode, 0);
            return Uint8List.fromList(bytes);
          },
        );
        final storage = EpcrStorageService(
          crypto: crypto,
          durability: TestDirectoryDurability(),
          recoveryKeyId: id,
        );
        final handle = await storage.create(documents, {
          'synthetic': true,
          'patient': {'firstName': 'TEST ONLY Δ 日本語 🩺'},
        }, idFactory: () => 'TEST-INTEROP');
        await storage.save(handle, {
          'synthetic': true,
          'revisionValue': 2,
          'note': 'TEST ONLY Δ 日本語 🩺',
        });
        final queue = (await storage.pendingUploads(documents)).single;
        final encrypted = (await storage.readPendingUpload(documents, queue))!;
        final original = Uint8List.fromList(
          utf8.encode(jsonEncode(await storage.read(handle))),
        );
        await File(
          '$output/backup.pvfdbak',
        ).writeAsBytes(encrypted, flush: true);
        await File('$output/original.bin').writeAsBytes(original, flush: true);
        keys.material
            .clear(); // Simulated loss of all test local keys after staging.
        expect(encrypted, isNotEmpty);
      } finally {
        await documents.delete(recursive: true);
      }
    },
  );
}
