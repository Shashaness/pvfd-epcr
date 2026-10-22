import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:pvfd_epcr/application/controllers/epcr_controller.dart';
import 'package:pvfd_epcr/domain/models/epcr_record.dart';
import 'support/memory_repository.dart';

void main() {
  testWidgets('750ms debounce restarts on edits and exposes dirty revisions', (
    tester,
  ) async {
    final repository = MemoryRepository();
    final controller = EpcrController(repository: repository);
    expect(controller.isDirty, false);
    controller.firstName.text = 'Synthetic first edit';
    final revision = controller.revision;
    expect(controller.isDirty, true);
    await tester.pump(const Duration(milliseconds: 749));
    expect(repository.writes, 0);
    controller.firstName.text = 'Synthetic latest edit';
    expect(controller.revision, greaterThan(revision));
    await tester.pump(const Duration(milliseconds: 749));
    expect(repository.writes, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(repository.writes, 1);
    expect(
      repository.records.values.single.patient.firstName,
      'Synthetic latest edit',
    );
    expect(controller.isDirty, false);
    controller.dispose();
  });
  test(
    'opening and listing do not write or clear unsupported clinical values',
    () async {
      final repository = MemoryRepository();
      final controller = EpcrController(repository: repository);
      controller.assessment.text = 'Synthetic';
      await controller.flush();
      final records = await controller.loadPCRs();
      final writes = repository.writes;
      await controller.loadPCR(records.single);
      expect(repository.writes, writes);
      expect(controller.isDirty, false);
      controller.dispose();
    },
  );
  test(
    'older completion cannot clear a newer edit; snapshot is stable',
    () async {
      final repository = MemoryRepository();
      final gate = Completer<void>();
      repository.gate = gate.future;
      final controller = EpcrController(repository: repository);
      controller.assessment.text = 'Synthetic old';
      final pending = controller.autoSavePCR();
      expect(controller.isSaving, true);
      controller.assessment.text = 'Synthetic new';
      expect(repository.requested!.clinical.assessment, 'Synthetic old');
      gate.complete();
      await pending;
      expect(controller.isSaving, false);
      expect(controller.isDirty, true);
      await controller.flush();
      expect(controller.isDirty, false);
      expect(
        repository.records.values.single.clinical.assessment,
        'Synthetic new',
      );
      controller.dispose();
    },
  );
  test(
    'failed save exposes generic error, retains dirty state and retries',
    () async {
      final repository = MemoryRepository()..fail = true;
      final controller = EpcrController(repository: repository);
      controller.firstName.text = 'Synthetic pending';
      expect(await controller.flush(), false);
      expect(controller.isDirty, true);
      expect(controller.isSaving, false);
      expect(controller.lastError, contains('Edits remain pending'));
      repository.fail = false;
      expect(await controller.flush(), true);
      expect(controller.isDirty, false);
      expect(controller.lastError, isNull);
      controller.dispose();
    },
  );
  test(
    'disposing during a failed save neither reuses fields nor emits late notifications',
    () async {
      final repository = MemoryRepository()..fail = true;
      final gate = Completer<void>();
      repository.gate = gate.future;
      final controller = EpcrController(repository: repository);
      var messages = 0;
      controller.onMessage = (_) => messages++;
      controller.firstName.text = 'Synthetic final edit';
      controller.dispose();
      gate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(messages, 0);
      expect(controller.isSaving, false);
      expect(controller.isDirty, true);
      // Pending reset/open continuations are disposed-aware.
      await controller.resetForm();
      expect(() => controller.firstName.addListener(() {}), throwsFlutterError);
    },
  );
  test(
    'export snapshot stays with its requested record after disposal',
    () async {
      final repository = MemoryRepository();
      final gate = Completer<void>();
      repository.gate = gate.future;
      final controller = EpcrController(repository: repository);
      controller.assessment.text = 'Synthetic requested document';
      final id = controller.epcrNumber;
      final pending = controller.autoSavePCR();
      controller.assessment.text = 'Synthetic later edit';
      controller.dispose();
      gate.complete();
      final snapshot = await pending;
      expect(snapshot.id, id);
      expect(
        snapshot.record.clinical.assessment,
        'Synthetic requested document',
      );
      await Future<void>.delayed(Duration.zero);
    },
  );
  test(
    'empty legacy JSON stays bound to its original path without inventing persisted IDs',
    () async {
      final repository = MemoryRepository();
      const path = '/synthetic/pcr_legacy.json';
      repository.records[path] = EpcrRecord.fromJson({}, sourcePath: path);
      final controller = EpcrController(repository: repository);
      await controller.loadPCR((await controller.loadPCRs()).single);
      expect(repository.writes, 0);
      controller.assessment.text = 'Synthetic recovered edit';
      await controller.flush();
      expect(repository.records.length, 1);
      final saved = repository.records[path]!;
      expect(saved.clinical.assessment, 'Synthetic recovered edit');
      expect(saved.toJson().containsKey('epcrNumber'), false);
      expect(saved.toJson().containsKey('appRecordId'), false);
      controller.dispose();
    },
  );
}
