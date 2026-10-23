import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:football_core/feeds/game_feed.dart';
import 'package:football_core/models/bet.dart';
import 'package:football_core/models/game.dart';
import 'package:football_core/models/game_notification.dart';
import 'package:football_core/models/team_record.dart';
import 'package:football_core/server/account_server.dart';
import 'package:football_core/server/betting_server.dart';
import 'package:football_core/server/payouts.dart';
import 'package:football_core/server/server_storage.dart';

class _ScriptedFeed implements GameFeed {
  _ScriptedFeed(this._responses);

  final List<List<Game>> _responses;
  var _calls = 0;

  @override
  Future<List<Game>> fetchGames() async =>
      _responses[min(_calls++, _responses.length - 1)];

  /// Games returned by [fetchGamesById], whatever ids are asked for.
  List<Game> unlisted = const [];

  @override
  Future<List<Game>> fetchGamesById(Iterable<String> ids) async => unlisted;
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

  group('scoreRangeMultiplier', () {
    test('adds 0.5x per point narrower than the widest range', () {
      expect(scoreRangeMultiplier(null), 1.0);
      expect(scoreRangeMultiplier(const ScoreRange(20, 28)), 1.0);
      expect(scoreRangeMultiplier(const ScoreRange(20, 27)), 1.5);
      expect(scoreRangeMultiplier(const ScoreRange(20, 24)), 3.0);
      expect(scoreRangeMultiplier(const ScoreRange(21, 21)), 5.0);
    });
  });

