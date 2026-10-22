import 'dart:convert';

import '../data/game_feed.dart';
import '../models/bet.dart';
import '../models/crowd_stats.dart';
import '../models/game.dart';
import 'account_server.dart';
import 'fake_players.dart';
import 'payouts.dart';
import 'server_storage.dart';

/// Thrown when the server refuses a bet.
class BetRejected implements Exception {
  const BetRejected(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Stand-in for the betting backend. It owns every player's coins and bets,
/// watches the scores feed, and pays out each game exactly once when it ends:
/// players who backed the winner get their stake back plus a share of the
/// pool (see [splitPool]).
///
/// Players are identified by the session token [AccountServer] gave them, so
/// a request can only touch the coins of whoever logged in. Calls with an
/// invalid token throw [AuthException].
///
/// It doesn't use Flutter, so it can be moved onto a real server unchanged.
// TODO: run this on a real server and have the app call it over the network.
class BettingServer {
  BettingServer({
    required this._feed,
    required this._storage,
    required this._accounts,
    this.botCount = 100,
  });

  static const startingBalance = 1000;

  /// How many bot players bet alongside real ones.
  final int botCount;

  final GameFeed _feed;
  final ServerStorage _storage;
  final AccountServer _accounts;

  // Loaded once and then changed in memory between awaits, so overlapping
  // calls can't overwrite each other's changes.
  _Ledger? _loaded;

  /// Games from the latest feed fetch, keyed by id.
  Map<String, Game> _games = {};

  /// Fetches the latest games. Bots bet on each game the first time it shows
  /// up, and games that have just finished are settled.
  Future<List<Game>> fetchGames() async {
    final games = await _feed.fetchGames();
    final ledger = await _ledger();
    _games = {for (final game in games) game.id: game};
    for (final game in games) {
      if (ledger.seeded.add(game.id)) _placeBotBets(ledger, game);
      if (game.isFinished && ledger.settled.add(game.id)) {
        _settle(ledger, game);
      }
    }
    await _save(ledger);
    return games;
  }

  Future<int> balance(String token) async {
    final player = await _playerFor(token);
    return (await _ledger()).balance(player);
  }

  /// The player's bets keyed by game id.
  Future<Map<String, Bet>> bets(String token) async {
    final player = await _playerFor(token);
    final ledger = await _ledger();
    return {
      for (final MapEntry(key: gameId, value: bets) in ledger.bets.entries)
        gameId: ?bets[player],
    };
  }

  /// Votes and coins bet on [game] by everyone except the player [token]
  /// belongs to, so the app can add the player's own bet back in.
  Future<CrowdStats> crowd(Game game, {String? token}) async {
    final excluding = token == null ? null : await _playerFor(token);
    final ledger = await _ledger();
    final votes = fakeVotesFor(game);
    final bets = [
      for (final MapEntry(key: player, value: bet)
          in (ledger.bets[game.id] ?? const {}).entries)
        if (player != excluding) bet,
    ];
    int pool(TeamSide side) => bets
        .where((b) => b.side == side)
        .fold(0, (total, b) => total + b.amount);
    return CrowdStats(
      homeVotes: votes.home,
      awayVotes: votes.away,
      homePool: pool(TeamSide.home),
      awayPool: pool(TeamSide.away),
    );
  }

  /// Takes [amount] coins from the player and stakes them on [side]. Only
  /// live games take bets, and only one bet per player per game.
  Future<void> placeBet(
    String token,
    String gameId,
    TeamSide side,
    int amount,
  ) async {
    final player = await _playerFor(token);
    final ledger = await _ledger();
    if (_games[gameId]?.isLive != true) {
      throw const BetRejected('Betting is closed for this game.');
    }
    _stake(ledger, player, gameId, side, amount);
    await _save(ledger);
  }

  /// Ids of games where the player's bet was settled since the last call.
  Future<List<String>> takeResults(String token) async {
    final player = await _playerFor(token);
    final ledger = await _ledger();
    final results = ledger.results.remove(player);
    if (results == null) return const [];
    await _save(ledger);
    return results;
  }

  Future<String> _playerFor(String token) async =>
      (await _accounts.accountFor(token)).id;

  void _placeBotBets(_Ledger ledger, Game game) {
    for (final (bot, bet) in fakeBetsFor(game, botCount: botCount)) {
      if (bet.amount <= ledger.balance(bot)) {
        _stake(ledger, bot, game.id, bet.side, bet.amount);
      }
    }
  }

  static void _stake(
    _Ledger ledger,
    String player,
    String gameId,
    TeamSide side,
    int amount,
  ) {
    final balance = ledger.balance(player);
    if (amount <= 0 || amount > balance) {
      throw BetRejected('Bets must be 1 to $balance coins.');
    }
    final bets = ledger.bets.putIfAbsent(gameId, () => {});
    if (bets.containsKey(player)) {
      throw const BetRejected('You already bet on this game.');
    }
    bets[player] = Bet(side: side, amount: amount);
    ledger.balances[player] = balance - amount;
  }

  static void _settle(_Ledger ledger, Game game) {
    final bets = ledger.bets[game.id];
    if (bets == null) return;
    final payouts = splitPool(bets, game.winner);
    for (final MapEntry(key: player, value: bet) in bets.entries) {
      final payout = payouts[player]!;
      bets[player] = Bet(side: bet.side, amount: bet.amount, payout: payout);
      ledger.balances[player] = ledger.balance(player) + payout;
      if (!isBot(player)) {
        ledger.results.putIfAbsent(player, () => []).add(game.id);
      }
    }
  }

  Future<_Ledger> _ledger() async => _loaded ??= await _load();

  Future<_Ledger> _load() async {
    final raw = await _storage.read();
    if (raw == null) return _Ledger();
    return _Ledger.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> _save(_Ledger ledger) =>
      _storage.write(jsonEncode(ledger.toJson()));
}

/// Everything the server stores.
class _Ledger {
  _Ledger();

  factory _Ledger.fromJson(Map<String, dynamic> json) => _Ledger()
    ..balances.addAll((json['balances'] as Map<String, dynamic>).cast())
    ..bets.addAll({
      for (final MapEntry(key: gameId, value: bets)
          in (json['bets'] as Map<String, dynamic>).entries)
        gameId: {
          for (final MapEntry(key: player, value: bet)
              in (bets as Map<String, dynamic>).entries)
            player: Bet.fromJson(bet as Map<String, dynamic>),
        },
    })
    ..seeded.addAll((json['seeded'] as List).cast())
    ..settled.addAll((json['settled'] as List).cast())
    ..results.addAll({
      for (final MapEntry(:key, :value)
          in (json['results'] as Map<String, dynamic>).entries)
        key: (value as List).cast<String>(),
    });

  /// Coins per player. Players who haven't bet yet aren't listed.
  final balances = <String, int>{};

  /// Bets keyed by game id, then player id.
  final bets = <String, Map<String, Bet>>{};

  /// Games bots have already bet on.
  final seeded = <String>{};

  /// Games that have been paid out.
  final settled = <String>{};

  /// Per player, settled games they haven't been told about yet.
  final results = <String, List<String>>{};

  int balance(String player) =>
      balances[player] ?? BettingServer.startingBalance;

  Map<String, Object?> toJson() => {
    'balances': balances,
    'bets': {
      for (final MapEntry(key: gameId, value: bets) in bets.entries)
        gameId: {for (final e in bets.entries) e.key: e.value.toJson()},
    },
    'seeded': seeded.toList(),
    'settled': settled.toList(),
    'results': results,
  };
}
