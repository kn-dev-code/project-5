import 'dart:convert';

import '../api/betting_api.dart';

import '../feeds/game_feed.dart';
import '../models/bet.dart';
import '../models/crowd_stats.dart';
import '../models/game.dart';
import '../models/game_notification.dart';
import '../models/shop_catalog.dart';
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

/// The betting backend. It owns every player's coins and bets,
/// watches the scores feed, and pays out each game exactly once when it ends:
/// players who backed the winner get their stake back plus a share of the
/// pool (see [splitPool]), times an underdog bonus based on the team's record
/// (see [underdogMultiplier]). Players can also name a range for the winner's
/// score: a narrower range earns a bigger bonus (see [scoreRangeMultiplier]),
/// but the bet loses if the score falls outside it.
///
/// Players are sent a [GameNotification] with the score at halftime of each
/// game they bet on, and another with the outcome once it is settled.
///
/// Players are identified by the session token [AccountServer] gave them, so
/// a request can only touch the coins of whoever logged in. Calls with an
/// invalid token throw [AuthException].
///
/// It doesn't use Flutter. The football_server package serves it over HTTP,
/// and the app runs it in-process for tests and offline play.
class BettingServer implements BettingApi {
  BettingServer({
    required GameFeed feed,
    required ServerStorage storage,
    required AccountServer accounts,
    this.botCount = 100,
  }) : _feed = feed,
       _storage = storage,
       _accounts = accounts;

  static const startingBalance = 1000;

  /// Coins awarded for a successful daily claim.
  static const dailyRewardAmount = 250;

  /// Coins given once a day to a player who is out of coins with nothing left
  /// riding on a game, so they can always keep betting.
  static const bailoutAmount = 100;

  /// Older notifications are dropped once a player has more than this many.
  static const maxNotifications = 50;

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

  /// The game with [id] from the latest fetch, if it was listed.
  Game? gameById(String id) => _games[id];

  /// Fetches the latest games. Bots bet on each game the first time it shows
  /// up, and games that have just finished are settled.
  @override
  Future<List<Game>> fetchGames() async {
    final games = await _feed.fetchGames();
    final ledger = await _ledger();

    _games = {for (final game in games) game.id: game};

    for (final game in games) {
      if (ledger.seeded.add(game.id)) {
        _placeBotBets(ledger, game);
      }

      if (game.isHalftimeOrLater && ledger.halftimeSent.add(game.id)) {
        _notifyHalftime(ledger, game);
      }

      if (game.isFinished && ledger.settled.add(game.id)) {
        _settle(ledger, game);
      }
    }

    // Games can drop off the feed before the server sees them finish, e.g.
    // while the app was closed, so look those up to pay their bets out.
    final unlisted = [
      for (final id in ledger.bets.keys)
        if (!ledger.settled.contains(id) && !_games.containsKey(id)) id,
    ];
    if (unlisted.isNotEmpty) {
      for (final game in await _feed.fetchGamesById(unlisted)) {
        if (game.isFinished && ledger.settled.add(game.id)) {
          _settle(ledger, game);
        }
      }
    }

    await _save(ledger);
    return games;
  }

  /// Returns a player's current spendable coin balance.
  @override
  Future<int> balance(String token) async {
    final player = await _playerFor(token);
    return (await _ledger()).balance(player);
  }

  /// Items owned by the player, returned as catalog ids.
  @override
  Future<Set<String>> ownedShopItems(String token) async {
    final player = await _playerFor(token);
    final ledger = await _ledger();
    return Set.unmodifiable({
      startingThemeListing.id,
      ...(ledger.ownedShopItems[player] ?? <String>{}),
    });
  }

  /// The id of the player's active theme, defaulting to the free basic theme.
  @override
  Future<String> activeShopTheme(String token) async {
    final player = await _playerFor(token);
    final ledger = await _ledger();
    return ledger.activeShopThemes[player] ?? startingThemeListing.id;
  }

  /// Activates one owned theme. Background items cannot be activated as themes.
  @override
  Future<void> setActiveShopTheme(String token, String themeId) async {
    final player = await _playerFor(token);
    final ledger = await _ledger();
    final item = themeId == startingThemeListing.id
        ? startingThemeListing
        : shopListingById(themeId);
    if (item == null || item.type != ShopItemType.theme) {
      throw const ShopRejected('That theme is unavailable.');
    }
    if (themeId != startingThemeListing.id &&
        !(ledger.ownedShopItems[player]?.contains(themeId) ?? false)) {
      throw const ShopRejected('Purchase this theme before activating it.');
    }
    ledger.activeShopThemes[player] = themeId;
    await _save(ledger);
  }

