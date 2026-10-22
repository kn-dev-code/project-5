/// Where a server keeps its data, as one JSON string. On a real server this
/// would be a database.
abstract class ServerStorage {
  Future<String?> read();

  Future<void> write(String data);
}

/// Keeps the data in memory only; used by tests.
class MemoryStorage implements ServerStorage {
  MemoryStorage([this.data]);

  String? data;

  @override
  Future<String?> read() async => data;

  @override
  Future<void> write(String data) async => this.data = data;
}
