import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../domain/models/epcr_record.dart';
import 'pdf_service.dart';
import 'nemsis_service.dart';

/// File exports only; record transactions remain in the repository/storage layer.
class DocumentExportService {
  DocumentExportService({
    Future<Directory> Function()? documentsDirectory,
    Future<Directory> Function()? temporaryDirectory,
    PdfService? pdf,
    NemsisService? nemsis,
  }) : documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory,
       temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
       pdf = pdf ?? PdfService(),
       nemsis = nemsis ?? NemsisService();
  final Future<Directory> Function() documentsDirectory;
  final Future<Directory> Function() temporaryDirectory;
  final PdfService pdf;
  final NemsisService nemsis;

  Future<File> _destination(String id, String extension, bool temporary) async {
    final base = await (temporary
        ? temporaryDirectory()
        : documentsDirectory());
    final exports = Directory('${base.path}/Exports');
    if (!await exports.exists()) await exports.create(recursive: true);
    return File(
      '${exports.path}/PVFD_ePCR_${Uri.encodeComponent(id)}.$extension',
    );
  }

  Future<File> writePdf(
    EpcrDocumentSnapshot snapshot, {
    bool temporary = false,
  }) async {
    final bytes = await pdf.generate(snapshot.record.toJson());
    final file = await _destination(snapshot.id, 'pdf', temporary);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<File> writeXml(
    EpcrDocumentSnapshot snapshot, {
    bool temporary = false,
  }) async {
    final file = await _destination(snapshot.id, 'xml', temporary);
    await file.writeAsString(
      nemsis.generate(
        snapshot.record.toJson(),
        epcrNumber: snapshot.id,
        dateTimeCreated: snapshot.dateTimeCreated,
      ),
    );
    return file;
  }
}
