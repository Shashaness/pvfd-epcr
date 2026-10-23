import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pvfd_epcr/qualification/qualification_app.dart';

void main() {
  testWidgets(
    'qualification defaults are disabled and perform no startup storage work',
    (tester) async {
      await tester.pumpWidget(const QualificationApp());
      expect(find.textContaining('DISABLED:'), findsOneWidget);
      for (final widget in tester.widgetList<ElevatedButton>(
        find.byType(ElevatedButton),
      )) {
        expect(widget.onPressed, isNull);
      }
      expect(tester.takeException(), isNull);
    },
  );
}
