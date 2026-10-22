import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:footballapp/data/game_feed.dart';
import 'package:footballapp/models/bet.dart';
import 'package:footballapp/models/game.dart';
import 'package:footballapp/server/account_server.dart';
import 'package:footballapp/server/betting_server.dart';
import 'package:footballapp/server/payouts.dart';
import 'package:footballapp/server/server_storage.dart';

class _ScriptedFeed implements GameFeed {
  _ScriptedFeed(this._responses);

  final List<List<Game>> _responses;
  var _calls = 0;

  @override
  Future<List<Game>> fetchGames() async =>
      _responses[min(_calls++, _responses.length - 1)];
}

Game _game(GameStatus status, {int home = 0, int away = 0}) => Game(
  id: 'x1',
  league: 'Pro Football',
  homeTeam: 'Alpha Aces',
  awayTeam: 'Beta Bulls',
  status: status,
  homeScore: home,
  awayScore: away,
);

void main() {
  group('splitPool', () {
    test('winners get their stake back plus a share of the losers coins', () {
      final payouts = splitPool({
        'a': const Bet(side: TeamSide.home, amount: 100),
        'b': const Bet(side: TeamSide.home, amount: 300),
        'c': const Bet(side: TeamSide.away, amount: 200),
      }, TeamSide.home);
      expect(payouts, {'a': 150, 'b': 450, 'c': 0});
    });

    test('pays out the whole pool when shares round down', () {
      final payouts = splitPool({
        'a': const Bet(side: TeamSide.home, amount: 1),
        'b': const Bet(side: TeamSide.home, amount: 1),
        'c': const Bet(side: TeamSide.home, amount: 1),
        'd': const Bet(side: TeamSide.away, amount: 10),
      }, TeamSide.home);
      expect(payouts.values.reduce((a, b) => a + b), 13);
      expect(payouts['d'], 0);
      for (final player in ['a', 'b', 'c']) {
        expect(payouts[player], inInclusiveRange(4, 5));
      }
    });

    test('refunds everyone on a tie or when nobody backed the winner', () {
      final bets = {
        'a': const Bet(side: TeamSide.home, amount: 100),
        'b': const Bet(side: TeamSide.home, amount: 50),
      };
      expect(splitPool(bets, null), {'a': 100, 'b': 50});
      expect(splitPool(bets, TeamSide.away), {'a': 100, 'b': 50});
    });
  });

  group('BettingServer', () {
    late AccountServer accounts;
    setUp(
      () =>
          accounts = AccountServer(storage: MemoryStorage(), hashIterations: 1),
    );

    test('settles every bet once and pays winners from the pool', () async {
      final storage = MemoryStorage();
      final server = BettingServer(
        feed: _ScriptedFeed([
          [_game(GameStatus.live)],
          [_game(GameStatus.finished, home: 7)],
        ]),
        storage: storage,
        accounts: accounts,
      );
      final me = await accounts.createAccount('alice', 'password1');
      final you = await accounts.createAccount('bob', 'password1');
      await server.fetchGames();
      await server.placeBet(me, 'x1', TeamSide.home, 100);
      await server.placeBet(you, 'x1', TeamSide.away, 100);
      final crowd = await server.crowd(_game(GameStatus.live));
      expect(crowd.homePool, greaterThanOrEqualTo(100));
      expect(await server.balance(me), 900);

      await server.fetchGames();
      final payout = (await server.bets(me))['x1']!.payout!;
      expect(payout, greaterThan(100));
      expect(await server.balance(me), 900 + payout);
      expect((await server.bets(you))['x1']!.payout, 0);
      expect(await server.balance(you), 900);
      expect(await server.takeResults(me), ['x1']);
      expect(await server.takeResults(me), isEmpty);

      // Fetching the finished game again must not pay out twice, even after
      // the server restarts from what it saved.
      await server.fetchGames();
      final restarted = BettingServer(
        feed: _ScriptedFeed([
          [_game(GameStatus.finished, home: 7)],
        ]),
        storage: storage,
        accounts: accounts,
      );
      await restarted.fetchGames();
      expect(await restarted.balance(me), 900 + payout);
    });

    test('pays out exactly the coins that were bet', () async {
      final server = BettingServer(
        feed: _ScriptedFeed([
          [_game(GameStatus.live)],
          [_game(GameStatus.finished, away: 3)],
        ]),
        storage: MemoryStorage(),
        accounts: accounts,
        botCount: 0,
      );
      await server.fetchGames();
      final players = [
        for (final name in ['alice', 'bob', 'carol'])
          await accounts.createAccount(name, 'password1'),
      ];
      await server.placeBet(players[0], 'x1', TeamSide.away, 10);
      await server.placeBet(players[1], 'x1', TeamSide.away, 20);
      await server.placeBet(players[2], 'x1', TeamSide.home, 37);
      await server.fetchGames();

      var paid = 0;
      for (final player in players) {
        paid += (await server.bets(player))['x1']!.payout!;
      }
      expect(paid, 10 + 20 + 37);
    });

    test('rejects requests without a valid session', () async {
      final server = BettingServer(
        feed: _ScriptedFeed([
          [_game(GameStatus.live)],
        ]),
        storage: MemoryStorage(),
        accounts: accounts,
      );
      await server.fetchGames();
      expect(server.balance('not-a-token'), throwsA(isA<AuthException>()));
      expect(
        server.placeBet('not-a-token', 'x1', TeamSide.home, 10),
        throwsA(isA<AuthException>()),
      );
    });

    test('rejects bets on closed games, over the balance, or twice', () async {
      final server = BettingServer(
        feed: _ScriptedFeed([
          [_game(GameStatus.live)],
          [_game(GameStatus.finished, home: 7)],
        ]),
        storage: MemoryStorage(),
        accounts: accounts,
      );
      final me = await accounts.createAccount('alice', 'password1');
      final you = await accounts.createAccount('bob', 'password1');
      await server.fetchGames();
      expect(
        server.placeBet(me, 'x1', TeamSide.home, 1001),
        throwsA(isA<BetRejected>()),
      );
      await server.placeBet(me, 'x1', TeamSide.home, 10);
      expect(
        server.placeBet(me, 'x1', TeamSide.away, 10),
        throwsA(isA<BetRejected>()),
      );

      await server.fetchGames();
      expect(
        server.placeBet(you, 'x1', TeamSide.home, 10),
        throwsA(isA<BetRejected>()),
      );
    });
  });
}
