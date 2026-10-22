import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pvfd_epcr/application/controllers/epcr_controller.dart';
import 'package:pvfd_epcr/domain/models/epcr_record.dart';
import 'package:pvfd_epcr/presentation/screens/epcr_editor_screen.dart';
import 'package:pvfd_epcr/presentation/widgets/add_vitals_dialog.dart';
import 'package:pvfd_epcr/presentation/widgets/pmh_section.dart';
import 'package:pvfd_epcr/presentation/widgets/responders_section.dart';
import 'support/memory_repository.dart';

Future<EpcrController> mountEditor(
  WidgetTester tester,
  MemoryRepository repository,
) async {
  final controller = EpcrController(repository: repository);
  await tester.pumpWidget(
    MaterialApp(home: PCRFormPage(controllerFactory: () => controller)),
  );
  await tester.pump();
  return controller;
}

Finder fieldLabel(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

void main() {
  testWidgets('drawer opens a historical record then New flushes edits', (
    tester,
  ) async {
    final repository = MemoryRepository();
    await repository.create(
      EpcrRecord.fromJson({
        'patient': {'firstName': 'Synthetic Existing'},
      }),
      idFactory: () => 'legacy',
    );
    final c = await mountEditor(tester, repository);
    expect(find.text('PVFD ePCR'), findsOneWidget);
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('List'));
    await tester.pumpAndSettle();
    expect(find.text('ePCR legacy'), findsOneWidget);
    await tester.tap(find.text('ePCR legacy'));
    await tester.pumpAndSettle();
    expect(c.firstName.text, 'Synthetic Existing');
    expect(
      repository.writes,
      1,
    ); // Listing and opening never rewrote the record.
    c.assessment.text = 'Synthetic clinical edit';
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New'));
    await tester.pumpAndSettle();
    expect(c.epcrNumber, isNot('legacy'));
    expect(
      repository.records.values.first.clinical.assessment,
      'Synthetic clinical edit',
    );
    await c.flush();
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('PMH None and responders chips keep current interaction', (
    tester,
  ) async {
    final c = await mountEditor(tester, MemoryRepository());
    await tester.tap(find.widgetWithText(FilterChip, 'F1'));
    expect(c.selectedResponders, {'F1'});
    await tester.scrollUntilVisible(
      find.widgetWithText(FilterChip, 'Asthma'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.widgetWithText(FilterChip, 'Asthma'));
    await tester.pump();
    expect(c.selectedPMH, {'Asthma'});
    await tester.tap(find.widgetWithText(FilterChip, 'None'));
    await tester.pump();
    expect(c.selectedPMH, {'None'});
    await c.flush();
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'clinical text and GCS edits reach the authoritative controller',
    (tester) async {
      final c = await mountEditor(tester, MemoryRepository());
      await tester.scrollUntilVisible(
        fieldLabel('Allergies'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(fieldLabel('Allergies'), 'Synthetic UI allergy');
      expect(c.allergies.text, 'Synthetic UI allergy');
      await tester.scrollUntilVisible(
        find.text('Eye Opening'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byType(DropdownButtonFormField<int>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('3 - To voice').last);
      await tester.pumpAndSettle();
      expect(c.gcsEye, 3);
      expect(c.isDirty, true);
      await c.flush();
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'vitals dialog can close, reopen and rebuild without disposed fields',
    (tester) async {
      final c = await mountEditor(tester, MemoryRepository());
      await tester.scrollUntilVisible(
        find.text('Add Vitals'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Add Vitals'));
      await tester.pumpAndSettle();
      await tester.enterText(fieldLabel('Pulse'), '80');
      await tester.tap(find.text('Save Vitals'));
      await tester.pumpAndSettle();
      expect(c.vitals.single['pulse'], '80');
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Add Vitals'));
      await tester.pumpAndSettle();
      expect(find.byType(AddVitalsDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await c.flush();
      await tester.pumpWidget(const SizedBox());
      await mountEditor(tester, MemoryRepository());
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('PMH and responder display filters survive scrolling', (
    tester,
  ) async {
    final c = await mountEditor(tester, MemoryRepository());
    await tester.tap(find.widgetWithText(FilterChip, 'F1'));
    final responderToggle = find.descendant(
      of: find.byType(RespondersSection),
      matching: find.widgetWithText(TextButton, 'Show Selected'),
    );
    await tester.tap(responderToggle);
    await tester.pump();
    expect(find.widgetWithText(FilterChip, 'F2'), findsNothing);
    await tester.scrollUntilVisible(
      find.widgetWithText(FilterChip, 'Asthma'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.widgetWithText(FilterChip, 'Asthma'));
    final pmhToggle = find.descendant(
      of: find.byType(PmhSection),
      matching: find.widgetWithText(TextButton, 'Show Selected'),
    );
    await tester.tap(pmhToggle);
    await tester.pump();
    expect(find.widgetWithText(FilterChip, 'Diabetes'), findsNothing);
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    scroll.position.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    scroll.position.jumpTo(0);
    await tester.pump();
    expect(find.widgetWithText(FilterChip, 'F2'), findsNothing);
    expect(find.widgetWithText(FilterChip, 'Diabetes'), findsNothing);
    expect(c.selectedPMH, {'Asthma'});
    expect(c.selectedResponders, {'F1'});
    await c.flush();
    await tester.pumpWidget(const SizedBox());
  });
}
