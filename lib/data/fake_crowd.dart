import 'dart:math';

import '../models/crowd_stats.dart';
import '../models/game.dart';

// TODO: replace with real vote and bet totals from other users once there is
// a backend. These are made up, but stay the same for a given game.
CrowdStats fakeCrowdFor(Game game) {
  final seed = game.id.codeUnits.fold(17, (h, c) => (h * 31 + c) & 0x7fffffff);
  final random = Random(seed);
  final totalVotes = 200 + random.nextInt(800);
  final homeShare = 0.25 + random.nextDouble() * 0.5;
  final homeVotes = (totalVotes * homeShare).round();
  final awayVotes = totalVotes - homeVotes;
  return CrowdStats(
    homeVotes: homeVotes,
    awayVotes: awayVotes,
    homePool: homeVotes * (20 + random.nextInt(30)),
    awayPool: awayVotes * (20 + random.nextInt(30)),
  );
}
