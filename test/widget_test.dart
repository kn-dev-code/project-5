import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:footballapp/data/auth.dart';
import 'package:footballapp/data/backend.dart';
import 'package:footballapp/data/game_feed.dart';
import 'package:footballapp/data/pick_store.dart';
import 'package:footballapp/main.dart';
import 'package:footballapp/models/crowd_stats.dart';
import 'package:footballapp/models/game.dart';
import 'package:footballapp/screens/game_select_screen.dart';
import 'package:footballapp/server/account_server.dart';
import 'package:footballapp/server/betting_server.dart';
import 'package:footballapp/server/server_storage.dart';

class _ScriptedFeed implements GameFeed {
  _ScriptedFeed(this._responses);

  final List<List<Game>> _responses;
  var _calls = 0;

  @override
  Future<List<Game>> fetchGames() async =>
      _responses[min(_calls++, _responses.length - 1)];
}

const _username = 'tester';
const _password = 'password1';

/// Opens the app and logs in through the login screen with the shared
/// accounts server, creating the account first if an earlier test hasn't.
Future<void> _openAppAndLogIn(WidgetTester tester) async {
  try {
    await accounts.createAccount(_username, _password);
  } on AuthException {
    // An earlier test already created it.
  }
  await tester.pumpWidget(const FootballWinnerApp());
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextField, 'Username'), _username);
  await tester.enterText(find.widgetWithText(TextField, 'Password'), _password);
  await tester.tap(find.widgetWithText(FilledButton, 'Log In'));
  await tester.pumpAndSettle();
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

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

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

    expect(find.text('Logged in as $_username'), findsOneWidget);
    expect(find.text('Select Game'), findsOneWidget);
    expect(find.text('Shop'), findsOneWidget);
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

  testWidgets('Select Game lists games and lets the user pick a live winner', (
    WidgetTester tester,
  ) async {
    await _openAppAndLogIn(tester);
    await tester.tap(find.text('Select Game'));
    await tester.pumpAndSettle();

    expect(find.text('Live Now'), findsOneWidget);
    expect(find.text('Riverside Raptors'), findsOneWidget);

    await tester.tap(find.text('Riverside Raptors'));
    await tester.pumpAndSettle();

    expect(find.text('Who will win?'), findsOneWidget);
    final confirm = find.widgetWithText(FilledButton, 'Confirm Pick');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await tester.tap(find.widgetWithText(ListTile, 'Northgate Knights'));
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(find.text('You picked Northgate Knights to win!'), findsOneWidget);
    expect(find.text('Live Now'), findsOneWidget);
    expect(
      find.text('Your pick: Northgate Knights (tap to change)'),
      findsOneWidget,
    );
    expect(await PickStore().loadPicks(), {'g1': TeamSide.away});
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

    expect(find.text('Your pick: Alpha Aces (tap to change)'), findsOneWidget);
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
    await _openAppAndLogIn(tester);
    await tester.tap(find.text('Select Game'));
    await tester.pumpAndSettle();

    expect(find.text('1000 coins'), findsOneWidget);

    await tester.tap(find.text('Riverside Raptors'));
    await tester.pumpAndSettle();

    expect(find.textContaining('% of votes'), findsNWidgets(2));

    await tester.tap(find.widgetWithText(ListTile, 'Northgate Knights'));
    final betField = find.byType(TextField);
    await tester.scrollUntilVisible(
      betField,
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.enterText(betField, '5000');
    await tester.pump();

    expect(find.text('You only have 1000 coins'), findsOneWidget);
    final confirm = find.widgetWithText(FilledButton, 'Confirm Pick');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await tester.enterText(betField, '100');
    await tester.pump();
    expect(
      find.textContaining('If Northgate Knights wins you get'),
      findsOneWidget,
    );

    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(
      find.text('You picked Northgate Knights to win and bet 100 coins!'),
      findsOneWidget,
    );
    expect(find.text('900 coins'), findsOneWidget);
    expect(
      find.textContaining('Bet: 100 coins on Northgate Knights'),
      findsOneWidget,
    );
    final session = await Auth().restore();
    expect(await backend.balance(session!.token), 900);
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
      quarter: 4,
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

  test('Fake feed eventually finishes every live game', () async {
    final feed = FakeGameFeed(random: Random(1));
    var games = await feed.fetchGames();
    for (var i = 0; i < 40; i++) {
      games = await feed.fetchGames();
    }
    expect(games.where((g) => g.isLive), isEmpty);
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
}
