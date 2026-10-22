import 'dart:math';

import '../models/bet.dart';
import '../models/game.dart';

// TODO: drop these once real users are voting and betting. They're made up,
// but stay the same for a given game.

/// Vote counts from other users.
({int home, int away}) fakeVotesFor(Game game) {
  final random = Random(_seed(game));
  final totalVotes = 200 + random.nextInt(800);
  final homeShare = 0.25 + random.nextDouble() * 0.5;
  final home = (totalVotes * homeShare).round();
  return (home: home, away: totalVotes - home);
}

/// Bets from bot players so every game has a pool to win. About one voter in
/// ten bets, each staking 10 to 100 coins. Bots are named `bot-0` up to
/// `bot-${botCount - 1}` and bet on many games, so their balances carry over.
List<(String, Bet)> fakeBetsFor(Game game, {required int botCount}) {
  final random = Random(_seed(game) + 1);
  final votes = fakeVotesFor(game);
  final bots = List.generate(botCount, (i) => 'bot-$i')..shuffle(random);
  var next = 0;
  return [
    for (final side in TeamSide.values)
      for (
        var i = 0;
        i < (side == TeamSide.home ? votes.home : votes.away) ~/ 10 &&
            next < bots.length;
        i++
      )
        (bots[next++], Bet(side: side, amount: 10 + random.nextInt(91))),
  ];
}

bool isBot(String player) => player.startsWith('bot-');

int _seed(Game game) =>
    game.id.codeUnits.fold(17, (h, c) => (h * 31 + c) & 0x7fffffff);