  /// The id of the player's active background, or null if none is set.
  @override
  Future<String?> activeShopBackground(String token) async {
    final player = await _playerFor(token);
    final ledger = await _ledger();
    return ledger.activeShopBackgrounds[player];
  }

  /// Shows one owned background, or goes back to none when [backgroundId] is
  /// null.
  @override
  Future<void> setActiveShopBackground(
    String token,
    String? backgroundId,
  ) async {
    final player = await _playerFor(token);
    final ledger = await _ledger();
    if (backgroundId == null) {
      ledger.activeShopBackgrounds.remove(player);
      await _save(ledger);
      return;
    }
    final item = shopListingById(backgroundId);
    if (item == null || item.type != ShopItemType.background) {
      throw const ShopRejected('That background is unavailable.');
    }
    if (!(ledger.ownedShopItems[player]?.contains(backgroundId) ?? false)) {
      throw const ShopRejected('Purchase this background before using it.');
    }
    ledger.activeShopBackgrounds[player] = backgroundId;
    await _save(ledger);
  }

  /// Purchases a catalog item using the player's spendable coins.
  /// The balance deduction and ownership record are saved together.
  @override
  Future<int> purchaseShopItem(String token, String itemId) async {
    final player = await _playerFor(token);
    final ledger = await _ledger();
    final item = shopListingById(itemId);
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
  @override
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
  @override
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

  /// Gives the player [bailoutAmount] coins if they have none left and no
  /// unsettled bets that could win some back. Works once per UTC day.
  ///
  /// Returns the coins given, or 0 if the player didn't need or can't get a
  /// bailout yet.
  @override
  Future<int> claimBailoutIfBroke(String token) async {
    final player = await _playerFor(token);
    final ledger = await _ledger();

    final today = _todayUtc();
    final lastBailout = ledger.bailouts[player];
    if (lastBailout != null && lastBailout.compareTo(today) >= 0) return 0;
    if (ledger.balance(player) > 0) return 0;
    final hasActiveBet = ledger.bets.values.any(
      (bets) => bets[player]?.isSettled == false,
    );
    if (hasActiveBet) return 0;

    ledger.balances[player] = ledger.balance(player) + bailoutAmount;
    ledger.bailouts[player] = today;
    await _save(ledger);
    return bailoutAmount;
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

  /// The next daily reward reset, at midnight UTC.
  /// This uses a calendar-day reset rather than a rolling 24-hour cooldown.
  DateTime nextDailyRewardResetUtc() {
    final now = DateTime.now().toUtc();
    return DateTime.utc(now.year, now.month, now.day + 1);
  }

  /// How long until this player can claim again. Zero means ready to claim.
  Future<Duration> timeUntilDailyReward(String token) async {
    if (await canClaimDailyReward(token)) return Duration.zero;
    return nextDailyRewardResetUtc().difference(DateTime.now().toUtc());
  }

  // ------------------------------------------------------------
  // NOTIFICATIONS
  // ------------------------------------------------------------

  /// The player's notifications, newest first.
  @override
  Future<List<GameNotification>> notifications(String token) async {
    final player = await _playerFor(token);
    final ledger = await _ledger();
    return List.unmodifiable(
      (ledger.notifications[player] ?? const []).reversed,
    );
  }

  /// Marks all of the player's notifications as read.
  @override
  Future<void> markNotificationsRead(String token) async {
    final player = await _playerFor(token);
    final ledger = await _ledger();
    final notifications = ledger.notifications[player];
    if (notifications == null || notifications.every((n) => n.read)) return;
    ledger.notifications[player] = [
      for (final n in notifications) n.markedRead(),
    ];
    await _save(ledger);
  }

  /// Tells every player with a bet on [game] the score at halftime, or the
  /// latest score if the server first saw the game after halftime.
  static void _notifyHalftime(_Ledger ledger, Game game) {
    final bets = ledger.bets[game.id];
    if (bets == null) return;

    final when = game.quarter! <= 3 ? 'Halftime' : game.gameClock!;
    for (final MapEntry(key: player, value: bet) in bets.entries) {
      if (isBot(player)) continue;
      _notify(
        ledger,
        player,
        game.id,
        GameNotificationKind.halftime,
        '$when: ${game.homeTeam} ${game.homeScore} - '
        '${game.awayScore} ${game.awayTeam}',
        _halftimeStatus(game, bet),
      );
    }
  }

  static String _halftimeStatus(Game game, Bet bet) {
    final team = game.teamName(bet.side);
    final other = bet.side == TeamSide.home ? TeamSide.away : TeamSide.home;
    final score = game.score(bet.side);
    final lead = score - game.score(other);
    final standing = lead > 0
        ? '$team leads by $lead.'
        : lead < 0
        ? '$team trails by ${-lead}.'
        : "It's tied.";
    final status = 'Your ${bet.amount}-coin bet on $team: $standing';

    final range = bet.scoreRange;
    if (range == null) return status;
    if (score > range.high) {
      return '$status $team already has $score points, above your $range '
          'range.';
    }
    return '$status $team has $score points; your range is $range.';
  }

  static String _resultTitle(Game game) {
    final winner = game.winner;
    if (winner == null) {
      return '${game.homeTeam} and ${game.awayTeam} tied '
          '${game.homeScore}-${game.awayScore}';
    }
    final loser = winner == TeamSide.home ? TeamSide.away : TeamSide.home;
    return '${game.teamName(winner)} beat ${game.teamName(loser)} '
        '${game.score(winner)}-${game.score(loser)}';
  }

  static String _resultStatus(Game game, Bet bet, int payout) {
    if (bet.wins(game.winner, game.winningScore)) {
      return 'You won $payout coins on your ${bet.amount}-coin bet.';
    }
    if (payout > 0) return 'Your ${bet.amount} coins were refunded.';
    final range = bet.scoreRange;
    if (bet.side == game.winner && range != null) {
      return 'Your pick was right, but ${game.winningScore} points missed '
          'your $range range. You lost ${bet.amount} coins.';
    }
    return 'You lost ${bet.amount} coins.';
  }

  static void _notify(
    _Ledger ledger,
    String player,
    String gameId,
    GameNotificationKind kind,
    String title,
    String body,
  ) {
    final notifications = ledger.notifications.putIfAbsent(player, () => [])
      ..add(
        GameNotification(
          id: ledger.nextNotificationId++,
          gameId: gameId,
          kind: kind,
          title: title,
          body: body,
          sentAt: DateTime.now().toUtc(),
        ),
      );
    if (notifications.length > maxNotifications) {
      notifications.removeRange(0, notifications.length - maxNotifications);
    }
  }

  // ------------------------------------------------------------
  // PLAYER BETS
  // ------------------------------------------------------------

  /// The player's bets keyed by game id.
  @override
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
  @override
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

    int bettors(TeamSide side) => bets.where((b) => b.side == side).length;

    return CrowdStats(
      homeVotes: votes.home,
      awayVotes: votes.away,
      homePool: pool(TeamSide.home),
      awayPool: pool(TeamSide.away),
      homeBettors: bettors(TeamSide.home),
      awayBettors: bettors(TeamSide.away),
    );
  }

  /// Takes [amount] coins from the player and stakes them on [side].
  /// Bets are taken until the end of the first quarter (see
  /// [Game.isBettingOpen]), one per player per game.
  ///
  /// With a [scoreRange], the bet also needs [side]'s final score to land
  /// inside it, in exchange for a bigger payout.
  @override
  Future<void> placeBet(
    String token,
    String gameId,
    TeamSide side,
    int amount, {
    ScoreRange? scoreRange,
  }) async {
    final player = await _playerFor(token);
    final ledger = await _ledger();

    if (_games[gameId]?.isBettingOpen != true) {
      throw const BetRejected(
        'Betting is closed for this game. Bets close at the end of the first '
        'quarter.',
      );
    }

    if (scoreRange != null && !isValidScoreRange(scoreRange)) {
      throw const BetRejected(
        'Score ranges must be at most $maxScoreRangeWidth points wide.',
      );
    }

    _stake(ledger, player, gameId, side, amount, scoreRange: scoreRange);

    await _save(ledger);
  }

  /// Returns half of the player's stake once, while the game is before
  /// halftime. The remaining stake stays in the pool and can still win.
  @override
  Future<int> cashOutHalf(String token, String gameId) async {
    final player = await _playerFor(token);
    final ledger = await _ledger();

    final game = _games[gameId];

    if (game?.isBeforeHalftime != true) {
      throw const BetRejected('Cash out is only available before halftime.');
    }

    final bet = ledger.bets[gameId]?[player];

    if (bet == null || bet.isSettled) {
      throw const BetRejected('You have no active bet to cash out.');
    }

    if (bet.cashOutAmount > 0) {
      throw const BetRejected('You already cashed out this bet.');
    }

    final refund = bet.amount ~/ 2;

    if (refund == 0) {
      throw const BetRejected('Your bet is too small to cash out half.');
    }

    ledger.bets[gameId]![player] = Bet(
      side: bet.side,
      amount: bet.amount - refund,
      cashOutAmount: refund,
      multiplier: bet.multiplier,
      scoreRange: bet.scoreRange,
    );

    ledger.balances[player] = ledger.balance(player) + refund;

    await _save(ledger);

    return refund;
  }

  /// Cancels the player's bet on a game that hasn't kicked off and gives the
  /// whole stake back, so they can bet again. Returns the coins refunded.
  @override
  Future<int> withdrawBet(String token, String gameId) async {
    final player = await _playerFor(token);
    final ledger = await _ledger();

    if (_games[gameId]?.status != GameStatus.upcoming) {
      throw const BetRejected('Bets can only be withdrawn before kickoff.');
    }

    final bet = ledger.bets[gameId]?[player];

    if (bet == null || bet.isSettled) {
      throw const BetRejected('You have no bet on this game to withdraw.');
    }

    ledger.bets[gameId]!.remove(player);
    ledger.balances[player] = ledger.balance(player) + bet.amount;

    await _save(ledger);

    return bet.amount;
  }

  /// Ids of games where the player's bet was settled since the last call.
  @override
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
    for (final (bot, bet) in fakeBetsFor(game, botCount: botCount)) {
      if (bet.amount <= ledger.balance(bot)) {
        _stake(ledger, bot, game.id, bet.side, bet.amount);
      }
    }
  }

