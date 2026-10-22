import '../models/bet.dart';
import '../models/game.dart';
import '../models/team_record.dart';

/// Highest bonus, for backing a team that hasn't won a game.
const maxUnderdogMultiplier = 2.0;

/// Bonus on a winning payout for backing a team with [record].
///
/// Teams at .500 or better get no bonus (1.0x). Below that the bonus grows
/// in a straight line to [maxUnderdogMultiplier] for a winless team, rounded
/// to one decimal place. Teams without a record get no bonus.
double underdogMultiplier(TeamRecord? record) {
  final winRate = record?.winRate;
  if (winRate == null || winRate >= 0.5) return 1.0;
  final raw = 1 + (0.5 - winRate) * 2 * (maxUnderdogMultiplier - 1);
  return (raw * 10).round() / 10;
}

/// [payout] with [multiplier] applied, rounded to whole coins.
int applyMultiplier(int payout, double multiplier) =>
    (payout * multiplier).round();

/// Splits the coins bet on a finished game between the players who backed
/// [winner].
///
/// Each winner gets their own stake back plus a share of the losing side's
/// coins in proportion to how much they staked, so together the winners take
/// the whole pool. Coins left over from rounding go one each to the winners
/// who were rounded down the most. If the game was a tie ([winner] is null)
/// or nobody backed the winner, every stake is refunded.
///
/// Returns the payout for every player in [bets], keyed the same way; losers
/// get 0.
Map<String, int> splitPool(Map<String, Bet> bets, TeamSide? winner) {
  int sum(Iterable<Bet> bets) => bets.fold(0, (total, b) => total + b.amount);

  final winningPool = sum(bets.values.where((b) => b.side == winner));
  if (winningPool == 0) {
    return {for (final e in bets.entries) e.key: e.value.amount};
  }
  final totalPool = sum(bets.values);

  final payouts = <String, int>{};
  final remainders = <String, int>{};
  for (final MapEntry(key: player, value: bet) in bets.entries) {
    if (bet.side != winner) {
      payouts[player] = 0;
      continue;
    }
    final share = bet.amount * totalPool;
    payouts[player] = share ~/ winningPool;
    remainders[player] = share % winningPool;
  }

  final paid = payouts.values.fold(0, (total, p) => total + p);
  final roundedDown = remainders.keys.toList()
    ..sort((a, b) {
      final byRemainder = remainders[b]!.compareTo(remainders[a]!);
      return byRemainder != 0 ? byRemainder : a.compareTo(b);
    });
  for (final player in roundedDown.take(totalPool - paid)) {
    payouts[player] = payouts[player]! + 1;
  }
  return payouts;
}
