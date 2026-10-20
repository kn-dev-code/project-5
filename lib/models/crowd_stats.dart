import 'bet.dart';
import 'game.dart';

/// How every user has voted and bet on one game.
class CrowdStats {
  const CrowdStats({
    required this.homeVotes,
    required this.awayVotes,
    required this.homePool,
    required this.awayPool,
  });

  final int homeVotes;
  final int awayVotes;

  /// Total coins bet on each side.
  final int homePool;
  final int awayPool;

  int votes(TeamSide side) => side == TeamSide.home ? homeVotes : awayVotes;

  int pool(TeamSide side) => side == TeamSide.home ? homePool : awayPool;

  int get totalVotes => homeVotes + awayVotes;

  int get totalPool => homePool + awayPool;

  /// Whole-number vote percentage for [side]; both sides add up to 100.
  int votePercent(TeamSide side) {
    final home = totalVotes == 0 ? 50 : (homeVotes * 100 / totalVotes).round();
    return side == TeamSide.home ? home : 100 - home;
  }

  /// Adds the current user's vote and stake to these totals.
  CrowdStats withUser({TeamSide? pick, Bet? bet}) {
    int stakeOn(TeamSide side) => bet?.side == side ? bet!.amount : 0;
    return CrowdStats(
      homeVotes: homeVotes + (pick == TeamSide.home ? 1 : 0),
      awayVotes: awayVotes + (pick == TeamSide.away ? 1 : 0),
      homePool: homePool + stakeOn(TeamSide.home),
      awayPool: awayPool + stakeOn(TeamSide.away),
    );
  }

  /// Coins returned, stake included, for [amount] bet on [side] if that side
  /// wins. Winners split the whole pool in proportion to their stakes, so the
  /// stake must already be counted in [pool].
  int winningPayout(TeamSide side, int amount) {
    final sidePool = pool(side);
    if (sidePool == 0) return amount;
    return amount * totalPool ~/ sidePool;
  }
}
