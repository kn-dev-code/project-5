
import 'dart:convert';

import '../data/game_feed.dart';
import '../models/bet.dart';
import '../models/crowd_stats.dart';
import '../models/game.dart';
import '../models/shop_item.dart';
import 'account_server.dart';
import 'fake_players.dart';
import 'payouts.dart';
import 'server_storage.dart';

/// Thrown when the server refuses a bet or reward claim.
class BetRejected implements Exception {
  const BetRejected(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thrown when a shop purchase cannot be completed.
class ShopRejected implements Exception {
  const ShopRejected(this.message);

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
///
/// TODO: Run this on a real server and have the app call it over the network.
class BettingServer {
  BettingServer({
    required GameFeed feed,
    required ServerStorage storage,
    required AccountServer accounts,
    this.botCount = 100,
  })  : _feed = feed,
        _storage = storage,
        _accounts = accounts;

  static const startingBalance = 1000;

  /// Coins awarded for a successful daily claim.
  static const dailyRewardAmount = 250;

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
      if (ledger.seeded.add(game.id)) {
        _placeBotBets(ledger, game);
      }

      if (game.isFinished && ledger.settled.add(game.id)) {
        _settle(ledger, game);
      }
    }

    await _save(ledger);
    return games;
  }

  /// Returns a player's current spendable coin balance.
  Future<int> balance(String token) async {
    final player = await _playerFor(token);
    return (await _ledger()).balance(player);
  }

  /// Items owned by the player, returned as catalog ids.
  Future<Set<String>> ownedShopItems(String token) async {
    final player = await _playerFor(token);
    final ledger = await _ledger();
    return Set.unmodifiable({
      startingTheme.id,
      ...(ledger.ownedShopItems[player] ?? <String>{}),
    });
  }

  /// The id of the player's active theme, defaulting to the free basic theme.
  Future<String> activeShopTheme(String token) async {
    final player = await _playerFor(token);
    final ledger = await _ledger();
    return ledger.activeShopThemes[player] ?? startingTheme.id;
  }

  /// Activates one owned theme. Background items cannot be activated as themes.
  Future<void> setActiveShopTheme(String token, String themeId) async {
    final player = await _playerFor(token);
    final ledger = await _ledger();
    final item = themeId == startingTheme.id
        ? startingTheme
        : _shopItemById(themeId);
    if (item == null || item.type != ShopItemType.theme) {
      throw const ShopRejected('That theme is unavailable.');
    }
    if (themeId != startingTheme.id &&
        !(ledger.ownedShopItems[player]?.contains(themeId) ?? false)) {
      throw const ShopRejected('Purchase this theme before activating it.');
    }
    ledger.activeShopThemes[player] = themeId;
    await _save(ledger);
  }

  /// Purchases a catalog item using the player's spendable coins.
  /// The balance deduction and ownership record are saved together.
  Future<int> purchaseShopItem(String token, String itemId) async {
    final player = await _playerFor(token);
    final ledger = await _ledger();
    final item = _shopItemById(itemId);
    if (item == null) throw const ShopRejected('That item is unavailable.');

    final owned = ledger.ownedShopItems.putIfAbsent(player, () => <String>{});
    if (owned.contains(itemId)) {
      throw const ShopRejected('You already own this item.');
    }

    final balance = ledger.balance(player);
    if (balance < item.price) {
      throw ShopRejected('You need ${item.price - balance} more coins.');
    }

    ledger.balances[player] = balance - item.price;
    owned.add(itemId);
    await _save(ledger);
    return ledger.balance(player);
  }

  static ShopItem? _shopItemById(String id) {
    for (final item in shopItems) {
      if (item.id == id) return item;
    }
    return null;
  }

  // ------------------------------------------------------------
  // DAILY CURRENCY REWARDS
  // ------------------------------------------------------------

  /// Returns today's date in UTC, formatted as YYYY-MM-DD.
  static String _todayUtc() {
    final now = DateTime.now().toUtc();

    final year = now.year.toString().padLeft(4, '0');
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');

    return '$year-$month-$day';
  }

  /// Returns true if the player can claim today's daily reward.
  ///
  /// Claims reset at midnight UTC.
  Future<bool> canClaimDailyReward(String token) async {
    final player = await _playerFor(token);
    final ledger = await _ledger();

    final lastClaim = ledger.dailyClaims[player];
    final today = _todayUtc();

    return lastClaim == null || lastClaim.compareTo(today) < 0;
  }

  /// Claims the daily reward and returns the player's updated balance.
  ///
  /// Rewards are granted once per UTC calendar day for each player.
  /// A second claim on the same day throws [BetRejected].
  Future<int> claimDailyReward(String token) async {
    final player = await _playerFor(token);
    final ledger = await _ledger();

    final today = _todayUtc();
    final lastClaim = ledger.dailyClaims[player];

    if (lastClaim != null && lastClaim.compareTo(today) >= 0) {
      throw const BetRejected(
        'Daily reward already claimed. Come back tomorrow!',
      );
    }

    final oldBalance = ledger.balance(player);

    final newBalance = oldBalance + dailyRewardAmount;

    ledger.balances[player] = newBalance;
    ledger.dailyClaims[player] = today;

    await _save(ledger);

    return newBalance;
  }

  /// Returns the UTC date of the player's last daily reward claim.
  ///
  /// Returns null if the player has never claimed a reward.
  Future<String?> lastDailyRewardClaim(String token) async {
    final player = await _playerFor(token);
    final ledger = await _ledger();

    return ledger.dailyClaims[player];
  }

  /// Returns how many coins the daily reward provides.
  Future<int> dailyRewardValue() async {
    return dailyRewardAmount;
  }

  // ------------------------------------------------------------
  // PLAYER BETS
  // ------------------------------------------------------------

  /// The player's bets keyed by game id.
  Future<Map<String, Bet>> bets(String token) async {
    final player = await _playerFor(token);
    final ledger = await _ledger();

    return {
      for (final MapEntry(key: gameId, value: bets)
          in ledger.bets.entries)
        gameId: ?bets[player],
    };
  }

  /// Votes and coins bet on [game] by everyone except the player [token]
  /// belongs to, so the app can add the player's own bet back in.
  Future<CrowdStats> crowd(Game game, {String? token}) async {
    final excluding =
        token == null ? null : await _playerFor(token);

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

  /// Takes [amount] coins from the player and stakes them on [side].
  /// Only live games take bets, and only one bet per player per game.
  Future<void> placeBet(
    String token,
    String gameId,
    TeamSide side,
    int amount,
  ) async {
    final player = await _playerFor(token);
    final ledger = await _ledger();

    if (_games[gameId]?.isLive != true) {
      throw const BetRejected(
        'Betting is closed for this game.',
      );
    }

    _stake(ledger, player, gameId, side, amount);

    await _save(ledger);
  }

  /// Returns half of the player's stake once, while the game is before
  /// halftime. The remaining stake stays in the pool and can still win.
  Future<int> cashOutHalf(
    String token,
    String gameId,
  ) async {
    final player = await _playerFor(token);
    final ledger = await _ledger();

    final game = _games[gameId];

    if (game?.isBeforeHalftime != true) {
      throw const BetRejected(
        'Cash out is only available before halftime.',
      );
    }

    final bet = ledger.bets[gameId]?[player];

    if (bet == null || bet.isSettled) {
      throw const BetRejected(
        'You have no active bet to cash out.',
      );
    }

    if (bet.cashOutAmount > 0) {
      throw const BetRejected(
        'You already cashed out this bet.',
      );
    }

    final refund = bet.amount ~/ 2;

    if (refund == 0) {
      throw const BetRejected(
        'Your bet is too small to cash out half.',
      );
    }

    ledger.bets[gameId]![player] = Bet(
      side: bet.side,
      amount: bet.amount - refund,
      cashOutAmount: refund,
    );

    ledger.balances[player] =
        ledger.balance(player) + refund;

    await _save(ledger);

    return refund;
  }

  /// Ids of games where the player's bet was settled since the last call.
  Future<List<String>> takeResults(String token) async {
    final player = await _playerFor(token);
    final ledger = await _ledger();

    final results = ledger.results.remove(player);

    if (results == null) {
      return const [];
    }

    await _save(ledger);

    return results;
  }

  Future<String> _playerFor(String token) async =>
      (await _accounts.accountFor(token)).id;

  void _placeBotBets(_Ledger ledger, Game game) {
    for (final (bot, bet) in fakeBetsFor(
      game,
      botCount: botCount,
    )) {
      if (bet.amount <= ledger.balance(bot)) {
        _stake(
          ledger,
          bot,
          game.id,
          bet.side,
          bet.amount,
        );
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
      throw BetRejected(
        'Bets must be 1 to $balance coins.',
      );
    }

    final bets =
        ledger.bets.putIfAbsent(gameId, () => {});

    if (bets.containsKey(player)) {
      throw const BetRejected(
        'You already bet on this game.',
      );
    }

    bets[player] = Bet(
      side: side,
      amount: amount,
    );

    ledger.balances[player] = balance - amount;
  }

  static void _settle(_Ledger ledger, Game game) {
    final bets = ledger.bets[game.id];

    if (bets == null) {
      return;
    }

    final payouts = splitPool(bets, game.winner);

    for (final MapEntry(key: player, value: bet)
        in bets.entries) {
      final payout = payouts[player]!;

      bets[player] = Bet(
        side: bet.side,
        amount: bet.amount,
        payout: payout,
        cashOutAmount: bet.cashOutAmount,
      );

      ledger.balances[player] =
          ledger.balance(player) + payout;

      if (!isBot(player)) {
        ledger.results
            .putIfAbsent(player, () => [])
            .add(game.id);
      }
    }
  }

  Future<_Ledger> _ledger() async =>
      _loaded ??= await _load();

  Future<_Ledger> _load() async {
    final raw = await _storage.read();

    if (raw == null) {
      return _Ledger();
    }

    return _Ledger.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  Future<void> _save(_Ledger ledger) =>
      _storage.write(jsonEncode(ledger.toJson()));
}

/// Everything the server stores.
class _Ledger {
  _Ledger();

  factory _Ledger.fromJson(Map<String, dynamic> json) =>
      _Ledger()
        ..balances.addAll(
          (json['balances'] as Map<String, dynamic>)
              .cast<String, int>(),
        )
        ..dailyClaims.addAll(
          (json['dailyClaims'] as Map<String, dynamic>? ??
                  <String, dynamic>{})
              .map(
            (key, value) =>
                MapEntry(key, value as String),
          ),
        )
        ..ownedShopItems.addAll({
          for (final MapEntry(key: player, value: ids)
              in (json['ownedShopItems'] as Map<String, dynamic>? ?? {})
                  .entries)
            player: (ids as List).cast<String>().toSet(),
        })
        ..activeShopThemes.addAll(
          (json['activeShopThemes'] as Map<String, dynamic>? ?? {})
              .map((key, value) => MapEntry(key, value as String)),
        )
        ..bets.addAll({
          for (final MapEntry(key: gameId, value: bets)
              in (json['bets'] as Map<String, dynamic>)
                  .entries)
            gameId: {
              for (final MapEntry(
                    key: player,
                    value: bet,
                  ) in (bets as Map<String, dynamic>).entries)
                player: Bet.fromJson(
                  bet as Map<String, dynamic>,
                ),
            },
        })
        ..seeded.addAll(
          (json['seeded'] as List).cast<String>(),
        )
        ..settled.addAll(
          (json['settled'] as List).cast<String>(),
        )
        ..results.addAll({
          for (final MapEntry(:key, :value)
              in (json['results'] as Map<String, dynamic>)
                  .entries)
            key: (value as List).cast<String>(),
        });

  /// Coins per player. Players who haven't bet yet aren't listed.
  final balances = <String, int>{};

  /// Last daily reward claim per player.
  ///
  /// Dates are stored as YYYY-MM-DD in UTC.
  final dailyClaims = <String, String>{};

  /// Purchased shop item ids, keyed by player id.
  final ownedShopItems = <String, Set<String>>{};

  /// Active shop theme id per player.
  final activeShopThemes = <String, String>{};

  /// Bets keyed by game id, then player id.
  final bets = <String, Map<String, Bet>>{};

  /// Games bots have already bet on.
  final seeded = <String>{};

  /// Games that have been paid out.
  final settled = <String>{};

  /// Per player, settled games they haven't been told about yet.
  final results = <String, List<String>>{};

  int balance(String player) =>
      balances[player] ??
      BettingServer.startingBalance;

  Map<String, Object?> toJson() => {
        'balances': balances,
        'dailyClaims': dailyClaims,
        'ownedShopItems': {
          for (final entry in ownedShopItems.entries)
            entry.key: entry.value.toList(),
        },
        'activeShopThemes': activeShopThemes,
        'bets': {
          for (final MapEntry(
                key: gameId,
                value: bets,
              ) in bets.entries)
            gameId: {
              for (final e in bets.entries)
                e.key: e.value.toJson(),
            },
        },
        'seeded': seeded.toList(),
        'settled': settled.toList(),
        'results': results,
      };
}
