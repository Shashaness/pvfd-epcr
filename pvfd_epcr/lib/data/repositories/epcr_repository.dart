import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../domain/models/epcr_record.dart';
import '../storage/epcr_storage_service.dart';

abstract class EpcrRepository {
  Future<EpcrRecord> create(EpcrRecord record, {String Function()? idFactory});
  Future<EpcrRecord> load(String path);
  Future<List<EpcrRecord>> list({void Function()? onUnreadable});
  Future<void> save(EpcrRecord record);
  Future<int> orphanCount();
}

/// Coordinates location/model conversion; the storage service owns transactions.
class LocalEpcrRepository implements EpcrRepository {
  LocalEpcrRepository({
    Future<Directory> Function()? documentsDirectory,
    EpcrStorageService? storage,
  }) : documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory,
       storage = storage ?? EpcrStorageService();
  final Future<Directory> Function() documentsDirectory;
  final EpcrStorageService storage;

  @override
  Future<EpcrRecord> create(
    EpcrRecord record, {
    String Function()? idFactory,
  }) async {
    final file = await storage.create(
      await documentsDirectory(),
      record.toJson(),
      idFactory: idFactory,
    );
    // No read-after-write race: creation returns its own committed snapshot.
    final id = file.uri.pathSegments.last
        .substring(4)
        .replaceFirst('.json', '');
    return EpcrRecord.fromJson({
      ...record.toJson(),
      'epcrNumber': id,
      'appRecordId': id,
    }, sourcePath: file.path);
  }

  @override
  Future<EpcrRecord> load(String path) async =>
      EpcrRecord.fromJson(await storage.read(File(path)), sourcePath: path);
  @override
  Future<List<EpcrRecord>> list({void Function()? onUnreadable}) async =>
      (await storage.list(
        await documentsDirectory(),
        onUnreadable: onUnreadable,
      )).map(EpcrRecord.fromJson).toList();
  @override
  Future<void> save(EpcrRecord record) {
    final path = record.sourcePath;
    if (path == null) throw StateError('Record has no bound destination');
    return storage.save(File(path), record.toJson());
  }

  @override
  Future<int> orphanCount() async =>
      storage.orphanCount(await documentsDirectory());
}