  void _stake(
    _Ledger ledger,
    String player,
    String gameId,
    TeamSide side,
    int amount, {
    ScoreRange? scoreRange,
  }) {
    final balance = ledger.balance(player);

    if (amount <= 0 || amount > balance) {
      throw BetRejected('Bets must be 1 to $balance coins.');
    }

    final bets = ledger.bets.putIfAbsent(gameId, () => {});

    if (bets.containsKey(player)) {
      throw const BetRejected('You already bet on this game.');
    }

    bets[player] = Bet(
      side: side,
      amount: amount,
      multiplier: underdogMultiplier(_games[gameId]?.record(side)),
      scoreRange: scoreRange,
    );

    ledger.balances[player] = balance - amount;
  }

  static void _settle(_Ledger ledger, Game game) {
    final bets = ledger.bets[game.id];

    if (bets == null) {
      return;
    }

    final payouts = splitPool(
      bets,
      game.winner,
      winningScore: game.winningScore,
    );

    for (final MapEntry(key: player, value: bet) in bets.entries) {
      // Bonuses only apply to winning bets, not refunds, and are paid on top
      // of the pool rather than out of it.
      final payout = bet.wins(game.winner, game.winningScore)
          ? applyMultiplier(payouts[player]!, totalMultiplier(bet))
          : payouts[player]!;

      bets[player] = Bet(
        side: bet.side,
        amount: bet.amount,
        payout: payout,
        cashOutAmount: bet.cashOutAmount,
        multiplier: bet.multiplier,
        scoreRange: bet.scoreRange,
      );

      ledger.balances[player] = ledger.balance(player) + payout;

      if (!isBot(player)) {
        ledger.results.putIfAbsent(player, () => []).add(game.id);
        _notify(
          ledger,
          player,
          game.id,
          GameNotificationKind.result,
          _resultTitle(game),
          _resultStatus(game, bet, payout),
        );
      }
    }
  }

