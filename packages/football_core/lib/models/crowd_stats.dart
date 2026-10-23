import 'bet.dart';
import 'game.dart';

/// Odds as coins back per coin staked, e.g. '2.40x'.
String formatOdds(double odds) => '${odds.toStringAsFixed(2)}x';

/// How every user has voted and bet on one game.
class CrowdStats {
  const CrowdStats({
    required this.homeVotes,
    required this.awayVotes,
    required this.homePool,
    required this.awayPool,
    this.homeBettors = 0,
    this.awayBettors = 0,
  });

  factory CrowdStats.fromJson(Map<String, dynamic> json) => CrowdStats(
    homeVotes: json['homeVotes'] as int,
    awayVotes: json['awayVotes'] as int,
    homePool: json['homePool'] as int,
    awayPool: json['awayPool'] as int,
    homeBettors: json['homeBettors'] as int? ?? 0,
    awayBettors: json['awayBettors'] as int? ?? 0,
  );

  final int homeVotes;
  final int awayVotes;

  /// Total coins bet on each side.
  final int homePool;
  final int awayPool;

  /// How many players have bet on each side.
  final int homeBettors;
  final int awayBettors;

  Map<String, Object?> toJson() => {
    'homeVotes': homeVotes,
    'awayVotes': awayVotes,
    'homePool': homePool,
    'awayPool': awayPool,
    'homeBettors': homeBettors,
    'awayBettors': awayBettors,
  };

  int votes(TeamSide side) => side == TeamSide.home ? homeVotes : awayVotes;

  int pool(TeamSide side) => side == TeamSide.home ? homePool : awayPool;

  int bettors(TeamSide side) =>
      side == TeamSide.home ? homeBettors : awayBettors;

  int get totalVotes => homeVotes + awayVotes;

  int get totalPool => homePool + awayPool;

  int get totalBettors => homeBettors + awayBettors;

  /// Whole-number vote percentage for [side]; both sides add up to 100.
  int votePercent(TeamSide side) {
    final home = totalVotes == 0 ? 50 : (homeVotes * 100 / totalVotes).round();
    return side == TeamSide.home ? home : 100 - home;
  }

  /// Coins a winning bet on [side] returns per coin staked, before any
  /// underdog bonus, if the pools stay as they are. Null when nobody has bet
  /// on [side] yet.
  double? odds(TeamSide side) {
    final sidePool = pool(side);
    if (sidePool == 0) return null;
    return totalPool / sidePool;
  }

  /// Adds the current user's vote and stake to these totals.
  CrowdStats withUser({TeamSide? pick, Bet? bet}) {
    int stakeOn(TeamSide side) => bet?.side == side ? bet!.amount : 0;
    int bettorOn(TeamSide side) => bet?.side == side ? 1 : 0;
    return CrowdStats(
      homeVotes: homeVotes + (pick == TeamSide.home ? 1 : 0),
      awayVotes: awayVotes + (pick == TeamSide.away ? 1 : 0),
      homePool: homePool + stakeOn(TeamSide.home),
      awayPool: awayPool + stakeOn(TeamSide.away),
      homeBettors: homeBettors + bettorOn(TeamSide.home),
      awayBettors: awayBettors + bettorOn(TeamSide.away),
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
