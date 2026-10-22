import 'dart:io';
import 'package:share_plus/share_plus.dart';

typedef ShareDocument =
    Future<void> Function(File file, String subject, String text);

class SharingService {
  SharingService({ShareDocument? share}) : _share = share ?? _nativeShare;
  final ShareDocument _share;
  Future<void> sharePdf(File file, String id) =>
      _share(file, 'PVFD ePCR $id', 'Attached is the PDF for PVFD ePCR $id.');
  Future<void> shareXml(File file, String id) =>
      _share(file, 'PVFD ePCR $id', 'Attached NEMSIS XML for PVFD ePCR $id.');
  static Future<void> _nativeShare(
    File file,
    String subject,
    String text,
  ) async {
    await Share.shareXFiles([XFile(file.path)], subject: subject, text: text);
  }
}