  Future<_Ledger> _ledger() async => _loaded ??= await _load();

  Future<_Ledger> _load() async {
    final raw = await _storage.read();

    if (raw == null) {
      return _Ledger();
    }

    return _Ledger.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> _save(_Ledger ledger) =>
      _storage.write(jsonEncode(ledger.toJson()));
}

/// Everything the server stores.
class _Ledger {
  _Ledger();

  factory _Ledger.fromJson(Map<String, dynamic> json) => _Ledger()
    ..balances.addAll(
      (json['balances'] as Map<String, dynamic>).cast<String, int>(),
    )
    ..dailyClaims.addAll(
      (json['dailyClaims'] as Map<String, dynamic>? ?? <String, dynamic>{}).map(
        (key, value) => MapEntry(key, value as String),
      ),
    )
    ..bailouts.addAll(
      (json['bailouts'] as Map<String, dynamic>? ?? {}).map(
        (key, value) => MapEntry(key, value as String),
      ),
    )
    ..ownedShopItems.addAll({
      for (final MapEntry(key: player, value: ids)
          in (json['ownedShopItems'] as Map<String, dynamic>? ?? {}).entries)
        player: (ids as List).cast<String>().toSet(),
    })
    ..activeShopThemes.addAll(
      (json['activeShopThemes'] as Map<String, dynamic>? ?? {}).map(
        (key, value) => MapEntry(key, value as String),
      ),
    )
    ..activeShopBackgrounds.addAll(
      (json['activeShopBackgrounds'] as Map<String, dynamic>? ?? {}).map(
        (key, value) => MapEntry(key, value as String),
      ),
    )
    ..bets.addAll({
      for (final MapEntry(key: gameId, value: bets)
          in (json['bets'] as Map<String, dynamic>).entries)
        gameId: {
          for (final MapEntry(key: player, value: bet)
              in (bets as Map<String, dynamic>).entries)
            player: Bet.fromJson(bet as Map<String, dynamic>),
        },
    })
    ..seeded.addAll((json['seeded'] as List).cast<String>())
    ..settled.addAll((json['settled'] as List).cast<String>())
    ..halftimeSent.addAll(
      (json['halftimeSent'] as List? ?? const []).cast<String>(),
    )
    ..notifications.addAll({
      for (final MapEntry(key: player, value: list)
          in (json['notifications'] as Map<String, dynamic>? ?? {}).entries)
        player: [
          for (final n in list as List)
            GameNotification.fromJson(n as Map<String, dynamic>),
        ],
    })
    ..nextNotificationId = json['nextNotificationId'] as int? ?? 0
    ..results.addAll({
      for (final MapEntry(:key, :value)
          in (json['results'] as Map<String, dynamic>).entries)
        key: (value as List).cast<String>(),
    });

