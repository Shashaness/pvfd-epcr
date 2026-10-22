import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';
import 'package:pvfd_epcr/services/pdf_service.dart';
import 'package:pvfd_epcr/domain/models/epcr_record.dart';
import 'package:pvfd_epcr/services/nemsis_service.dart';
import 'package:pvfd_epcr/services/document_export_service.dart';
import 'support/synthetic_record.dart';
import 'support/pdf_structure.dart';

void main() {
  test(
    'PDF drawing streams match frozen Milestone 1 layout and signature lines',
    () async {
      final expected = jsonDecode(
        await File('test/fixtures/milestone_1_pdf_streams.json').readAsString(),
      );
      final streams = pdfStreams(await PdfService().generate(syntheticJson()));
      expect(streams, isNotEmpty);
      expect(streams, expected);
      final content = RegExp(
        r'\[\((.*?)\)\]TJ',
      ).allMatches(streams.join()).map((m) => m.group(1)).join(' ');
      expect(content, contains('Signature'));
      expect(content, contains('Date'));
      expect(content, contains('Synthetic Responder'));
      expect(content, contains('Synthetic allergy'));
    },
  );
  test(
    'XML matches frozen structure, mappings, identities and escaping',
    () async {
      final snapshot = syntheticSnapshot();
      final xml = NemsisService().generate(
        snapshot.record.toJson(),
        epcrNumber: snapshot.id,
        dateTimeCreated: snapshot.dateTimeCreated,
      );
      final expected = await File(
        'test/fixtures/milestone_1_synthetic.xml',
      ).readAsString();
      expect(normalizeXmlTime(xml), expected);
      final document = XmlDocument.parse(xml);
      expect(
        document.findAllElements('ePatient.03').single.innerText,
        'Synthetic <A>',
      );
      expect(
        document.findAllElements('ePatient.02').single.innerText,
        'Test & Example',
      );
      expect(
        document.findAllElements('eRecord.01').single.innerText,
        syntheticId,
      );
      expect(xml, contains('Synthetic &lt;A'));
    },
  );
  test(
    'document export uses a detached snapshot and existing naming/directory convention',
    () async {
      final dir = await Directory.systemTemp.createTemp('synthetic_exports_');
      try {
        final raw = syntheticJson();
        final snapshot = EpcrDocumentSnapshot(
          record: EpcrRecord.fromJson(raw),
          id: syntheticId,
          dateTimeCreated: DateTime(2026, 10, 22, 14, 15, 30),
        );
        final service = DocumentExportService(
          documentsDirectory: () async => dir,
          temporaryDirectory: () async => Directory('${dir.path}/temporary'),
        );
        (raw['patient'] as Map)['firstName'] = 'Later edit';
        final pdf = await service.writePdf(snapshot);
        final xml = await service.writeXml(snapshot, temporary: true);
        expect(pdf.path, '${dir.path}/Exports/PVFD_ePCR_$syntheticId.pdf');
        expect(
          xml.path,
          '${dir.path}/temporary/Exports/PVFD_ePCR_$syntheticId.xml',
        );
        expect(await pdf.length(), greaterThan(0));
        expect(await xml.readAsString(), contains('Synthetic &lt;A'));
        // Export retention remains unchanged; neither service deletes outputs.
        expect(await pdf.exists(), true);
        expect(await xml.exists(), true);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
