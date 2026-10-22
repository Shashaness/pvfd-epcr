import 'package:pvfd_epcr/domain/models/epcr_record.dart';

const syntheticId = '20261022141530-SYNTHETIC';
Map<String, dynamic> syntheticJson() => {
  'appRecordId': syntheticId,
  'epcrNumber': syntheticId,
  'nemsisVersionTarget': '3.5.1',
  'incident': {
    'incidentNumber': syntheticId,
    'incidentAddress': '100 Synthetic & Test Lane',
    'responders': ['F1', 'R2'],
    'forestLand': true,
    'gpsCoordinates': '34.10, -110.90',
    'dateTimeCreated': '2026-10-22T14:15:30.000',
  },
  'patient': {
    'firstName': 'Synthetic <A>',
    'lastName': 'Test & Example',
    'age': '40',
    'gender': 'Female',
  },
  'crew': {'levelOfCare': 'EMT'},
  'contacts': {
    'emergencyContactName': 'Synthetic Contact',
    'emergencyContactNumber': '000-000-0000',
    'reportingParty': 'Synthetic Reporter',
    'reportingPartyNumber': '000-000-0001',
  },
  'formCompletion': {'completedBy': 'Synthetic Responder'},
  'clinical': {
    'chiefComplaint': 'Synthetic complaint',
    'pmh': ['Asthma', 'HTN'],
    'allergies': 'Synthetic allergy',
    'medications': 'Synthetic medication',
    'assessment': 'Synthetic assessment <stable>',
    'treatment': 'Synthetic treatment',
    'disposition': 'Synthetic disposition',
    'glasgowComaScale': {'eye': 3, 'verbal': 5, 'motor': 6, 'total': 14},
    'vitals': [
      {
        'time': '2026-10-22T14:15:30.000',
        'timeDisplay': '10/22/2026 14:15:30',
        'pulse': '80',
        'o2Sat': '98',
        'systolic': '120',
        'diastolic': '80',
        'temp': '98.6',
        'bloodGlucose': '100',
      },
    ],
  },
};
EpcrDocumentSnapshot syntheticSnapshot() => EpcrDocumentSnapshot(
  record: EpcrRecord.fromJson(syntheticJson()),
  id: syntheticId,
  dateTimeCreated: DateTime(2026, 10, 22, 14, 15, 30),
);