  /// Coins per player. Players who haven't bet yet aren't listed.
  final balances = <String, int>{};

  /// Last daily reward claim per player.
  ///
  /// Dates are stored as YYYY-MM-DD in UTC.
  final dailyClaims = <String, String>{};

  /// Last bailout per player, as YYYY-MM-DD in UTC.
  final bailouts = <String, String>{};

  /// Purchased shop item ids, keyed by player id.
  final ownedShopItems = <String, Set<String>>{};

  /// Active shop theme id per player.
  final activeShopThemes = <String, String>{};

  /// Active shop background id per player. Players with none aren't listed.
  final activeShopBackgrounds = <String, String>{};

  /// Bets keyed by game id, then player id.
  final bets = <String, Map<String, Bet>>{};

  /// Games bots have already bet on.
  final seeded = <String>{};

  /// Games that have been paid out.
  final settled = <String>{};

  /// Per player, settled games they haven't been told about yet.
  final results = <String, List<String>>{};

  /// Games whose halftime notifications have been sent.
  final halftimeSent = <String>{};

  /// Notifications per player, oldest first.
  final notifications = <String, List<GameNotification>>{};

  /// Id for the next notification sent to anyone.
  var nextNotificationId = 0;

  int balance(String player) =>
      balances[player] ?? BettingServer.startingBalance;

  Map<String, Object?> toJson() => {
    'balances': balances,
    'dailyClaims': dailyClaims,
    'bailouts': bailouts,
    'ownedShopItems': {
      for (final entry in ownedShopItems.entries)
        entry.key: entry.value.toList(),
    },
    'activeShopThemes': activeShopThemes,
    'activeShopBackgrounds': activeShopBackgrounds,
    'bets': {
      for (final MapEntry(key: gameId, value: bets) in bets.entries)
        gameId: {for (final e in bets.entries) e.key: e.value.toJson()},
    },
    'seeded': seeded.toList(),
    'settled': settled.toList(),
    'results': results,
    'halftimeSent': halftimeSent.toList(),
    'notifications': {
      for (final MapEntry(key: player, value: list) in notifications.entries)
        player: [for (final n in list) n.toJson()],
    },
    'nextNotificationId': nextNotificationId,
  };
}
