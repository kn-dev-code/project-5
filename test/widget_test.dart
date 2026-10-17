import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:footballapp/data/game_feed.dart';
import 'package:footballapp/data/pick_store.dart';
import 'package:footballapp/main.dart';
import 'package:footballapp/models/game.dart';
import 'package:footballapp/screens/game_select_screen.dart';

class _ScriptedFeed implements GameFeed {
  _ScriptedFeed(this._responses);

  final List<List<Game>> _responses;
  var _calls = 0;

  @override
  Future<List<Game>> fetchGames() async =>
      _responses[min(_calls++, _responses.length - 1)];
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Login screen leads to homepage with Select Game and Shop', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const FootballWinnerApp());

    expect(find.widgetWithText(TextField, 'Name'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Password'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Log In'));
    await tester.pumpAndSettle();

    expect(find.text('Select Game'), findsOneWidget);
    expect(find.text('Shop'), findsOneWidget);
  });

  testWidgets('Select Game lists games and lets the user pick a live winner', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const FootballWinnerApp());

    await tester.tap(find.widgetWithText(FilledButton, 'Log In'));
    await tester.pumpAndSettle();
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

    await tester.pumpWidget(
      MaterialApp(
        home: GameSelectScreen(
          feed: _ScriptedFeed([
            [live],
            [finished],
          ]),
        ),
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

  test('Fake feed eventually finishes every live game', () async {
    final feed = FakeGameFeed(random: Random(1));
    var games = await feed.fetchGames();
    for (var i = 0; i < 40; i++) {
      games = await feed.fetchGames();
    }
    expect(games.where((g) => g.isLive), isEmpty);
  });

  testWidgets('Create account screen asks for username and password twice', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const FootballWinnerApp());

    await tester.tap(find.text("Don't have an account? Create one"));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Username'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Password'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Confirm Password'), findsOneWidget);
  });
}
