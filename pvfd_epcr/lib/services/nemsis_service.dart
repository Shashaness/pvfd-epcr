import 'dart:convert';
import 'dart:math';
import 'package:xml/xml.dart';
import '../domain/models/record_json.dart';

/// Existing mappings, extracted unchanged; not a conformance assertion.
class NemsisService {
  // ---------------------------------------------------------------------------
  // NEMSIS 3.5.1 XML EXPORT
  // ---------------------------------------------------------------------------
  // Important:
  // This produces a much more correct NEMSIS-shaped EMSDataSet than the earlier
  // starter export. However, true "100% NEMSIS compliant" output depends on:
  //   1) your official Arizona/PVFD agency identifiers,
  //   2) Arizona-required fields and code values,
  //   3) the official NEMSIS 3.5.1 XSD package,
  //   4) the National + Arizona Schematron rules.
  //
  // Replace the PVFD_* constants below with your real values before using this
  // for submission/import into ImageTrend or any state repository.

  static const String pvfdAgencyNumber = 'PVFD-AGENCY-NUMBER';
  static const String pvfdAgencyName = 'Pleasant Valley Fire District';
  static const String pvfdStateCode = '04'; // Arizona FIPS/state code.
  static const String nemsisVersion = '3.5.1';

  String _xmlText(dynamic value) {
    return value?.toString().trim() ?? '';
  }

  bool _hasText(dynamic value) {
    return _xmlText(value).isNotEmpty;
  }

