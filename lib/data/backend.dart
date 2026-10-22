import 'package:shared_preferences/shared_preferences.dart';

import '../server/account_server.dart';
import '../server/betting_server.dart';
import '../server/server_storage.dart';
import 'game_feed.dart';

// TODO: replace these with clients for the real servers. The app only talks
// to them through their public methods, sending the session token, so the
// clients can keep the same methods.

/// Shared accounts server. For now it runs inside the app and keeps its data
/// on the device.
final AccountServer accounts = AccountServer(
  storage: PrefsStorage('server_accounts'),
);

/// Shared betting server. For now it runs inside the app and keeps its data on
/// the device.
final BettingServer backend = BettingServer(
  feed: gameFeed,
  storage: PrefsStorage('server_ledger'),
  accounts: accounts,
);

/// Saves a server's data in shared preferences under [key].
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
