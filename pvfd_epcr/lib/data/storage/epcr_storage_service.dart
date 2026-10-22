import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../core/epcr_id.dart';

class EpcrStorageService {
  EpcrStorageService({this.beforeReplace});

  /// Failure injection for tests, after the flushed temporary file is complete.
  final Future<void> Function(File temporary, File destination)? beforeReplace;
  static final Map<String, Future<void>> _queues = {};

  Future<T> _ordered<T>(String path, Future<T> Function() action) {
    final previous = _queues[path] ?? Future<void>.value();
    final result = previous.then((_) => action());
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace stack) {},
    );
    _queues[path] = tail;
    unawaited(
      tail.then((_) {
        if (identical(_queues[path], tail)) _queues.remove(path);
      }),
    );
    return result;
  }

  Future<void> save(File destination, Map<String, dynamic> record) {
    // Serialize now: mutable form state cannot change a queued snapshot.
    final content = jsonEncode(record);
    if (!(Platform.isAndroid ||
        Platform.isLinux ||
        Platform.isMacOS ||
        Platform.isIOS)) {
      throw UnsupportedError(
        'Atomic record replacement is not verified on this platform',
      );
    }
    return _ordered(destination.absolute.path, () async {
      final temporary = File(
        '${destination.path}.epcr-tmp-${newEpcrId(DateTime.now())}',
      );
      try {
        await temporary.writeAsString(content, flush: true);
        await beforeReplace?.call(temporary, destination);
        // Android/Linux rename replaces atomically on the same filesystem.
        // Never delete destination as a fallback on other filesystems.
        await temporary.rename(destination.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    });
  }

  Future<File> create(
    Directory directory,
    Map<String, dynamic> record, {
    String Function()? idFactory,
  }) async {
    for (var attempt = 0; attempt < 20; attempt++) {
      final id = idFactory?.call() ?? newEpcrId(DateTime.now());
      if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id)) {
        throw const FormatException('Invalid record identifier');
      }
      final destination = File('${directory.path}/pcr_$id.json');
      // A separate exclusive reservation avoids exposing an empty JSON record.
      final lock = File('${destination.path}.reserve');
      try {
        await lock.create(exclusive: true);
      } on FileSystemException {
        continue;
      }
      try {
        if (await destination.exists()) continue;
        await save(destination, {
          ...record,
          'epcrNumber': id,
          'appRecordId': id,
        });
        return destination;
      } finally {
        await lock.delete();
      }
    }
    throw const FileSystemException('Unable to allocate a new record');
  }

  Future<Map<String, dynamic>> read(File file) async {
    final value = jsonDecode(await file.readAsString());
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Record must be a JSON object');
    }
    return value;
  }

  /// Orphans are retained for manual recovery; never promote them automatically.
  Future<int> orphanCount(Directory directory) async {
    var count = 0;
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is File &&
          (entry.path.contains('.epcr-tmp-') ||
              entry.path.endsWith('.reserve'))) {
        count++;
      }
    }
    return count;
  }

  Future<List<Map<String, dynamic>>> list(
    Directory directory, {
    void Function()? onUnreadable,
  }) async {
    final records = <Map<String, dynamic>>[];
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is! File || !entry.path.endsWith('.json')) continue;
      try {
        records.add({...await read(entry), '_filePath': entry.path});
      } on FormatException {
        onUnreadable?.call();
      } on FileSystemException {
        onUnreadable?.call();
      }
    }
    records.sort(
      (a, b) => '${b['epcrNumber']}'.compareTo('${a['epcrNumber']}'),
    );
    return records;
  }
}
