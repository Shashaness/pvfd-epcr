import 'dart:convert';

Map<String, dynamic> recordMap(dynamic value) =>
    value is Map<String, dynamic> ? value : <String, dynamic>{};
List<dynamic> recordList(dynamic value) => value is List ? value : [];

List<String> readPmh(Map<String, dynamic> record) {
  final clinical = recordMap(record['clinical'])['pmh'];
  final legacy = recordMap(record['incident'])['pmh'];
  final value = clinical is List && clinical.every((v) => v is String)
      ? clinical
      : legacy;
  return recordList(value).whereType<String>().toList();
}

/// Apply only fields actually edited in the UI, retaining unsupported values.
Map<String, dynamic> mergeRecord(
  Map<String, dynamic> original,
  Map<String, dynamic> baseline,
  Map<String, dynamic> current,
) {
  final result = Map<String, dynamic>.from(original)..remove('_filePath');
  for (final entry in current.entries) {
    final old = baseline[entry.key];
    if (entry.value is Map<String, dynamic> && old is Map<String, dynamic>) {
      final merged = mergeRecord(
        recordMap(original[entry.key]),
        old,
        entry.value as Map<String, dynamic>,
      );
      if (jsonEncode(old) != jsonEncode(entry.value)) {
        result[entry.key] = merged;
      }
    } else if (!baseline.containsKey(entry.key) ||
        jsonEncode(old) != jsonEncode(entry.value)) {
      result[entry.key] = entry.value;
    }
  }
  return result;
}
