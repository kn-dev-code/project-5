import 'dart:io';

import 'package:football_core/api/betting_api.dart';
import 'package:football_core/api/http_api.dart';
import 'package:football_core/feeds/game_feed.dart';
import 'package:football_core/models/bet.dart';
import 'package:football_core/models/game.dart';
import 'package:football_core/models/game_notification.dart';
import 'package:football_core/server/account_server.dart';
import 'package:football_core/server/betting_server.dart';
import 'package:football_core/server/server_storage.dart';
import 'package:football_server/file_storage.dart';
import 'package:football_server/football_api.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

/// Serves whatever [games] is set to.
class _SettableFeed implements GameFeed {
  List<Game> games = const [];

  @override
  Future<List<Game>> fetchGames() async => games;

  @override
  Future<List<Game>> fetchGamesById(Iterable<String> ids) async => const [];
}

Game _game(
  GameStatus status, {
  int home = 0,
  int away = 0,
  int? quarter,
  String? clock,
}) => Game(
  id: 'nfl-1',
  league: 'NFL',
  homeTeam: 'Chicago Bears',
  awayTeam: 'New England Patriots',
  status: status,
  homeScore: home,
  awayScore: away,
  quarter: quarter,
  clock: clock,
);

void main() {
  late HttpServer server;
  late _SettableFeed feed;
  late FootballApi api;
  late HttpAccountApi accounts;
  late HttpBettingApi betting;
  late ApiConnection connection;

  setUp(() async {
    feed = _SettableFeed();
    final accountServer = AccountServer(
      storage: MemoryStorage(),
      hashIterations: 1,
    );
    api = FootballApi(
      accounts: accountServer,
      betting: BettingServer(
        feed: feed,
        storage: MemoryStorage(),
        accounts: accountServer,
        botCount: 0,
      ),
      // Always fetch, so tests see feed changes straight away.
      gamesMaxAge: Duration.zero,
      log: (_) {},
    );
    server = await shelf_io.serve(api.handler, 'localhost', 0);
    connection = ApiConnection(Uri.parse('http://localhost:${server.port}'));
    accounts = HttpAccountApi(connection);
    betting = HttpBettingApi(connection);
  });

  tearDown(() async {
    connection.close();
    await server.close(force: true);
  });

  test('plays a whole game over HTTP', () async {
    feed.games = [_game(GameStatus.live, quarter: 1, clock: '10:00')];
    final me = await accounts.createAccount('alice', 'password1');
    final you = await accounts.createAccount('bob', 'password1');
    expect((await accounts.accountFor(me)).username, 'alice');

    final games = await betting.fetchGames();
    expect(games.single.homeTeam, 'Chicago Bears');
    expect(games.single.gameClock, 'Q1 10:00');

    expect(await betting.claimDailyReward(me), 1250);
    await betting.placeBet(
      me,
      'nfl-1',
      TeamSide.home,
      200,
      scoreRange: const ScoreRange(17, 24),
    );
    await betting.placeBet(you, 'nfl-1', TeamSide.away, 100);
    expect(await betting.balance(me), 1050);
    final myBet = (await betting.bets(me))['nfl-1']!;
    expect(myBet.amount, 200);
    expect(myBet.scoreRange.toString(), '17-24');
    final crowd = await betting.crowd(games.single, token: me);
    expect((crowd.homePool, crowd.awayPool), (0, 100));

    expect(await betting.cashOutHalf(you, 'nfl-1'), 50);

    feed.games = [
      _game(GameStatus.live, home: 10, away: 7, quarter: 3, clock: '15:00'),
    ];
    await betting.fetchGames();
    final halftime = await betting.notifications(me);
    expect(halftime.single.kind, GameNotificationKind.halftime);

    feed.games = [_game(GameStatus.finished, home: 21, away: 14)];
    await betting.fetchGames();
    expect(await betting.takeResults(me), ['nfl-1']);
    final settled = (await betting.bets(me))['nfl-1']!;
    // 250 in the pool, times 1 + (8 - 7) * 0.5 for the 7-point range.
    expect(settled.payout, 375);
    expect(await betting.balance(me), 1050 + 375);

    await betting.markNotificationsRead(me);
    final notifications = await betting.notifications(me);
    expect(notifications.first.kind, GameNotificationKind.result);
    expect(notifications.every((n) => n.read), isTrue);

    await accounts.logOut(me);
    await expectLater(betting.balance(me), throwsA(isA<AuthException>()));
  });

  test('sends refusals back as the same exceptions', () async {
    feed.games = [_game(GameStatus.upcoming)];
    final me = await accounts.createAccount('carol', 'password1');

    await expectLater(
      accounts.createAccount('carol', 'password1'),
      throwsA(isA<AuthException>()),
    );
    await expectLater(
      accounts.logIn('carol', 'wrong-password'),
      throwsA(isA<AuthException>()),
    );
    await expectLater(
      betting.placeBet(me, 'nfl-1', TeamSide.home, 10),
      throwsA(
        isA<BetRejected>().having(
          (e) => e.message,
          'message',
          'Betting is closed for this game.',
        ),
      ),
    );
    await expectLater(
      betting.purchaseShopItem(me, 'no-such-item'),
      throwsA(isA<ShopRejected>()),
    );
    await expectLater(
      betting.balance('not-a-token'),
      throwsA(isA<AuthException>()),
    );

    // The shop round-trips too.
    expect(await betting.purchaseShopItem(me, 'stadium_lights'), 750);
    await betting.setActiveShopBackground(me, 'stadium_lights');
    expect(await betting.activeShopBackground(me), 'stadium_lights');
    expect(await betting.ownedShopItems(me), contains('stadium_lights'));
  });

  test('answers bad requests and browsers sensibly', () async {
    final base = 'http://localhost:${server.port}';
    final badJson = await http.post(
      Uri.parse('$base/v1/sessions'),
      body: 'not json',
    );
    expect(badJson.statusCode, 400);
    expect(badJson.body, contains('"kind":"other"'));

    final missingField = await http.post(
      Uri.parse('$base/v1/sessions'),
      body: '{"username": "x"}',
    );
    expect(missingField.statusCode, 400);

    final preflight = await http.Request(
      'OPTIONS',
      Uri.parse('$base/v1/games'),
    ).send();
    expect(preflight.statusCode, 200);
    expect(preflight.headers['access-control-allow-origin'], '*');

    expect((await http.get(Uri.parse('$base/nope'))).statusCode, 404);
  });

  test('says the server is unreachable instead of crashing', () async {
    await server.close(force: true);
    await expectLater(
      betting.fetchGames(),
      throwsA(
        isA<ApiException>().having((e) => e.statusCode, 'statusCode', null),
      ),
    );
  });

  test('file storage keeps the last write', () async {
    final dir = await Directory.systemTemp.createTemp('football_server_test');
    addTearDown(() => dir.delete(recursive: true));
    final storage = FileStorage('${dir.path}/sub/ledger.json');
    expect(await storage.read(), isNull);
    await Future.wait([storage.write('one'), storage.write('two')]);
    expect(await storage.read(), 'two');
    expect(await FileStorage('${dir.path}/sub/ledger.json').read(), 'two');
  });
}
