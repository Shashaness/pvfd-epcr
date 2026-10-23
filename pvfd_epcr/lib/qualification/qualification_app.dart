import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../data/storage/epcr_storage_service.dart';
import '../data/storage/protected_storage_crypto.dart';
import '../services/encryption/encryption_types.dart';
import '../services/recovery/recovery_encryption_service.dart';
import 'qualification_cases.dart';

class QualificationApp extends StatelessWidget {
  const QualificationApp({super.key});
  @override
  Widget build(BuildContext context) =>
      const MaterialApp(home: QualificationPage());
}

class QualificationPage extends StatefulWidget {
  const QualificationPage({super.key});
  @override
  State<QualificationPage> createState() => _QualificationPageState();
}

class _QualificationPageState extends State<QualificationPage> {
  static const target = 'R95Y804S2PV';
  static const enabled =
      kDebugMode && bool.fromEnvironment('PVFD_HARDWARE_QUALIFICATION');
  static const armed =
      kDebugMode && bool.fromEnvironment('PVFD_ALLOW_DEVELOPMENT_RESET');
  final _serial = TextEditingController();
  final _phrase = TextEditingController();
  final _cases = QualificationCases();
  bool _development = false;
  bool _synthetic = false;
  bool _executeAuthorized = false;
  bool _busy = false;
  String _status = 'Preparation only. No operations run at startup.';
  DevelopmentResetPlan? _plan;
  String get _required =>
      'DELETE CONFIRMED DEVELOPMENT DATA ONLY ${_plan?.confirmationToken ?? ''}';
  bool get _targetConfirmed => _serial.text == target && _development;
  Future<void> _run(Future<String> Function() action) async {
    setState(() => _busy = true);
    try {
      final result = await action();
      if (mounted) setState(() => _status = result);
    } on ProtectedStorageException catch (e) {
      if (mounted) setState(() => _status = 'STOP: ${e.code}');
    } on EncryptionException catch (e) {
      if (mounted) setState(() => _status = 'STOP: ${e.code.name}');
    } on RecoveryException catch (e) {
      if (mounted) setState(() => _status = 'STOP: ${e.code.name}');
    } catch (_) {
      if (mounted) {
        setState(
          () => _status =
              'STOP: qualification operation failed; no exception contents displayed.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String> _preview() async {
    if (!enabled || !armed || !_targetConfirmed) {
      throw const ProtectedStorageException('operatorConfirmationRequired');
    }
    final plan = await EpcrStorageService().prepareDevelopmentReset(
      await getApplicationDocumentsDirectory(),
    );
    if (mounted) {
      setState(() {
        _plan = plan;
        _phrase.clear();
        _executeAuthorized = false;
      });
    }
    return 'PLAN ONLY: ${plan.fileCount} known files, ${plan.directoryCount} directories. No deletion performed. Keys and unrelated files are excluded.';
  }

  Future<String> _execute() async {
    if (!enabled ||
        !armed ||
        !_targetConfirmed ||
        !_executeAuthorized ||
        _plan == null ||
        _phrase.text != _required) {
      throw const ProtectedStorageException(
        'separateResetAuthorizationRequired',
      );
    }
    await EpcrStorageService().executeDevelopmentReset(
      _plan!,
      confirmation: _phrase.text,
    );
    if (mounted) {
      setState(() {
        _plan = null;
        _phrase.clear();
        _executeAuthorized = false;
      });
    }
    return 'Reset completed for confirmed development-only target. Keystore keys/index and unrelated files retained. Stop for next review step.';
  }

  Widget _testButton(String label, Future<String> Function() action) =>
      ElevatedButton(
        onPressed: enabled && !_busy && _targetConfirmed && _synthetic && !armed
            ? () => _run(action)
            : null,
        child: Text(label),
      );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        armed
            ? 'ARMED development reset harness'
            : 'UNARMED synthetic qualification harness',
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (!enabled)
          const Text(
            'DISABLED: debug qualification define required. No storage action is available.',
          ),
        const Text(
          'Target R95Y804S2PV only. Verify the serial externally with ADB. This text entry is operator attestation, not automatic device identity verification.',
        ),
        TextField(
          controller: _serial,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Confirmed ADB serial (enter exactly)',
          ),
        ),
        CheckboxListTile(
          value: _development,
          onChanged: _busy
              ? null
              : (value) => setState(() => _development = value ?? false),
          title: const Text(
            'Operator confirms this is the authorized development-only tablet; no real patient records.',
          ),
        ),
        if (armed) ...[
          ElevatedButton(
            onPressed: enabled && !_busy && _targetConfirmed
                ? () => _run(_preview)
                : null,
            child: const Text(
              'Preview exact development reset plan (no deletion)',
            ),
          ),
          if (_plan != null) ...[
            Text(
              '${_plan!.fileCount} known files; ${_plan!.directoryCount} directories',
            ),
            const Text(
              'Exact relative files to delete (contents never displayed):',
            ),
            ..._plan!.relativeFiles.map((p) => SelectableText(p)),
            const Text('Exact empty directories to remove after files:'),
            ..._plan!.relativeDirectories.map((p) => SelectableText(p)),
            const Text(
              'Separate operator authorization required. Exact confirmation phrase:',
            ),
            SelectableText(_required),
            TextField(
              controller: _phrase,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Type the complete phrase; never prefilled',
              ),
            ),
            CheckboxListTile(
              value: _executeAuthorized,
              onChanged: _busy
                  ? null
                  : (value) =>
                        setState(() => _executeAuthorized = value ?? false),
              title: const Text(
                'I separately authorize deletion of exactly the reviewed development reset plan.',
              ),
            ),
            ElevatedButton(
              onPressed:
                  enabled &&
                      !_busy &&
                      _targetConfirmed &&
                      _executeAuthorized &&
                      _phrase.text == _required
                  ? () => _run(_execute)
                  : null,
              child: const Text('Execute authorized development reset'),
            ),
          ],
        ] else ...[
          CheckboxListTile(
            value: _synthetic,
            onChanged: _busy
                ? null
                : (value) => setState(() => _synthetic = value ?? false),
            title: const Text(
              'Authorize synthetic tests only in the isolated app-private qualification namespace. Existing normal records are not a test target.',
            ),
          ),
          _testButton(
            '1. Synthetic create / read / update (repeat offline)',
            _cases.basic,
          ),
          _testButton('2. Real autosave timer / flush', _cases.autosave),
          _testButton(
            '3. Verify restart / queue persistence',
            _cases.verifyRestart,
          ),
          _testButton(
            '4. Bounded ENOSPC injection (no filler files)',
            _cases.boundedSpaceFailure,
          ),
          _testButton(
            '5. Tamper synthetic ciphertext and restore it',
            _cases.tamper,
          ),
          _testButton(
            '6. Pause before rename for operator process termination',
            () => _cases.pauseBeforePublication((message) {
              if (mounted) setState(() => _status = message);
            }),
          ),
          if (_busy && _cases.pause != null)
            ElevatedButton(
              onPressed: _cases.cancelPause,
              child: const Text('Cancel paused save (retain prior revision)'),
            ),
        ],
        const Divider(),
        SelectableText(_status),
        const Text(
          'No private-key access, AWS, network upload, application uninstall, app-data clearing, automatic reset or power interruption is provided.',
        ),
      ],
    ),
  );
  @override
  void dispose() {
    _serial.dispose();
    _phrase.dispose();
    super.dispose();
  }
}
