import 'dart:io';

import 'package:football_core/server/server_storage.dart';

/// Keeps a server's data in one JSON file.
///
/// Each write goes to a temporary file that then replaces the real one, so a
/// crash mid-write never leaves half a file behind. Writes are queued, so the
/// last one made is the one that sticks, and a failed write doesn't stop later
/// ones.
// TODO: move to a database before running more than one server instance.
class FileStorage implements ServerStorage {
  FileStorage(String path) : _file = File(path);

  final File _file;
  Future<void> _lastWrite = Future.value();

  @override
  Future<String?> read() async =>
      await _file.exists() ? _file.readAsString() : null;

  @override
  Future<void> write(String data) =>
      _lastWrite = _lastWrite.catchError((Object _) {}).then((_) async {
        await _file.parent.create(recursive: true);
        final temp = File('${_file.path}.tmp');
        await temp.writeAsString(data, flush: true);
        await temp.rename(_file.path);
      });
}
