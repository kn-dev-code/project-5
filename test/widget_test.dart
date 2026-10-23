import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_core/feeds/fake_games.dart';
import 'package:football_core/feeds/game_feed.dart';
import 'package:football_core/models/bet.dart';
import 'package:football_core/models/crowd_stats.dart';
import 'package:football_core/models/game.dart';
import 'package:football_core/server/account_server.dart';
import 'package:football_core/server/betting_server.dart';
import 'package:football_core/server/payouts.dart';
import 'package:football_core/server/server_storage.dart';
import 'package:footballapp/data/app_theme.dart';
import 'package:footballapp/data/auth.dart';
import 'package:footballapp/data/backend.dart';
import 'package:footballapp/data/pick_store.dart';
import 'package:footballapp/data/sound_effects.dart';
import 'package:footballapp/main.dart';
import 'package:footballapp/screens/game_select_screen.dart';
import 'package:footballapp/screens/home_screen.dart';
import 'package:footballapp/screens/shop_screen.dart';
import 'package:footballapp/widgets/score_effects.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ScriptedFeed implements GameFeed {
  _ScriptedFeed(this._responses);

  final List<List<Game>> _responses;
  var _calls = 0;

  @override
  Future<List<Game>> fetchGames() async =>
      _responses[min(_calls++, _responses.length - 1)];

  @override
  Future<List<Game>> fetchGamesById(Iterable<String> ids) async => const [];
}

const _username = 'tester';
const _password = 'password1';

/// Opens the app and logs in through the login screen with the shared
/// accounts server, creating the account first if an earlier test hasn't.
/// Tests that bet on the shared server's games log in as their own [username]
/// so their bets don't clash.
Future<void> _openAppAndLogIn(
  WidgetTester tester, {
  String username = _username,
}) async {
  try {
    await accounts.createAccount(username, _password);
  } on AuthException {
    // An earlier test already created it.
  }
  await tester.pumpWidget(const FootballWinnerApp());
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextField, 'Username'), username);
  await tester.enterText(find.widgetWithText(TextField, 'Password'), _password);
  await tester.tap(find.widgetWithText(FilledButton, 'Log In'));
  await tester.pumpAndSettle();
}

/// The first game in the shared feed that still takes bets. There's always
/// one, since upcoming games take bets and kick off every few minutes.
Future<Game> _bettableGame() async =>
    (await gameFeed.fetchGames()).firstWhere((g) => g.isBettingOpen);

/// A game still taking bets whose away team is below .500. Even kickoff slots
/// always have one, and there are always two upcoming slots in a row.
Future<Game> _underdogAwayGame() async =>
    (await gameFeed.fetchGames()).firstWhere(
      (game) => game.isBettingOpen && underdogMultiplier(game.awayRecord) > 1,
    );

/// The card for [game] in the game list; the end time is unique to each game.
Finder _cardFor(WidgetTester tester, Game game) {
  final ends = MaterialLocalizations.of(tester.element(find.text('Live Now')))
      .formatTimeOfDay(TimeOfDay.fromDateTime(game.endsAt!));
  return find.textContaining('· ends $ends');
}

/// A betting server that only knows the games in [feed], and a player who is
/// logged in to it.
Future<(BettingServer, Session)> _testServer(GameFeed feed) async {
  final accounts = AccountServer(storage: MemoryStorage(), hashIterations: 1);
  final token = await accounts.createAccount(_username, _password);
  final session = Session(
    token: token,
    account: await accounts.accountFor(token),
  );
  final server = BettingServer(
    feed: feed,
    storage: MemoryStorage(),
    accounts: accounts,
  );
  return (server, session);
}

/// Records sounds instead of playing them; tests have no audio.
class _RecordingSoundPlayer implements SoundPlayer {
  final played = <Sound>[];

  @override
  Future<void> play(Sound sound) async => played.add(sound);
}

