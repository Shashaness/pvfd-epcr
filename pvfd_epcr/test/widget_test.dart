import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pvfd_epcr/presentation/screens/epcr_editor_screen.dart';
import 'package:pvfd_epcr/application/controllers/epcr_controller.dart';
import 'package:pvfd_epcr/application/services/epcr_lifecycle_service.dart';
import 'package:pvfd_epcr/data/repositories/epcr_repository.dart';
import 'package:pvfd_epcr/services/nemsis_service.dart';
import 'package:pvfd_epcr/services/pdf_service.dart';
import 'package:pvfd_epcr/services/epcr_storage_service.dart';

void main() {
  late Directory dir;
  setUp(
    () async => dir = await Directory.systemTemp.createTemp('synthetic_form_'),
  );
  tearDown(() async => dir.delete(recursive: true));

  Future<dynamic> mount(
    WidgetTester tester, {
    EpcrStorageService? storage,
  }) async {
    final controller = EpcrController(
      repository: LocalEpcrRepository(
        documentsDirectory: () async => dir,
        storage: storage,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PCRFormPage(
          documentsDirectory: () async => dir,
          storage: storage,
          controllerFactory: () => controller,
        ),
      ),
    );
    await tester.runAsync(() async => Future<void>.delayed(Duration.zero));
    return controller;
  }

  for (final pmh in [
    <String>[],
    ['Asthma'],
    ['Asthma', 'Diabetes'],
    ['None'],
    ['Future condition', 'HTN'],
  ]) {
    testWidgets('PMH save load save preserves $pmh and other clinical data', (
      tester,
    ) async {
      final dynamic state = await mount(tester);
      state.selectedPMH.addAll(pmh);
      state.assessment.text = 'Synthetic assessment';
      await tester.runAsync(() async {
        await state.autoSavePCR();
        final record = (await state.loadPCRs()).single;
        await state.loadPCR(record);
        expect(state.selectedPMH, containsAll(pmh));
        await state.autoSavePCR();
        final saved = (await state.loadPCRs()).single;
        expect(readPmh(saved), pmh);
        expect(
          recordMap(saved['clinical'])['assessment'],
          'Synthetic assessment',
        );
      });
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'legacy malformed values open safely; opening never rewrites file; edits preserve unknown fields',
    (tester) async {
      final file = File('${dir.path}/pcr_legacy.json');
      const content =
          '{"epcrNumber":"legacy","patient":{"gender":"Future"},"incident":{"pmh":["Future condition"]},"clinical":{"vitals":42,"glasgowComaScale":{"eye":99},"future":true},"crew":42,"future":123}';
      await tester.runAsync(() => file.writeAsString(content));
      final dynamic state = await mount(tester);
      await tester.runAsync(() async {
        await state.loadPCR((await state.loadPCRs()).single);
      });
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      expect(await tester.runAsync(() => file.readAsString()), content);
      state.assessment.text = 'Synthetic edit';
      await tester.runAsync(() async {
        await state.autoSavePCR();
        final saved = await EpcrStorageService().read(file);
        expect(saved['future'], 123);
        expect(saved['crew'], 42);
        expect(recordMap(saved['clinical'])['vitals'], 42);
        expect(recordMap(saved['clinical'])['future'], true);
        expect(readPmh(saved), ['Future condition']);
      });
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'record switching flushes pending edits to original destination',
    (tester) async {
      final dynamic state = await mount(tester);
      state.firstName.text = 'Synthetic A';
      final second = (await tester.runAsync(
        () => EpcrStorageService().create(dir, {
          'patient': {'firstName': 'Synthetic B'},
        }),
      ))!;
      await tester.runAsync(() async {
        await state.loadPCR({
          ...await EpcrStorageService().read(second),
          '_filePath': second.path,
        });
        expect(state.firstName.text, 'Synthetic B');
        final records = await state.loadPCRs();
        expect(records.length, 2);
        expect(
          records.map((r) => recordMap(r['patient'])['firstName']),
          containsAll(['Synthetic A', 'Synthetic B']),
        );
      });
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('failed autosave keeps edits and prevents switch until retry', (
    tester,
  ) async {
    var fail = true;
    final dynamic state = await mount(
      tester,
      storage: EpcrStorageService(
        beforeReplace: (_, target) async {
          if (fail) throw const FileSystemException('Synthetic failure');
        },
      ),
    );
    state.firstName.text = 'Synthetic unsaved';
    final second = (await tester.runAsync(
      () => EpcrStorageService().create(dir, {
        'patient': {'firstName': 'Synthetic B'},
      }),
    ))!;
    await tester.runAsync(() async {
      await state.loadPCR({
        ...await EpcrStorageService().read(second),
        '_filePath': second.path,
      });
      expect(state.firstName.text, 'Synthetic unsaved');
      fail = false;
      await state.savePCR();
      expect((await state.loadPCRs()).length, 2);
    });
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('new record flushes edits before reset and keeps identifiers', (
    tester,
  ) async {
    final dynamic state = await mount(tester);
    final oldId = state.epcrNumber;
    state.firstName.text = 'Synthetic prior record';
    await tester.runAsync(() async {
      await state.resetForm();
      expect(state.epcrNumber, isNot(oldId));
      await state.autoSavePCR();
      final records = await state.loadPCRs();
      expect(records.length, 2);
      expect(records.map((r) => r['epcrNumber']), contains(oldId));
    });
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('background lifecycle flushes pending edits', (tester) async {
    final dynamic state = await mount(tester);
    state.firstName.text = 'Synthetic background';
    await tester.runAsync(() async {
      EpcrLifecycleService(
        state,
      ).didChangeAppLifecycleState(AppLifecycleState.paused);
      // Await the same destination queue after the lifecycle snapshot.
      await state.autoSavePCR();
      final records = await state.loadPCRs();
      expect(
        recordMap(records.single['patient'])['firstName'],
        'Synthetic background',
      );
    });
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'in-progress write cannot redirect pending edits to another record',
    (tester) async {
      late Completer<void> entered;
      late Completer<void> release;
      var calls = 0;
      final dynamic state = await mount(
        tester,
        storage: EpcrStorageService(
          beforeReplace: (_, target) async {
            if (calls++ == 0) {
              entered.complete();
              await release.future;
            }
          },
        ),
      );
      await tester.runAsync(() async {
        entered = Completer<void>();
        release = Completer<void>();
        final second = await EpcrStorageService().create(dir, {
          'patient': {'firstName': 'Synthetic B'},
        });
        state.firstName.text = 'Synthetic A1';
        final first = state.autoSavePCR() as Future<void>;
        await entered.future;
        state.firstName.text = 'Synthetic A2';
        final switching =
            state.loadPCR({
                  ...await EpcrStorageService().read(second),
                  '_filePath': second.path,
                })
                as Future<void>;
        release.complete();
        await first;
        await switching;
        expect(state.firstName.text, 'Synthetic B');
        final records = await state.loadPCRs();
        expect(
          records.map((r) => recordMap(r['patient'])['firstName']),
          containsAll(['Synthetic A2', 'Synthetic B']),
        );
      });
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('None UI selection preserves unknown historical PMH in storage', (
    tester,
  ) async {
    final dynamic state = await mount(tester);
    await tester.runAsync(() async {
      final file = await EpcrStorageService().create(dir, {
        'clinical': {
          'pmh': ['Future condition', 'HTN'],
        },
      });
      await state.loadPCR({
        ...await EpcrStorageService().read(file),
        '_filePath': file.path,
      });
      state.selectedPMH
        ..clear()
        ..add('None');
      await state.autoSavePCR();
      expect(readPmh(await EpcrStorageService().read(file)), [
        'None',
        'Future condition',
      ]);
    });
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('PDF and XML generation retain clinical and incident features', (
    tester,
  ) async {
    final dynamic state = await mount(tester);
    state.selectedPMH.addAll(['Asthma', 'HTN']);
    state.selectedResponders.add('F1');
    state.allergies.text = 'Synthetic allergy';
    state.medications.text = 'Synthetic medication';
    state.forestLand = true;
    state.gpsCoordinates.text = '34.10, -110.90';
    state.gcsEye = 3;
    state.vitals.add({
      'pulse': '80',
      'dateTime': DateTime(2026, 10, 22).toIso8601String(),
    });
    await tester.runAsync(() async {
      await state.autoSavePCR();
      final record = state.buildPCRJson() as Map<String, dynamic>;
      final xml = NemsisService().generate(
        record,
        epcrNumber: state.epcrNumber,
        dateTimeCreated: state.dateTimeCreated,
      );
      expect(xml, contains('<eRecord.01>'));
      expect(xml, contains(state.epcrNumber as String));
      expect(xml, contains('Synthetic allergy'));
      expect(xml, contains('Synthetic medication'));
      expect(xml, contains('F1'));
      final pdf = await PdfService().generate(record);
      expect(pdf.take(4).toList(), [37, 80, 68, 70]);
      expect(recordMap(record['incident'])['forestLand'], true);
      expect(recordMap(record['incident'])['gpsCoordinates'], '34.10, -110.90');
      expect(
        recordMap(recordMap(record['clinical'])['glasgowComaScale'])['eye'],
        3,
      );
    });
    await tester.pumpWidget(const SizedBox());
  });
}