  String _isoWithOffset(DateTime dt) {
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    String three(int n) => n.toString().padLeft(3, '0');

    final offset = local.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final absOffset = offset.abs();
    final hours = two(absOffset.inHours);
    final minutes = two(absOffset.inMinutes.remainder(60));

    return '${local.year}-${two(local.month)}-${two(local.day)}T'
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}.'
        '${three(local.millisecond)}$sign$hours:$minutes';
  }

  String _stableUuid(String seed) {
    // Produces a valid RFC-4122-shaped UUID without adding another dependency.
    // This is deterministic for a given seed, which helps re-export the same PCR.
    final bytes = utf8.encode(seed);
    int hash = 0x811C9DC5;
    for (final b in bytes) {
      hash ^= b;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }

    final r = Random(hash);
    final values = List<int>.generate(16, (_) => r.nextInt(256));
    values[6] = (values[6] & 0x0F) | 0x40; // version 4
    values[8] = (values[8] & 0x3F) | 0x80; // variant

    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    final h = values.map(hex).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
        '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  String _nemsisGenderCode(String gender) {
    switch (gender.trim().toLowerCase()) {
      case 'male':
        return '9906003';
      case 'female':
        return '9906001';
      default:
        return '9906005'; // Unknown / unable to determine.
    }
  }

  void _nemsisElement(
    XmlBuilder builder,
    String name,
    dynamic value, {
    String? notValue,
    Map<String, String> attributes = const {},
  }) {
    final text = _xmlText(value);

    builder.element(
      name,
      nest: () {
        for (final entry in attributes.entries) {
          builder.attribute(entry.key, entry.value);
        }

        if (text.isEmpty) {
          // NEMSIS commonly uses xsi:nil plus NV/PN attributes for values that are
          // not documented, not applicable, or not known. 7701003 = Not Recorded.
          builder.attribute('xsi:nil', 'true');
          builder.attribute('NV', notValue ?? '7701003');
        } else {
          builder.text(text);
        }
      },
    );
  }

  void _nemsisComment(XmlBuilder builder, String text) {
    builder.comment(' $text ');
  }

  String generate(
    Map<String, dynamic> pcr, {
    required String epcrNumber,
    required DateTime dateTimeCreated,
  }) {
    final builder = XmlBuilder();

    final incident = recordMap(pcr['incident']);
    final patient = recordMap(pcr['patient']);
    final crew = recordMap(pcr['crew']);
    final contacts = recordMap(pcr['contacts']);
    final formCompletion = recordMap(pcr['formCompletion']);
    final clinical = recordMap(pcr['clinical']);
    final gcs = recordMap(clinical['glasgowComaScale']);
    final vitalsList = recordList(
      clinical['vitals'],
    ).whereType<Map>().map((v) => Map<String, dynamic>.from(v)).toList();

    final created =
        DateTime.tryParse(_xmlText(incident['dateTimeCreated'])) ??
        dateTimeCreated;

    final emsDataSetUuid = _stableUuid('EMSDataSet-$epcrNumber');
    final pcrUuid = _stableUuid('PatientCareReport-$epcrNumber');

    final incidentNumberText = _hasText(incident['incidentNumber'])
        ? incident['incidentNumber']
        : epcrNumber;
    final patientFirst = _xmlText(patient['firstName']);
    final patientLast = _xmlText(patient['lastName']);
    final patientAge = _xmlText(patient['age']);
    final patientGenderCode = _nemsisGenderCode(_xmlText(patient['gender']));
    final createdIso = _isoWithOffset(created);
    final narrative = [
      if (_hasText(clinical['assessment']))
        'Assessment: ${_xmlText(clinical['assessment'])}',
      if (_hasText(clinical['treatment']))
        'Treatment: ${_xmlText(clinical['treatment'])}',
      if (_hasText(clinical['disposition']))
        'Disposition: ${_xmlText(clinical['disposition'])}',
      if (_hasText(clinical['allergies']))
        'Allergies: ${_xmlText(clinical['allergies'])}',
      if (_hasText(clinical['medications']))
        'Medications: ${_xmlText(clinical['medications'])}',
      'GCS: E${_xmlText(gcs['eye'])} V${_xmlText(gcs['verbal'])} M${_xmlText(gcs['motor'])} = ${_xmlText(gcs['total'])}',
      'Level of care: ${_xmlText(crew['levelOfCare'])}',
      if (recordList(incident['responders']).isNotEmpty)
        'Responders: ${recordList(incident['responders']).join(', ')}',
      'Forest Land: ${incident['forestLand'] == true ? 'Yes' : 'No'}',
      if (_hasText(incident['gpsCoordinates']))
        'GPS Coordinates: ${_xmlText(incident['gpsCoordinates'])}',
      if (_hasText(contacts['emergencyContactName']))
        'Emergency Contact: ${_xmlText(contacts['emergencyContactName'])}',
      if (_hasText(contacts['emergencyContactNumber']))
        'Emergency Contact Number: ${_xmlText(contacts['emergencyContactNumber'])}',
      if (_hasText(contacts['reportingParty']))
        'Reporting Party: ${_xmlText(contacts['reportingParty'])}',
      if (_hasText(contacts['reportingPartyNumber']))
        'Reporting Party Number: ${_xmlText(contacts['reportingPartyNumber'])}',
      if (_hasText(formCompletion['completedBy']))
        'Form completed by: ${_xmlText(formCompletion['completedBy'])}',
      'Signature captured: ${(formCompletion['signaturePointCount'] as int? ?? 0) > 0 ? 'Yes' : 'No'}',
    ].join('\n');

    builder.processing('xml', 'version="1.0" encoding="UTF-8"');

    builder.element(
      'EMSDataSet',
      nest: () {
        builder.attribute('xmlns', 'http://www.nemsis.org');
        builder.attribute(
          'xmlns:xsi',
          'http://www.w3.org/2001/XMLSchema-instance',
        );
        builder.attribute('UUID', emsDataSetUuid);

        builder.element(
          'Header',
          nest: () {
            builder.element(
              'DemographicGroup',
              nest: () {
                _nemsisElement(builder, 'dAgency.01', pvfdAgencyNumber);
                _nemsisElement(builder, 'dAgency.02', pvfdAgencyNumber);
                _nemsisElement(builder, 'dAgency.03', pvfdAgencyName);
                _nemsisElement(builder, 'dAgency.04', pvfdStateCode);
              },
            );
          },
        );

        builder.element(
          'PatientCareReport',
          nest: () {
            builder.attribute('UUID', pcrUuid);

            // eRecord: record identity.
            builder.element(
              'eRecord',
              nest: () {
                _nemsisElement(builder, 'eRecord.01', incidentNumberText);
                _nemsisElement(builder, 'eRecord.02', nemsisVersion);
              },
            );

            // eResponse: incident/response identity. Several state-required response
            // values are not collected by the current GUI yet, so they are nil-coded.
            builder.element(
              'eResponse',
              nest: () {
                _nemsisElement(builder, 'eResponse.01', incidentNumberText);
                _nemsisElement(builder, 'eResponse.03', incidentNumberText);
                _nemsisElement(builder, 'eResponse.05', crew['levelOfCare']);
                _nemsisElement(builder, 'eResponse.07', null);
                _nemsisElement(builder, 'eResponse.09', null);
                _nemsisElement(
                  builder,
                  'eResponse.23',
                  incident['incidentAddress'],
                );
              },
            );

            // eDispatch: required section in many validation profiles, but not yet
            // captured in the GUI.
            builder.element(
              'eDispatch',
              nest: () {
                _nemsisElement(builder, 'eDispatch.01', null);
                _nemsisElement(builder, 'eDispatch.02', null);
              },
            );

            // eTimes: currently we only know when the PCR/incident was created.
            builder.element(
              'eTimes',
              nest: () {
                _nemsisElement(builder, 'eTimes.01', createdIso);
                _nemsisElement(builder, 'eTimes.03', createdIso);
                _nemsisElement(builder, 'eTimes.05', null);
                _nemsisElement(builder, 'eTimes.06', null);
                _nemsisElement(builder, 'eTimes.07', null);
                _nemsisElement(builder, 'eTimes.09', null);
                _nemsisElement(builder, 'eTimes.11', null);
                _nemsisElement(builder, 'eTimes.12', null);
                _nemsisElement(builder, 'eTimes.13', null);
              },
            );

            // ePatient.
            builder.element(
              'ePatient',
              nest: () {
                _nemsisElement(builder, 'ePatient.01', null);
                _nemsisElement(builder, 'ePatient.02', patientLast);
                _nemsisElement(builder, 'ePatient.03', patientFirst);
                _nemsisElement(builder, 'ePatient.13', patientGenderCode);
                _nemsisElement(builder, 'ePatient.15', patientAge);
                if (_hasText(patientAge)) {
                  _nemsisElement(builder, 'ePatient.16', '2516009'); // Years.
                } else {
                  _nemsisElement(builder, 'ePatient.16', null);
                }
              },
            );

            // eSituation.
            builder.element(
              'eSituation',
              nest: () {
                _nemsisElement(builder, 'eSituation.01', null);
                _nemsisElement(builder, 'eSituation.02', null);
                _nemsisElement(
                  builder,
                  'eSituation.07',
                  clinical['chiefComplaint'],
                );
                _nemsisElement(
                  builder,
                  'eSituation.09',
                  clinical['chiefComplaint'],
                );
              },
            );

            // eHistory.
            builder.element(
              'eHistory',
              nest: () {
                _nemsisElement(builder, 'eHistory.06', clinical['allergies']);
                _nemsisElement(builder, 'eHistory.12', clinical['medications']);
              },
            );

            // eVitals. One group per vitals row.
            if (vitalsList.isEmpty) {
              builder.element(
                'eVitals',
                nest: () {
                  _nemsisElement(builder, 'eVitals.01', null);
                  _nemsisElement(builder, 'eVitals.06', null);
                  _nemsisElement(builder, 'eVitals.10', null);
                  _nemsisElement(builder, 'eVitals.12', null);
                  _nemsisElement(builder, 'eVitals.14', null);
                  _nemsisElement(builder, 'eVitals.16', null);
                  _nemsisElement(builder, 'eVitals.18', null);
                  _nemsisElement(builder, 'eVitals.19', null);
                },
              );
            } else {
              for (final vital in vitalsList) {
                builder.element(
                  'eVitals',
                  nest: () {
                    _nemsisElement(
                      builder,
                      'eVitals.01',
                      vital['dateTime'] ?? createdIso,
                    );
                    _nemsisElement(builder, 'eVitals.06', vital['systolic']);
                    _nemsisElement(builder, 'eVitals.10', vital['diastolic']);
                    _nemsisElement(builder, 'eVitals.12', vital['pulse']);
                    _nemsisElement(
                      builder,
                      'eVitals.14',
                      vital['respirations'],
                    );
                    _nemsisElement(builder, 'eVitals.16', vital['o2Sat']);
                    _nemsisElement(
                      builder,
                      'eVitals.18',
                      vital['bloodGlucose'],
                    );
                    _nemsisElement(
                      builder,
                      'eVitals.19',
                      vital['gcs'] ?? gcs['total'],
                    );
                  },
                );
              }
            }

            // eExam: GCS values captured by the GUI.
            builder.element(
              'eExam',
              nest: () {
                _nemsisElement(builder, 'eExam.13', gcs['eye']);
                _nemsisElement(builder, 'eExam.14', gcs['verbal']);
                _nemsisElement(builder, 'eExam.15', gcs['motor']);
                _nemsisElement(builder, 'eExam.16', gcs['total']);
              },
            );

            // eDisposition. The GUI currently captures a narrative disposition only.
            builder.element(
              'eDisposition',
              nest: () {
                _nemsisElement(
                  builder,
                  'eDisposition.12',
                  clinical['disposition'],
                );
                _nemsisElement(builder, 'eDisposition.16', null);
                _nemsisElement(builder, 'eDisposition.17', null);
              },
            );

            builder.element(
              'eNarrative',
              nest: () {
                _nemsisElement(builder, 'eNarrative.01', narrative);
              },
            );

            _nemsisComment(
              builder,
              'PVFD Flutter export. Validate with official NEMSIS 3.5.1 XSD and National/Arizona Schematron before submission.',
            );
          },
        );
      },
    );

    return builder.buildDocument().toXmlString(pretty: true, indent: '  ');
  }
}