final _sounds = _RecordingSoundPlayer();

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sfx.player = _sounds;
    sfx.muted.value = false;
    _sounds.played.clear();
  });
  tearDown(() => appBackground.value = null);

  testWidgets('Login screen rejects missing or wrong details', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const FootballWinnerApp());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Log In'));
    await tester.pump();
    expect(find.text('Enter your username and password.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Username'), 'nope');
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'wrong-password',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Log In'));
    await tester.pumpAndSettle();
    expect(find.text('Wrong username or password.'), findsOneWidget);
    expect(find.text('Select Game'), findsNothing);
  });

  testWidgets('Login screen leads to homepage with Select Game and Shop', (
    WidgetTester tester,
  ) async {
    await _openAppAndLogIn(tester);

    // The app opens with its jingle, then the login button taps and the
    // first-login reward pays out.
    expect(_sounds.played.first, Sound.startup);
    expect(_sounds.played, containsAllInOrder([Sound.tap, Sound.coins]));

    expect(find.text('Logged in as $_username'), findsOneWidget);
    expect(find.text('Select Game'), findsOneWidget);
    expect(find.text('Shop'), findsOneWidget);
  });

  testWidgets('Home screen grants the daily login reward only once', (
    WidgetTester tester,
  ) async {
    final (server, session) = await _testServer(_ScriptedFeed([const []]));
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(session: session, server: server),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Daily login reward: +${BettingServer.dailyRewardAmount} coins!',
      ),
      findsOneWidget,
    );
    final rewardedBalance =
        BettingServer.startingBalance + BettingServer.dailyRewardAmount;
    expect(await server.balance(session.token), rewardedBalance);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(session: session, server: server),
      ),
    );
    await tester.pumpAndSettle();

    expect(await server.balance(session.token), rewardedBalance);
    expect(
      find.text(
        'Daily login reward: +${BettingServer.dailyRewardAmount} coins!',
      ),
      findsNothing,
    );
  });

  testWidgets('The app stays logged in until the player logs out', (
    WidgetTester tester,
  ) async {
    await _openAppAndLogIn(tester);

    // Relaunching skips the login screen.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const FootballWinnerApp());
    await tester.pumpAndSettle();
    expect(find.text('Logged in as $_username'), findsOneWidget);

    await tester.tap(find.byTooltip('Log Out'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Log In'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const FootballWinnerApp());
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Log In'), findsOneWidget);
  });

  testWidgets('Select Game lists games and lets the user bet on a winner', (
    WidgetTester tester,
  ) async {
    final game = await _bettableGame();
    await _openAppAndLogIn(tester, username: 'picker');
    // Let the first-login reward message go so later ones can show.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select Game'));
    await tester.pumpAndSettle();

    expect(find.text('Live Now'), findsOneWidget);
    expect(find.text(game.homeTeam), findsWidgets);
    expect(find.textContaining('bettor'), findsWidgets);

    final card = _cardFor(tester, game);
    await tester.scrollUntilVisible(card, 300);
    await tester.tap(card);
    await tester.pumpAndSettle();

    expect(find.text('Who will win?'), findsOneWidget);
    final confirm = find.widgetWithText(FilledButton, 'Confirm Pick');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await tester.tap(find.widgetWithText(ListTile, game.awayTeam));
    await tester.pump();
    // Picking a team isn't enough; every pick needs a bet.
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    final betField = find.byType(TextField);
    await tester.scrollUntilVisible(
      betField,
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.enterText(betField, '10');
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(
      find.text('You picked ${game.awayTeam} to win and bet 10 coins!'),
      findsOneWidget,
    );
    expect(_sounds.played, containsAllInOrder([Sound.select, Sound.bet]));
    // Back on the game list, with the pick on the game's card.
    expect(find.text('Select Game'), findsOneWidget);
    expect(find.text('Your pick: ${game.awayTeam}'), findsOneWidget);
    expect(await PickStore().loadPicks(), {game.id: TeamSide.away});
  });

  testWidgets('Game list refreshes periodically and shows who won', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({'winner_picks': '{"x1":"home"}'});
    const live = Game(
      id: 'x1',
      league: 'Pro Football',
      homeTeam: 'Alpha Aces',
      awayTeam: 'Beta Bulls',
      status: GameStatus.live,
      homeScore: 10,
      awayScore: 3,
      quarter: 4,
      clock: '1:00',
    );
    const finished = Game(
      id: 'x1',
      league: 'Pro Football',
      homeTeam: 'Alpha Aces',
      awayTeam: 'Beta Bulls',
      status: GameStatus.finished,
      homeScore: 17,
      awayScore: 3,
    );
    final (server, session) = await _testServer(
      _ScriptedFeed([
        [live],
        [finished],
      ]),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: GameSelectScreen(session: session, server: server),
      ),
    );
    await tester.pumpAndSettle();

    // Fourth quarter: betting is closed, so the pick can't be changed.
    expect(find.text('Your pick: Alpha Aces'), findsOneWidget);
    expect(find.textContaining('Winner:'), findsNothing);

    await tester.pump(const Duration(seconds: 30));
    await tester.pump();

    expect(find.text('Winner: Alpha Aces'), findsOneWidget);
    expect(find.text('Your pick: Alpha Aces - correct!'), findsOneWidget);
    expect(find.text('Alpha Aces won! Your pick was right!'), findsOneWidget);
  });

  testWidgets('Pick screen shows vote percentages and places a bet', (
    WidgetTester tester,
  ) async {
    final game = await _underdogAwayGame();
    final record = game.awayRecord!;
    final bonus = underdogMultiplier(record);
    await _openAppAndLogIn(tester);
    await tester.tap(find.text('Select Game'));
    await tester.pumpAndSettle();

    final loginBalance =
        BettingServer.startingBalance + BettingServer.dailyRewardAmount;
    expect(find.text('$loginBalance coins'), findsOneWidget);

    final card = _cardFor(tester, game);
    await tester.scrollUntilVisible(card, 300);
    await tester.tap(card);
    await tester.pumpAndSettle();

    expect(find.textContaining('% of votes'), findsNWidgets(2));
    expect(find.textContaining('Away · $record · '), findsOneWidget);
    expect(find.text('${bonus}x underdog bonus if they win'), findsOneWidget);

    await tester.tap(find.widgetWithText(ListTile, game.awayTeam));
    final betField = find.byType(TextField);
    await tester.scrollUntilVisible(
      betField,
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.enterText(betField, '5000');
    await tester.pump();

    expect(find.text('You only have $loginBalance coins'), findsOneWidget);
    final confirm = find.widgetWithText(FilledButton, 'Confirm Pick');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await tester.enterText(betField, '100');
    await tester.pump();
    await tester.drag(find.byType(ListView).last, const Offset(0, -240));
    await tester.pump();
    expect(
      find.textContaining('If ${game.awayTeam} wins you get'),
      findsOneWidget,
    );
    expect(
      find.textContaining('with a ${bonus}x underdog bonus'),
      findsOneWidget,
    );
    expect(find.textContaining('Your odds: '), findsOneWidget);
    expect(find.textContaining('if you bet 100 coins'), findsOneWidget);
    expect(find.textContaining('players have bet'), findsOneWidget);
    expect(find.textContaining('Odds '), findsWidgets);

    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(
      find.text('You picked ${game.awayTeam} to win and bet 100 coins!'),
      findsOneWidget,
    );
    expect(find.text('${loginBalance - 100} coins'), findsOneWidget);
    expect(
      find.textContaining('Bet: 100 coins on ${game.awayTeam}'),
      findsOneWidget,
    );
    final session = await Auth().restore();
    expect(await backend.balance(session!.token), loginBalance - 100);
  });

  testWidgets('Winning bets are paid out when the game ends', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({'winner_picks': '{"x1":"home"}'});
    const live = Game(
      id: 'x1',
      league: 'Pro Football',
      homeTeam: 'Alpha Aces',
      awayTeam: 'Beta Bulls',
      status: GameStatus.live,
      quarter: 1,
      clock: '1:00',
    );
    const finished = Game(
      id: 'x1',
      league: 'Pro Football',
      homeTeam: 'Alpha Aces',
      awayTeam: 'Beta Bulls',
      status: GameStatus.finished,
      homeScore: 7,
    );
    final (server, session) = await _testServer(
      _ScriptedFeed([
        [live],
        [live],
        [finished],
      ]),
    );
    await server.fetchGames();
    await server.placeBet(session.token, 'x1', TeamSide.home, 100);

    await tester.pumpWidget(
      MaterialApp(
        home: GameSelectScreen(session: session, server: server),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('900 coins'), findsOneWidget);

    await tester.pump(const Duration(seconds: 30));
    await tester.pump();

    final payout = (await server.bets(session.token))['x1']!.payout!;
    expect(payout, greaterThan(100));
    expect(find.text('${900 + payout} coins'), findsOneWidget);
    expect(
      find.text('Alpha Aces won! Your pick was right! You won $payout coins.'),
      findsOneWidget,
    );
    expect(await server.balance(session.token), 900 + payout);
  });

  testWidgets('Halftime scores pop up and collect under the bell', (
    WidgetTester tester,
  ) async {
    Game live(int quarter, {int home = 0}) => Game(
      id: 'x1',
      league: 'Pro Football',
      homeTeam: 'Alpha Aces',
      awayTeam: 'Beta Bulls',
      status: GameStatus.live,
      homeScore: home,
      quarter: quarter,
      clock: '10:00',
    );
    final (server, session) = await _testServer(
      _ScriptedFeed([
        [live(1)],
        [live(1)],
        [live(3, home: 7)],
      ]),
    );
    await server.fetchGames();
    await server.placeBet(session.token, 'x1', TeamSide.home, 100);

    await tester.pumpWidget(
      MaterialApp(
        home: GameSelectScreen(session: session, server: server),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Badge), findsOneWidget);
    expect(find.text('1'), findsNothing);

    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    expect(
      find.text(
        'Halftime: Alpha Aces 7 - 0 Beta Bulls. '
        'Your 100-coin bet on Alpha Aces: Alpha Aces leads by 7.',
      ),
      findsOneWidget,
    );
    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();
    expect(find.text('Halftime: Alpha Aces 7 - 0 Beta Bulls'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('1'), findsNothing);
    expect((await server.notifications(session.token)).single.read, isTrue);
  });

  testWidgets('Owned backgrounds can be used and removed from the inventory', (
    WidgetTester tester,
  ) async {
    final (server, session) = await _testServer(_ScriptedFeed([const []]));
    await server.purchaseShopItem(session.token, 'stadium_lights');

    await tester.pumpWidget(
      MaterialApp(
        home: ShopScreen(session: session, server: server),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inventory'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Use background'));
    await tester.pumpAndSettle();
    expect(appBackground.value?.id, 'stadium_lights');
    expect(await server.activeShopBackground(session.token), 'stadium_lights');
    expect(find.text('Stadium Lights is now your background.'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(appBackground.value, isNull);
    expect(await server.activeShopBackground(session.token), isNull);
  });

  testWidgets(
    'Scores play fanfare for the backed team and coins for the other',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({'winner_picks': '{"x1":"home"}'});
      Game live(int home, int away) => Game(
        id: 'x1',
        league: 'Pro Football',
        homeTeam: 'Alpha Aces',
        awayTeam: 'Beta Bulls',
        status: GameStatus.live,
        homeScore: home,
        awayScore: away,
        quarter: 3,
        clock: '9:00',
      );
      final (server, session) = await _testServer(
        _ScriptedFeed([
          [live(0, 0)],
          [live(7, 3)],
        ]),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: GameSelectScreen(session: session, server: server),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ScoreEffect), findsNothing);

      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      expect(find.text('TOUCHDOWN! Alpha Aces +7'), findsOneWidget);
      expect(
        find.text('Beta Bulls scored 3. Your coins are slipping away...'),
        findsOneWidget,
      );

      await tester.pump(ScoreEffect.duration + const Duration(milliseconds: 50));
      await tester.pump();
      expect(find.byType(ScoreEffect), findsNothing);
    },
  );

  test('Score events only fire for games the user backed', () {
    Game game(String id, int home, int away) => Game(
      id: id,
      league: 'Pro Football',
      homeTeam: 'Alpha Aces',
      awayTeam: 'Beta Bulls',
      status: GameStatus.live,
      homeScore: home,
      awayScore: away,
    );
    final events = scoreEvents(
      [game('a', 0, 0), game('b', 0, 0)],
      [game('a', 3, 0), game('b', 7, 7)],
      {'a': TeamSide.away},
    );
    expect(events, hasLength(1));
    expect(events.single.kind, ScoreEffectKind.moneyAway);
    expect(events.single.team, 'Alpha Aces');
    expect(events.single.points, 3);
  });

  test('Odds come from the pools and bettor counts include the user', () {
    const crowd = CrowdStats(
      homeVotes: 2,
      awayVotes: 1,
      homePool: 300,
      awayPool: 100,
      homeBettors: 4,
      awayBettors: 1,
    );
    expect(crowd.odds(TeamSide.home), closeTo(1.333, 0.001));
    expect(crowd.odds(TeamSide.away), 4.0);
    expect(formatOdds(4), '4.00x');
    final mine = crowd.withUser(
      pick: TeamSide.away,
      bet: const Bet(side: TeamSide.away, amount: 100),
    );
    expect(mine.awayBettors, 2);
    expect(mine.totalBettors, 6);
    expect(mine.odds(TeamSide.away), 2.5);
    expect(
      const CrowdStats(
        homeVotes: 0,
        awayVotes: 0,
        homePool: 0,
        awayPool: 0,
      ).odds(TeamSide.home),
      isNull,
    );
  });

  test('Vote percentages add up to 100 and winners split the pool', () {
    const crowd = CrowdStats(
      homeVotes: 2,
      awayVotes: 1,
      homePool: 300,
      awayPool: 100,
    );
    expect(crowd.votePercent(TeamSide.home), 67);
    expect(crowd.votePercent(TeamSide.away), 33);
    expect(crowd.winningPayout(TeamSide.home, 100), 133);
    expect(crowd.winningPayout(TeamSide.away, 100), 400);
  });

  test('Fake games expire at their end time with a winner', () async {
    var now = DateTime(2026, 10, 22, 12, 1);
    final feed = FakeGameFeed(clock: () => now);
    final games = await feed.fetchGames();
    expect(games.where((g) => g.isLive), isNotEmpty);
    expect(games.where((g) => g.status == GameStatus.upcoming), isNotEmpty);
    expect(games.where((g) => g.isFinished), isNotEmpty);

    final live = games.firstWhere((g) => g.isLive);
    expect(live.endsAt, live.kickoff!.add(fakeGameLength));

    now = live.endsAt!.subtract(const Duration(seconds: 1));
    final [stillLive] = await feed.fetchGamesById([live.id]);
    expect(stillLive.isLive, isTrue);
    expect(stillLive.quarter, 4);

    now = live.endsAt!;
    final [ended] = await feed.fetchGamesById([live.id]);
    expect(ended.isFinished, isTrue);
    expect(ended.winner, isNotNull);
    expect(ended.homeTeam, live.homeTeam);
    expect(ended.homeScore, greaterThanOrEqualTo(live.homeScore));
  });

  test('Fake games look the same after the app restarts', () async {
    final now = DateTime(2026, 10, 22, 12, 7);
    List<(String, String, int, int, String, String)> snapshot(
      List<Game> games,
    ) => [
      for (final g in games)
        (
          g.id,
          g.homeTeam,
          g.homeScore,
          g.awayScore,
          '${g.homeRecord}',
          '${g.awayRecord}',
        ),
    ];
    final before = await FakeGameFeed(clock: () => now).fetchGames();
    final after = await FakeGameFeed(clock: () => now).fetchGames();
    expect(snapshot(after), snapshot(before));
  });

  test('Every fake game ends with a winner, never a tie', () async {
    final feed = FakeGameFeed(clock: () => DateTime(2030));
    final games = await feed.fetchGamesById([
      for (var slot = 0; slot < 500; slot++) 'fake-$slot',
    ]);
    expect(games, hasLength(500));
    expect(games.where((g) => g.winner == null), isEmpty);
    expect(await feed.fetchGamesById(['g1', 'fake-x']), isEmpty);
  });

  testWidgets('Create account screen checks the form and logs in', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const FootballWinnerApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text("Don't have an account? Create one"));
    await tester.pumpAndSettle();

    final username = find.widgetWithText(TextField, 'Username');
    final password = find.widgetWithText(TextField, 'Password');
    final confirm = find.widgetWithText(TextField, 'Confirm Password');
    final create = find.widgetWithText(FilledButton, 'Create Account');

    await tester.enterText(username, 'new_player');
    await tester.enterText(password, 'password1');
    await tester.enterText(confirm, 'password2');
    await tester.tap(create);
    await tester.pump();
    expect(find.text("Passwords don't match."), findsOneWidget);

    await tester.enterText(password, 'short');
    await tester.enterText(confirm, 'short');
    await tester.tap(create);
    await tester.pumpAndSettle();
    expect(
      find.text('Passwords must be at least 8 characters.'),
      findsOneWidget,
    );

    await tester.enterText(password, 'password1');
    await tester.enterText(confirm, 'password1');
    await tester.tap(create);
    await tester.pumpAndSettle();
    expect(find.text('Logged in as new_player'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
  });

  testWidgets('Muting sounds silences them and is remembered', (
    WidgetTester tester,
  ) async {
    final (server, session) = await _testServer(_ScriptedFeed([const []]));
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(session: session, server: server),
      ),
    );
    await tester.pumpAndSettle();
    _sounds.played.clear();

    await tester.tap(find.byTooltip('Turn sounds off'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Turn sounds on'), findsOneWidget);
    expect(_sounds.played, isEmpty);
    expect(
      (await SharedPreferences.getInstance()).getBool('sounds_muted'),
      isTrue,
    );

    await tester.tap(find.byTooltip('Refresh balance and reward'));
    await tester.pumpAndSettle();
    expect(_sounds.played, isEmpty);

    // A fresh start reads the saved setting.
    sfx.muted.value = false;
    await sfx.loadSettings();
    expect(sfx.muted.value, isTrue);

    await tester.tap(find.byTooltip('Turn sounds on'));
    await tester.pumpAndSettle();
    expect(_sounds.played, [Sound.select]);
  });

  testWidgets('A bet refused by the server plays the error sound', (
    WidgetTester tester,
  ) async {
    Game live(int quarter) => Game(
      id: 'x1',
      league: 'Pro Football',
      homeTeam: 'Alpha Aces',
      awayTeam: 'Beta Bulls',
      status: GameStatus.live,
      quarter: quarter,
      clock: '5:00',
    );
    final (server, session) = await _testServer(
      _ScriptedFeed([
        [live(1)],
        [live(2)],
      ]),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: GameSelectScreen(session: session, server: server),
      ),
    );
    await tester.pumpAndSettle();
    _sounds.played.clear();

    await tester.tap(find.text('Alpha Aces').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Alpha Aces'));
    await tester.pump();
    final betField = find.byType(TextField);
    await tester.scrollUntilVisible(
      betField,
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.enterText(betField, '10');
    await tester.pump();

    // The first quarter ends while the player is still choosing.
    await server.fetchGames();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm Pick'));
    await tester.pumpAndSettle();

    expect(_sounds.played, [Sound.tap, Sound.select, Sound.error]);
    expect(find.textContaining('Betting is closed'), findsOneWidget);
    expect(await server.bets(session.token), isEmpty);
  });
}
