import 'dart:async';
import 'dart:io';

import 'package:football_core/feeds/espn_game_feed.dart';
import 'package:football_core/feeds/game_feed.dart';
import 'package:football_core/server/account_server.dart';
import 'package:football_core/server/betting_server.dart';
import 'package:football_server/file_storage.dart';
import 'package:football_server/football_api.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

/// Runs the Football Winner server. Settings come from environment variables:
///
/// - `PORT`: port to listen on, default 8080.
/// - `DATA_DIR`: where accounts and the betting ledger are saved, default
///   `data`. Put it on a persistent volume in production.
/// - `GAME_FEED`: `espn` (default) for live games, or `fake` for made-up games
///   that finish every 12 minutes, for testing.
/// - `POLL_SECONDS`: how often to check scores, default 30. Halftime and
///   result notifications and payouts happen on these checks.
/// - `ALLOWED_ORIGIN`: the web app's origin for CORS, default `*`.
Future<void> main() async {
  final env = Platform.environment;
  final port = int.parse(env['PORT'] ?? '8080');
  final dataDir = env['DATA_DIR'] ?? 'data';
  final pollEvery = Duration(seconds: int.parse(env['POLL_SECONDS'] ?? '30'));
  final GameFeed feed = switch (env['GAME_FEED'] ?? 'espn') {
    'espn' => EspnGameFeed(),
    'fake' => FakeGameFeed(),
    final other => throw ArgumentError('Unknown GAME_FEED "$other"'),
  };

  final accounts = AccountServer(
    storage: FileStorage('$dataDir/accounts.json'),
  );
  final betting = BettingServer(
    feed: feed,
    storage: FileStorage('$dataDir/ledger.json'),
    accounts: accounts,
  );
  final api = FootballApi(
    accounts: accounts,
    betting: betting,
    allowedOrigin: env['ALLOWED_ORIGIN'] ?? '*',
  );

  // Checks scores even when no one has the app open, so bets are paid out
  // and notifications go out on time.
  Future<void> poll() async {
    try {
      await api.refreshGames();
    } on Object catch (e) {
      stderr.writeln('Score check failed: $e');
    }
  }

  await poll();
  final timer = Timer.periodic(pollEvery, (_) => poll());

  final server = await shelf_io.serve(
    const Pipeline().addMiddleware(logRequests()).addHandler(api.handler),
    InternetAddress.anyIPv4,
    port,
  );
  print('Football Winner server listening on port ${server.port}');

  final stopping = Completer<void>();
  for (final signal in [
    ProcessSignal.sigint,
    if (!Platform.isWindows) ProcessSignal.sigterm,
  ]) {
    signal.watch().listen((_) {
      if (!stopping.isCompleted) stopping.complete();
    });
  }
  await stopping.future;
  print('Shutting down');
  timer.cancel();
  await server.close();
  exit(0);
}
