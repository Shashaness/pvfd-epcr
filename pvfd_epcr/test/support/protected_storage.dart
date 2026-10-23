// Synthetic test providers only. Production cannot select these implementations.
import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:pvfd_epcr/data/storage/epcr_storage_service.dart';
import 'package:pvfd_epcr/data/storage/protected_storage_crypto.dart';
import 'package:pvfd_epcr/services/encryption/record_encryption_service.dart';
import 'package:pvfd_epcr/services/recovery/operational_recovery_key.dart';
import 'encryption/memory_crypto_provider.dart';

class TestDirectoryDurability implements DurableFileOperations {
  bool fail = false;
  int calls = 0;
  int? failOnCall;
  @override
  Future<void> syncDirectory(Directory directory) async {
    calls++;
    if (fail || calls == failOnCall) {
      throw const ProtectedStorageException('directorySyncFailed');
    }
  }
}

class SyntheticStorageEnvironment {
  final keys = MemoryCryptoProvider();
  final durability = TestDirectoryDurability();
  int countOverride = 0;
  bool failRecovery = false;
  int recoveryCount = 0;
  final recoveryKeys = <String, SecretKey>{};
  late final RotatingStorageCrypto crypto = RotatingStorageCrypto(
    keys: keys,
    local: RecordEncryptionService(keys: keys, cipher: keys),
    usage: (id) async => countOverride,
    recovery: (bytes) async {
      if (failRecovery) {
        throw const ProtectedStorageException('syntheticRecoveryFailed');
      }
      // AES-GCM test-only envelope, not an RSA implementation or production
      // fallback. Real native RSA/Python interoperability is tested separately.
      final aes = AesGcm.with256bits();
      final key = SecretKey(
        List.generate(32, (i) => (i + recoveryCount++) % 256),
      );
      final nonce = Uint8List(12)
        ..buffer.asByteData().setUint64(4, recoveryCount);
      final header = Uint8List(480);
      header.setAll(0, 'PVFDBAK1'.codeUnits);
      header[8] = 1;
      header[9] = 1;
      header[14] = 12;
      header[15] = 16;
      ByteData.sublistView(header)
        ..setUint16(10, 64)
        ..setUint16(12, 384)
        ..setUint32(16, bytes.length);
      header.setAll(20, operationalRecoveryKeyId.codeUnits);
      header.setAll(468, nonce);
      final sealed = await aes.encrypt(
        bytes,
        secretKey: key,
        nonce: nonce,
        aad: header,
      );
      final box = Uint8List.fromList([
        ...header,
        ...sealed.cipherText,
        ...sealed.mac.bytes,
      ]);
      recoveryKeys[box.toString()] = key;
      return box;
    },
  );
  EpcrStorageService storage({
    Future<void> Function(File, File)? beforeReplace,
    Future<void> Function()? beforeRecoveryStage,
    bool allowDevelopmentReset = false,
  }) => EpcrStorageService(
    crypto: crypto,
    durability: durability,
    beforeReplace: beforeReplace,
    beforeRecoveryStage: beforeRecoveryStage,
    allowDevelopmentReset: allowDevelopmentReset,
  );
}
