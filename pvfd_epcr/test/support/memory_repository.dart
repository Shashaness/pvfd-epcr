import 'package:pvfd_epcr/data/repositories/epcr_repository.dart';
import 'package:pvfd_epcr/domain/models/epcr_record.dart';

class MemoryRepository implements EpcrRepository {
  final records = <String, EpcrRecord>{};
  int writes = 0;
  bool fail = false;
  Future<void>? gate;
  EpcrRecord? requested;
  @override
  Future<EpcrRecord> create(
    EpcrRecord record, {
    String Function()? idFactory,
  }) async {
    writes++;
    requested = record;
    await gate;
    if (fail) throw StateError('Synthetic storage failure');
    final id = idFactory?.call() ?? 'synthetic-id';
    final saved = EpcrRecord.fromJson({
      ...record.toJson(),
      'epcrNumber': id,
      'appRecordId': id,
    }, sourcePath: '/synthetic/pcr_$id.json');
    records[saved.sourcePath!] = saved;
    return saved;
  }

  @override
  Future<void> save(EpcrRecord record) async {
    writes++;
    requested = record;
    await gate;
    if (fail) throw StateError('Synthetic storage failure');
    records[record.sourcePath!] = record;
  }

  @override
  Future<EpcrRecord> load(String path) async => records[path]!;
  @override
  Future<List<EpcrRecord>> list({void Function()? onUnreadable}) async =>
      records.values.toList();
  @override
  Future<void> delete(EpcrRecord record) async {
    records.remove(record.sourcePath);
  }

  @override
  Future<int> orphanCount() async => 0;
}