  group('underdogMultiplier', () {
    test('rewards worse records and never drops below 1x', () {
      expect(underdogMultiplier(null), 1.0);
      expect(underdogMultiplier(const TeamRecord(0, 0)), 1.0);
      expect(underdogMultiplier(const TeamRecord(9, 1)), 1.0);
      expect(underdogMultiplier(const TeamRecord(5, 5)), 1.0);
      expect(underdogMultiplier(const TeamRecord(4, 6)), 1.2);
      expect(underdogMultiplier(const TeamRecord(2, 8)), 1.6);
      expect(underdogMultiplier(const TeamRecord(0, 10)), 2.0);
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

    test('settles bets on games that left the feed before finishing', () async {
      final feed = _ScriptedFeed([
        [_game(GameStatus.live)],
        [],
      ]);
      final server = BettingServer(
        feed: feed,
        storage: MemoryStorage(),
        accounts: accounts,
      );
      final me = await accounts.createAccount('alice', 'password1');
      await server.fetchGames();
      await server.placeBet(me, 'x1', TeamSide.home, 100);

      feed.unlisted = [_game(GameStatus.live)];
      await server.fetchGames();
      expect((await server.bets(me))['x1']!.isSettled, isFalse);

      feed.unlisted = [_game(GameStatus.finished, home: 7)];
      await server.fetchGames();
      final payout = (await server.bets(me))['x1']!.payout!;
      expect(payout, greaterThan(100));
      expect(await server.balance(me), 900 + payout);
      expect(await server.takeResults(me), ['x1']);
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

    test('winning bets on bad teams get the underdog bonus', () async {
      Game game(GameStatus status, {int home = 0, int away = 0}) => Game(
        id: 'x1',
        league: 'Pro Football',
        homeTeam: 'Alpha Aces',
        awayTeam: 'Beta Bulls',
        status: status,
        homeScore: home,
        awayScore: away,
        homeRecord: const TeamRecord(9, 1),
        awayRecord: const TeamRecord(0, 10),
      );
      final server = BettingServer(
        feed: _ScriptedFeed([
          [game(GameStatus.live)],
          [game(GameStatus.finished, away: 3)],
        ]),
        storage: MemoryStorage(),
        accounts: accounts,
        botCount: 0,
      );
      final me = await accounts.createAccount('underdog', 'password1');
      final you = await accounts.createAccount('favorite', 'password1');
      await server.fetchGames();
      await server.placeBet(me, 'x1', TeamSide.away, 100);
      await server.placeBet(you, 'x1', TeamSide.home, 100);
      expect((await server.bets(me))['x1']!.multiplier, 2.0);
      expect((await server.bets(you))['x1']!.multiplier, 1.0);

      await server.fetchGames();
      // 200 from the pool, doubled by the bonus.
      expect((await server.bets(me))['x1']!.payout, 400);
      expect(await server.balance(me), 1300);
      expect(await server.balance(you), 900);
    });

    test('score range bets win only inside the range, with a bonus', () async {
      final server = BettingServer(
        feed: _ScriptedFeed([
          [_game(GameStatus.live)],
          [_game(GameStatus.finished, home: 24, away: 10)],
        ]),
        storage: MemoryStorage(),
        accounts: accounts,
        botCount: 0,
      );
      final hit = await accounts.createAccount('hit', 'password1');
      final miss = await accounts.createAccount('miss', 'password1');
      final loser = await accounts.createAccount('loser', 'password1');
      await server.fetchGames();
      await server.placeBet(
        hit,
        'x1',
        TeamSide.home,
        100,
        scoreRange: const ScoreRange(21, 25),
      );
      await server.placeBet(
        miss,
        'x1',
        TeamSide.home,
        100,
        scoreRange: const ScoreRange(28, 30),
      );
      await server.placeBet(loser, 'x1', TeamSide.away, 100);
      expect((await server.bets(hit))['x1']!.scoreRange.toString(), '21-25');

      await server.fetchGames();
      // The whole 300 pool goes to the only winning bet, times 3.0x for a
      // range 4 points wide.
      expect((await server.bets(hit))['x1']!.payout, 900);
      expect((await server.bets(miss))['x1']!.payout, 0);
      expect((await server.bets(loser))['x1']!.payout, 0);
      expect(await server.balance(miss), 900);
    });

    test('notifies bettors of the halftime score and the result', () async {
      Game live(int quarter, String clock, {int home = 0, int away = 0}) =>
          Game(
            id: 'x1',
            league: 'Pro Football',
            homeTeam: 'Alpha Aces',
            awayTeam: 'Beta Bulls',
            status: GameStatus.live,
            homeScore: home,
            awayScore: away,
            quarter: quarter,
            clock: clock,
          );
      final server = BettingServer(
        feed: _ScriptedFeed([
          [live(1, '9:00')],
          [live(2, '0:00', home: 14, away: 10)],
          [live(3, '12:00', home: 21, away: 10)],
          [_game(GameStatus.finished, home: 24, away: 17)],
        ]),
        storage: MemoryStorage(),
        accounts: accounts,
        botCount: 0,
      );
      final me = await accounts.createAccount('alice', 'password1');
      final you = await accounts.createAccount('bob', 'password1');
      final idle = await accounts.createAccount('carol', 'password1');
      await server.fetchGames();
      await server.placeBet(
        me,
        'x1',
        TeamSide.home,
        100,
        scoreRange: const ScoreRange(28, 30),
      );
      await server.placeBet(you, 'x1', TeamSide.away, 100);
      // Someone has to win, or every stake is refunded.
      final fan = await accounts.createAccount('dave', 'password1');
      await server.placeBet(fan, 'x1', TeamSide.home, 100);
      expect(await server.notifications(me), isEmpty);

      await server.fetchGames();
      await server.fetchGames();
      final halftime = await server.notifications(you);
      expect(halftime, hasLength(1));
      expect(halftime.single.kind, GameNotificationKind.halftime);
      expect(halftime.single.title, 'Halftime: Alpha Aces 14 - 10 Beta Bulls');
      expect(
        halftime.single.body,
        'Your 100-coin bet on Beta Bulls: Beta Bulls trails by 4.',
      );
      expect(
        (await server.notifications(me)).single.body,
        'Your 100-coin bet on Alpha Aces: Alpha Aces leads by 4. '
        'Alpha Aces has 14 points; your range is 28-30.',
      );

      await server.fetchGames();
      final mine = await server.notifications(me);
      expect(mine.map((n) => n.kind), [
        GameNotificationKind.result,
        GameNotificationKind.halftime,
      ]);
      expect(mine.first.title, 'Alpha Aces beat Beta Bulls 24-17');
      expect(
        mine.first.body,
        'Your pick was right, but 24 points missed your 28-30 range. '
        'You lost 100 coins.',
      );
      expect(
        (await server.notifications(fan)).first.body,
        'You won 300 coins on your 100-coin bet.',
      );
      expect(await server.notifications(idle), isEmpty);

      expect(mine.every((n) => !n.read), isTrue);
      await server.markNotificationsRead(me);
      expect((await server.notifications(me)).every((n) => n.read), isTrue);
      expect((await server.notifications(you)).every((n) => !n.read), isTrue);
    });

    test('bails out a broke player once a day', () async {
      final server = BettingServer(
        feed: _ScriptedFeed([
          [_game(GameStatus.live)],
          [_game(GameStatus.finished, away: 7)],
        ]),
        storage: MemoryStorage(),
        accounts: accounts,
        botCount: 0,
      );
      final me = await accounts.createAccount('broke', 'password1');
      final you = await accounts.createAccount('rich', 'password1');
      await server.fetchGames();
      expect(await server.claimBailoutIfBroke(me), 0);

      await server.placeBet(me, 'x1', TeamSide.home, 1000);
      await server.placeBet(you, 'x1', TeamSide.away, 10);
      // Out of coins, but the bet could still win.
      expect(await server.claimBailoutIfBroke(me), 0);

      await server.fetchGames();
      expect(await server.balance(me), 0);
      expect(await server.claimBailoutIfBroke(me), BettingServer.bailoutAmount);
      expect(await server.balance(me), BettingServer.bailoutAmount);
      expect(await server.claimBailoutIfBroke(you), 0);
    });

    test('rejects score ranges wider than the maximum', () async {
      final server = BettingServer(
        feed: _ScriptedFeed([
          [_game(GameStatus.live)],
        ]),
        storage: MemoryStorage(),
        accounts: accounts,
        botCount: 0,
      );
      final me = await accounts.createAccount('wide', 'password1');
      await server.fetchGames();
      for (final range in const [ScoreRange(10, 19), ScoreRange(20, 10)]) {
        await expectLater(
          server.placeBet(me, 'x1', TeamSide.home, 10, scoreRange: range),
          throwsA(isA<BetRejected>()),
        );
      }
      expect(await server.balance(me), 1000);
      await server.placeBet(
        me,
        'x1',
        TeamSide.home,
        10,
        scoreRange: const ScoreRange(10, 18),
      );
    });

    test(
      'crowd counts bettors per side, leaving out the asking player',
      () async {
        final server = BettingServer(
          feed: _ScriptedFeed([
            [_game(GameStatus.live)],
          ]),
          storage: MemoryStorage(),
          accounts: accounts,
          botCount: 0,
        );
        await server.fetchGames();
        final players = [
          for (final name in ['ann', 'ben', 'cat'])
            await accounts.createAccount(name, 'password1'),
        ];
        await server.placeBet(players[0], 'x1', TeamSide.home, 10);
        await server.placeBet(players[1], 'x1', TeamSide.home, 20);
        await server.placeBet(players[2], 'x1', TeamSide.away, 30);

        final everyone = await server.crowd(_game(GameStatus.live));
        expect(everyone.homeBettors, 2);
        expect(everyone.awayBettors, 1);
        final others = await server.crowd(
          _game(GameStatus.live),
          token: players[0],
        );
        expect(others.homeBettors, 1);
        expect(others.homePool, 20);
      },
    );

    test('refunds on a tie are not multiplied', () async {
      const tie = Game(
        id: 'x1',
        league: 'Pro Football',
        homeTeam: 'Alpha Aces',
        awayTeam: 'Beta Bulls',
        status: GameStatus.finished,
        homeScore: 3,
        awayScore: 3,
        awayRecord: TeamRecord(0, 10),
      );
      const live = Game(
        id: 'x1',
        league: 'Pro Football',
        homeTeam: 'Alpha Aces',
        awayTeam: 'Beta Bulls',
        status: GameStatus.live,
        awayRecord: TeamRecord(0, 10),
      );
      final server = BettingServer(
        feed: _ScriptedFeed([
          [live],
          [tie],
        ]),
        storage: MemoryStorage(),
        accounts: accounts,
        botCount: 0,
      );
      final me = await accounts.createAccount('tied', 'password1');
      await server.fetchGames();
      await server.placeBet(me, 'x1', TeamSide.away, 100);
      expect((await server.bets(me))['x1']!.multiplier, 2.0);
      await server.fetchGames();
      expect((await server.bets(me))['x1']!.payout, 100);
    });

    test('uses one owned background at a time and remembers it', () async {
      final storage = MemoryStorage();
      final server = BettingServer(
        feed: _ScriptedFeed([const []]),
        storage: storage,
        accounts: accounts,
        botCount: 0,
      );
      final me = await accounts.createAccount('decorator', 'password1');

      expect(await server.activeShopBackground(me), isNull);
      await expectLater(
        server.setActiveShopBackground(me, 'gridiron'),
        throwsA(isA<ShopRejected>()),
      );
      await server.purchaseShopItem(me, 'stadium_lights');
      await server.purchaseShopItem(me, 'midnight_theme');
      await expectLater(
        server.setActiveShopBackground(me, 'midnight_theme'),
        throwsA(isA<ShopRejected>()),
      );
      await server.setActiveShopBackground(me, 'stadium_lights');

      final restored = BettingServer(
        feed: _ScriptedFeed([const []]),
        storage: storage,
        accounts: accounts,
        botCount: 0,
      );
      expect(await restored.activeShopBackground(me), 'stadium_lights');
      await restored.setActiveShopBackground(me, null);
      expect(await restored.activeShopBackground(me), isNull);
    });

    test('cash out returns half the stake once before halftime', () async {
      final beforeHalftime = Game(
        id: 'x1',
        league: 'Pro Football',
        homeTeam: 'Alpha Aces',
        awayTeam: 'Beta Bulls',
        status: GameStatus.live,
        quarter: 2,
        clock: '3:00',
      );
      final halftime = Game(
        id: 'x1',
        league: 'Pro Football',
        homeTeam: 'Alpha Aces',
        awayTeam: 'Beta Bulls',
        status: GameStatus.live,
        quarter: 2,
        clock: '0:00',
      );
      final server = BettingServer(
        feed: _ScriptedFeed([
          [beforeHalftime],
          [halftime],
        ]),
        storage: MemoryStorage(),
        accounts: accounts,
        botCount: 0,
      );
      final me = await accounts.createAccount('cashout', 'password1');
      await server.fetchGames();
      await server.placeBet(me, 'x1', TeamSide.home, 101);

      expect(await server.cashOutHalf(me, 'x1'), 50);
      expect(await server.balance(me), 949);
      final bet = (await server.bets(me))['x1']!;
      expect(bet.amount, 51);
      expect(bet.cashOutAmount, 50);
      await expectLater(
        server.cashOutHalf(me, 'x1'),
        throwsA(isA<BetRejected>()),
      );

      await server.fetchGames();
      await expectLater(
        server.cashOutHalf(me, 'x1'),
        throwsA(isA<BetRejected>()),
      );
      expect(await server.balance(me), 949);
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

    test('purchases themes and persists one active theme per player', () async {
      final storage = MemoryStorage();
      final server = BettingServer(
        feed: _ScriptedFeed([const []]),
        storage: storage,
        accounts: accounts,
        botCount: 0,
      );
      final me = await accounts.createAccount('shopper', 'password1');

      expect(await server.ownedShopItems(me), contains('basic_theme'));
      expect(await server.activeShopTheme(me), 'basic_theme');
      expect(await server.purchaseShopItem(me, 'midnight_theme'), 500);
      expect(await server.ownedShopItems(me), contains('midnight_theme'));
      await server.setActiveShopTheme(me, 'midnight_theme');
      expect(await server.activeShopTheme(me), 'midnight_theme');
      await server.setActiveShopTheme(me, 'basic_theme');
      expect(await server.activeShopTheme(me), 'basic_theme');

      await expectLater(
        server.purchaseShopItem(me, 'midnight_theme'),
        throwsA(isA<ShopRejected>()),
      );
      await expectLater(
        server.setActiveShopTheme(me, 'stadium_lights'),
        throwsA(isA<ShopRejected>()),
      );

      final restored = BettingServer(
        feed: _ScriptedFeed([const []]),
        storage: storage,
        accounts: accounts,
        botCount: 0,
      );
      expect(await restored.ownedShopItems(me), contains('midnight_theme'));
      expect(await restored.activeShopTheme(me), 'basic_theme');
      expect(await restored.balance(me), 500);
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
