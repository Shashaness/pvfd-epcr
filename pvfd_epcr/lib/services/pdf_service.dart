import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../domain/models/record_json.dart';

/// Document generation only: no platform printing or mutable editor access.
class PdfService {
  Future<Uint8List> generate(Map<String, dynamic> pcr) async {
    final pdf = pw.Document();

    final incident = recordMap(pcr["incident"]);
    final patient = recordMap(pcr["patient"]);
    final crew = recordMap(pcr["crew"]);
    final contacts = recordMap(pcr["contacts"]);
    final formCompletion = recordMap(pcr["formCompletion"]);
    final clinical = recordMap(pcr["clinical"]);
    final vitalsForPdf = (recordList(
      clinical["vitals"],
    )).whereType<Map>().map((v) => Map<String, dynamic>.from(v)).toList();

    final created = DateTime.tryParse(
      incident["dateTimeCreated"]?.toString() ?? "",
    );

    String value(dynamic v) {
      final text = v?.toString().trim() ?? "";
      return text.isEmpty ? "Not entered" : text;
    }

    String blank(dynamic v) {
      return v?.toString().trim() ?? "";
    }

    String bloodPressure(Map<String, dynamic> vital) {
      final systolic = blank(vital["systolic"]);
      final diastolic = blank(vital["diastolic"]);

      if (systolic.isEmpty && diastolic.isEmpty) return "";
      if (systolic.isEmpty) return "/$diastolic";
      if (diastolic.isEmpty) return "$systolic/";
      return "$systolic/$diastolic";
    }

    pw.Widget sectionTitle(String title) {
      return pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(6),
        margin: const pw.EdgeInsets.only(top: 14, bottom: 6),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey300,
          border: pw.Border.all(color: PdfColors.grey700),
        ),
        child: pw.Text(
          title,
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
      );
    }

    pw.Widget row(String label, String text) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 5),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 120,
              child: pw.Text(
                label,
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.Expanded(child: pw.Text(text)),
          ],
        ),
      );
    }

    pw.Widget narrativeBox(String text) {
      return pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey600),
        ),
        child: pw.Text(value(text)),
      );
    }

    pw.Widget vitalsTable() {
      if (vitalsForPdf.isEmpty) {
        return pw.Text('No vitals entered.');
      }

      return pw.TableHelper.fromTextArray(
        headers: const ['Time', 'Pulse', 'O2 Sat', 'BP', 'Temp', 'BGL'],
        data: vitalsForPdf.map((vital) {
          return [
            blank(vital["timeDisplay"]),
            blank(vital["pulse"]),
            blank(vital["o2Sat"]),
            bloodPressure(vital),
            blank(vital["temp"]),
            blank(vital["bloodGlucose"]),
          ];
        }).toList(),
        border: pw.TableBorder.all(color: PdfColors.grey600),
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
        cellAlignment: pw.Alignment.centerLeft,
        cellPadding: const pw.EdgeInsets.all(5),
      );
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(36),
        footer: (context) {
          return pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 9),
            ),
          );
        },
        build: (context) => [
          pw.Center(
            child: pw.Column(
              children: [
                pw.Text(
                  'Pleasant Valley Fire District',
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  'Electronic Patient Care Report',
                  style: const pw.TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 18),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.black),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                row('ePCR Number:', value(pcr["epcrNumber"])),
                row('Incident Number:', value(incident["incidentNumber"])),
                row('Incident Address:', value(incident["incidentAddress"])),
                row(
                  'Responders:',
                  value(recordList(incident["responders"]).join(', ')),
                ),
                row(
                  'Forest Land:',
                  incident["forestLand"] == true ? 'Yes' : 'No',
                ),
                row('GPS Coordinates:', value(incident["gpsCoordinates"])),
                row(
                  'Created:',
                  created == null ? 'Not entered' : created.toString(),
                ),
                row('NEMSIS Target:', value(pcr["nemsisVersionTarget"])),
              ],
            ),
          ),
          sectionTitle('Patient Information'),
          row('First Name:', value(patient["firstName"])),
          row('Last Name:', value(patient["lastName"])),
          row('Age:', value(patient["age"])),
          row('Gender:', value(patient["gender"])),
          sectionTitle('Crew / Provider'),
          row('Provider Level:', value(crew["levelOfCare"])),
          sectionTitle('Chief Complaint'),
          narrativeBox(value(clinical["chiefComplaint"])),

          sectionTitle('PMH'),
          narrativeBox(value(readPmh(pcr).join(', '))),

          sectionTitle('Allergies'),
          narrativeBox(value(clinical["allergies"])),

          sectionTitle('Medications'),
          narrativeBox(value(clinical["medications"])),

          sectionTitle('Glasgow Coma Scale'),
          row('Eye:', value(clinical["glasgowComaScale"]?["eye"])),
          row('Verbal:', value(clinical["glasgowComaScale"]?["verbal"])),
          row('Motor:', value(clinical["glasgowComaScale"]?["motor"])),
          row('Total:', value(clinical["glasgowComaScale"]?["total"])),

          sectionTitle('Vitals'),
          vitalsTable(),
          sectionTitle('Assessment / Narrative'),
          narrativeBox(value(clinical["assessment"])),
          sectionTitle('Treatment Provided'),
          narrativeBox(value(clinical["treatment"])),
          sectionTitle('Disposition / Transport'),
          narrativeBox(value(clinical["disposition"])),
          sectionTitle('Additional Contacts'),
          row('Emergency Contact:', value(contacts["emergencyContactName"])),
          row(
            'Emergency Contact Number:',
            value(contacts["emergencyContactNumber"]),
          ),
          row('Reporting Party:', value(contacts["reportingParty"])),
          row(
            'Reporting Party Number:',
            value(contacts["reportingPartyNumber"]),
          ),
          sectionTitle('Form Completion'),
          row('Completed By:', value(formCompletion["completedBy"])),
          row(
            'Signature Captured:',
            (formCompletion["signaturePointCount"] as int? ?? 0) > 0
                ? 'Yes'
                : 'No',
          ),
          pw.SizedBox(height: 24),
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Container(
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      bottom: pw.BorderSide(color: PdfColors.black),
                    ),
                  ),
                  height: 24,
                ),
              ),
              pw.SizedBox(width: 24),
              pw.Expanded(
                child: pw.Container(
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      bottom: pw.BorderSide(color: PdfColors.black),
                    ),
                  ),
                  height: 24,
                ),
              ),
            ],
          ),
          pw.Row(
            children: [
              pw.Expanded(child: pw.Text('Signature')),
              pw.SizedBox(width: 24),
              pw.Expanded(child: pw.Text('Date')),
            ],
          ),
        ],
      ),
    );

    return await pdf.save();
  }
}
