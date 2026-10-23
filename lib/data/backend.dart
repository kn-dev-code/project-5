import 'package:football_core/api/betting_api.dart';
import 'package:football_core/api/http_api.dart';
import 'package:football_core/feeds/game_feed.dart';
import 'package:football_core/server/account_server.dart';
import 'package:football_core/server/betting_server.dart';
import 'package:football_core/server/server_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Address of the Football Winner server (see `server/`), set when building
/// with `--dart-define=API_URL=https://...`.
///
/// Without it the app runs the servers itself, on the device, with made-up
/// games. Tests rely on that, and it lets the app work without a server.
const apiUrl = String.fromEnvironment('API_URL');

/// Whether the app talks to the real server with live games.
bool get usesLiveServer => apiUrl.isNotEmpty;

final ApiConnection? _connection = usesLiveServer
    ? ApiConnection(Uri.parse(apiUrl))
    : null;

/// Made-up games for the on-device server when there's no [apiUrl].
final GameFeed gameFeed = FakeGameFeed();

/// Shared accounts service.
final AccountApi accounts = switch (_connection) {
  final connection? => HttpAccountApi(connection),
  null => AccountServer(storage: PrefsStorage('server_accounts')),
};

/// Shared betting service.
final BettingApi backend = switch (_connection) {
  final connection? => HttpBettingApi(connection),
  null => BettingServer(
    feed: gameFeed,
    storage: PrefsStorage('server_ledger'),
    accounts: accounts as AccountServer,
  ),
};

/// Saves an on-device server's data in shared preferences under [key].
class PrefsStorage implements ServerStorage {
  PrefsStorage(this.key);

  final String key;

  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> write(String data) async =>
      (await SharedPreferences.getInstance()).setString(key, data);
}
