import 'dart:convert';
import 'dart:io';

/// Decode PDF content streams; omit varying trailer IDs and document metadata.
List<String> pdfStreams(List<int> bytes) {
  final text = latin1.decode(bytes);
  final result = <String>[];
  for (final match in RegExp(
    r'<<(.*?)>>\s*stream\r?\n(.*?)\r?\nendstream',
    dotAll: true,
  ).allMatches(text)) {
    final content = latin1.encode(match.group(2)!);
    if (match.group(1)!.contains('/FlateDecode')) {
      result.add(latin1.decode(zlib.decode(content)));
    } else {
      result.add(latin1.decode(content));
    }
  }
  return result;
}

String normalizeXmlTime(String text) => text.replaceAll(
  RegExp(r'2026-10-22T14:15:30\.000[+-]\d{2}:\d{2}'),
  '__CREATED_LOCAL__',
);
