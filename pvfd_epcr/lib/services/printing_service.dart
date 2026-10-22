import 'dart:typed_data';
import 'package:printing/printing.dart';

typedef PrintDocument = Future<void> Function(Uint8List bytes, String name);

class PrintingService {
  PrintingService({PrintDocument? print}) : _print = print ?? _nativePrint;
  final PrintDocument _print;
  Future<void> printPdf(Uint8List bytes, String id) =>
      _print(bytes, 'PVFD_ePCR_${Uri.encodeComponent(id)}.pdf');
  static Future<void> _nativePrint(Uint8List bytes, String name) async {
    await Printing.layoutPdf(name: name, onLayout: (_) async => bytes);
  }
}
