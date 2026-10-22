import 'dart:convert';
import 'record_json.dart';

/// Lossless JSON document. Projections never normalize or mutate stored values.
/// Source location is metadata and is not serialized as a clinical field.
class EpcrRecord {
  EpcrRecord.fromJson(Map<String, dynamic> json, {String? sourcePath})
    : _json = _copy({...json}..remove('_filePath')),
      sourcePath =
          sourcePath ??
          (json['_filePath'] is String ? json['_filePath'] as String : null);

  factory EpcrRecord.decode(String text, {String? sourcePath}) {
    final value = jsonDecode(text);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Record must be a JSON object');
    }
    return EpcrRecord.fromJson(value, sourcePath: sourcePath);
  }

  final Map<String, dynamic> _json;
  final String? sourcePath;
  Map<String, dynamic> toJson() => _copy(_json);
  String encode() => jsonEncode(_json);
  String get id =>
      (_json['epcrNumber'] ?? _json['appRecordId'] ?? '').toString();
  Incident get incident => Incident(recordMap(toJson()['incident']));
  Patient get patient => Patient(recordMap(toJson()['patient']));
  Clinical get clinical =>
      Clinical(recordMap(toJson()['clinical']), readPmh(_json));

  EpcrRecord applyEdits(
    Map<String, dynamic> baseline,
    Map<String, dynamic> current, {
    required List<String> pmhOptions,
  }) {
    final merged = mergeRecord(_json, baseline, current);
    if (jsonEncode(recordMap(baseline['clinical'])['pmh']) !=
        jsonEncode(recordMap(current['clinical'])['pmh'])) {
      recordMap(merged['clinical'])['pmh'] = {
        ...recordList(
          recordMap(current['clinical'])['pmh'],
        ).whereType<String>(),
        ...readPmh(_json).where((value) => !pmhOptions.contains(value)),
        ...recordList(
          recordMap(_json['clinical'])['pmh'],
        ).whereType<String>().where((value) => !pmhOptions.contains(value)),
      }.toList();
    }
    return EpcrRecord.fromJson(merged, sourcePath: sourcePath);
  }

  static Map<String, dynamic> _copy(Map<String, dynamic> value) =>
      jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
}

/// Detached UI projections; every unrecognized field stays in EpcrRecord.
class Incident {
  Incident(this.fields);
  final Map<String, dynamic> fields;
  String get number => fields['incidentNumber']?.toString() ?? '';
  String get address => fields['incidentAddress']?.toString() ?? '';
  bool get forestLand => fields['forestLand'] == true;
  String get gpsCoordinates => fields['gpsCoordinates']?.toString() ?? '';
}

class Patient {
  Patient(this.fields);
  final Map<String, dynamic> fields;
  String get firstName => fields['firstName']?.toString() ?? '';
  String get lastName => fields['lastName']?.toString() ?? '';
  String get age => fields['age']?.toString() ?? '';
  String get gender => fields['gender']?.toString() ?? 'Unknown';
}

class Clinical {
  Clinical(this.fields, this.pmh);
  final Map<String, dynamic> fields;
  final List<String> pmh;
  String get assessment => fields['assessment']?.toString() ?? '';
  List<Map<String, dynamic>> get vitals =>
      recordList(fields['vitals']).whereType<Map<String, dynamic>>().toList();
}

/// Captures fallback metadata alongside lossless JSON for document generation.
class EpcrDocumentSnapshot {
  EpcrDocumentSnapshot({
    required this.record,
    required this.id,
    required this.dateTimeCreated,
  });
  final EpcrRecord record;
  final String id;
  final DateTime dateTimeCreated;
}
