import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pvfd_epcr/services/recovery/operational_recovery_key.dart';
import 'package:pvfd_epcr/services/recovery/recovery_encryption_service.dart';

import 'development_public_key.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.pvfd3.pvfd_epcr/recovery');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'operational public key loads with its independently pinned fingerprint',
    () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls++;
        expect(
          call.method,
          'validatePublicKey',
        ); // Provisioning never encrypts.
        final args = call.arguments as Map;
        final der = args['publicKeyDer'] as Uint8List;
        final digest = await Sha256().hash(der);
        final fingerprint = digest.bytes
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
        expect(
          fingerprint,
          '23c0301fc9fbf5898b1354484203b928c197ed95d843411fa6e3f3acc1dd88dd',
        );
        expect(fingerprint, operationalRecoveryKeyId);
        expect(args['keyId'], fingerprint);
        expect(fingerprint, isNot(developmentKeyId));
        return {'keyId': fingerprint};
      });
      final key = await loadOperationalRecoveryKey(
        AndroidRecoveryEncryptionService(),
      );
      expect(key.id, operationalRecoveryKeyId);
      expect(calls, 1);
    },
  );

  test(
    'operational provisioning failure never falls back to a test key',
    () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls++;
        expect((call.arguments as Map)['keyId'], operationalRecoveryKeyId);
        throw PlatformException(code: 'keyIdMismatch');
      });
      await expectLater(
        loadOperationalRecoveryKey(AndroidRecoveryEncryptionService()),
        throwsA(
          isA<RecoveryException>().having(
            (e) => e.code,
            'code',
            RecoveryError.keyIdMismatch,
          ),
        ),
      );
      expect(calls, 1);
    },
  );
}
