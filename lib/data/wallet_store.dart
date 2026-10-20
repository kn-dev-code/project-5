import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/bet.dart';
import '../models/game.dart';
import 'fake_crowd.dart';

/// Saves the user's coin balance and bets on the device.
class WalletStore {
  static const startingBalance = 1000;
  static const _balanceKey = 'wallet_balance';
  static const _betsKey = 'wallet_bets';

  Future<int> loadBalance() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_balanceKey) ?? startingBalance;
  }

  /// Bets keyed by game id.
  Future<Map<String, Bet>> loadBets() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_betsKey);
    if (raw == null) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return {
      for (final MapEntry(:key, :value) in decoded.entries)
        key: Bet.fromJson(value as Map<String, dynamic>),
    };
  }

  /// Takes [amount] coins from the balance and stakes them on [side].
  /// Only one bet is allowed per game.
  Future<void> placeBet(String gameId, TeamSide side, int amount) async {
    final balance = await loadBalance();
    final bets = await loadBets();
    if (amount <= 0 || amount > balance) {
      throw ArgumentError.value(amount, 'amount', 'must be 1 to $balance');
    }
    if (bets.containsKey(gameId)) {
      throw StateError('A bet was already placed on game $gameId');
    }
    bets[gameId] = Bet(side: side, amount: amount);
    await _save(balance - amount, bets);
  }

  /// Pays out the bet on [game] if it has finished and hasn't been settled.
  /// Returns the settled bet, or null if there was nothing to settle.
  Future<Bet?> settle(Game game) async {
    if (!game.isFinished) return null;
    final bets = await loadBets();
    final bet = bets[game.id];
    if (bet == null || bet.isSettled) return null;

    final settled = Bet(
      side: bet.side,
      amount: bet.amount,
      payout: payoutFor(game, bet),
    );
    bets[game.id] = settled;
    await _save(await loadBalance() + settled.payout!, bets);
    return settled;
  }

  /// Winners split the pool; a tie refunds the stake.
  static int payoutFor(Game game, Bet bet) {
    final winner = game.winner;
    if (winner == null) return bet.amount;
    if (winner != bet.side) return 0;
    return fakeCrowdFor(game)
        .withUser(bet: bet)
        .winningPayout(bet.side, bet.amount);
  }

  Future<void> _save(int balance, Map<String, Bet> bets) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_balanceKey, balance);
    await prefs.setString(
      _betsKey,
      jsonEncode({for (final e in bets.entries) e.key: e.value.toJson()}),
    );
  }
}
