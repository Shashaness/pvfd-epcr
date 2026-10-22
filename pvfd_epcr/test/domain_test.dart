import 'package:flutter_test/flutter_test.dart';
import 'package:pvfd_epcr/domain/models/epcr_record.dart';
import 'package:pvfd_epcr/domain/validation/epcr_validator.dart';

void main() {
  test('lossless decode encode retains legacy malformed and future values', () {
    final raw = <String, dynamic>{
      'epcrNumber': 'legacy',
      'incident': {
        'pmh': ['Asthma', 'Future'],
      },
      'patient': {'age': null, 'gender': 'Future'},
      'clinical': {
        'vitals': 42,
        'glasgowComaScale': 'unsupported',
        'future': [1, null],
      },
      'future': {'nested': true},
      'crew': false,
    };
    final record = EpcrRecord.fromJson(
      raw,
      sourcePath: '/synthetic/original.json',
    );
    expect(EpcrRecord.decode(record.encode()).toJson(), raw);
    expect(record.clinical.pmh, ['Asthma', 'Future']);
    expect(record.clinical.vitals, isEmpty);
    expect(record.patient.gender, 'Future');
    expect(record.sourcePath, '/synthetic/original.json');
    expect(record.toJson().containsKey('_filePath'), false);
  });
  test('snapshots and projections cannot mutate the original', () {
    final raw = <String, dynamic>{
      'patient': {'firstName': 'Synthetic'},
      'clinical': {
        'pmh': ['Asthma'],
      },
    };
    final record = EpcrRecord.fromJson(raw);
    (raw['patient'] as Map)['firstName'] = 'Changed';
    record.patient.fields['firstName'] = 'Changed again';
    record.clinical.pmh.clear();
    expect(record.patient.firstName, 'Synthetic');
    expect(record.clinical.pmh, ['Asthma']);
  });
  test('differential model edits retain unsupported data and unknown PMH', () {
    final record = EpcrRecord.fromJson({
      'clinical': {
        'pmh': ['Future', 'HTN'],
        'vitals': 42,
        'assessment': 'Before',
        'future': true,
      },
    });
    final baseline = <String, dynamic>{
      'clinical': {
        'pmh': ['Future', 'HTN'],
        'vitals': [],
        'assessment': 'Before',
      },
    };
    final current = <String, dynamic>{
      'clinical': {
        'pmh': ['None'],
        'vitals': [],
        'assessment': 'Synthetic edit',
      },
    };
    final edited = record.applyEdits(
      baseline,
      current,
      pmhOptions: ['None', 'HTN'],
    );
    expect(edited.clinical.pmh, ['None', 'Future']);
    expect(edited.clinical.fields['vitals'], 42);
    expect(edited.clinical.fields['future'], true);
    expect(record.clinical.assessment, 'Before');
  });
  test('domain rejects nonobject JSON and malformed JSON', () {
    for (final text in ['[]', 'null', '{broken']) {
      expect(() => EpcrRecord.decode(text), throwsFormatException);
    }
    expect(EpcrRecord.fromJson({'_filePath': 42}).sourcePath, isNull);
  });
  test('forest GPS validation retains existing conditional requirement', () {
    const validator = EpcrValidator();
    expect(validator.forestGps(forestLand: false, gpsCoordinates: ''), isNull);
    expect(
      validator.forestGps(forestLand: true, gpsCoordinates: '   '),
      isNotNull,
    );
    expect(
      validator.forestGps(forestLand: true, gpsCoordinates: '34, -110'),
      isNull,
    );
  });
}
