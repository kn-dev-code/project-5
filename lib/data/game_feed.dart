import 'dart:math';

import '../models/game.dart';
import 'fake_games.dart';

/// Source of the latest game scores and statuses.
abstract class GameFeed {
  Future<List<Game>> fetchGames();

  /// Looks up games that [fetchGames] may no longer list, such as games that
  /// ended a while ago. Ids the feed doesn't know are left out.
  Future<List<Game>> fetchGamesById(Iterable<String> ids);
}

/// Shared feed used by the app so game progress survives leaving the screen.
// TODO: swap for a real live-scores feed.
final GameFeed gameFeed = FakeGameFeed();

/// Simulates a never-ending schedule of games: one kicks off every
/// [fakeKickoffInterval] and expires [fakeGameLength] later with a winner.
///
/// Each game's teams, score and clock depend only on its kickoff slot and the
/// current time, so a game looks the same after the app restarts and keeps
/// playing while the app is closed. Ties at the end are broken with a field
/// goal so every bet wins or loses.
class FakeGameFeed implements GameFeed {
  FakeGameFeed({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  static const _idPrefix = 'fake-';
  static const _gameSeconds = 4 * _quarterSeconds;
  static const _quarterSeconds = 15 * 60;
  static const _secondsPerDrive = 3 * 60;

  final DateTime Function() _clock;

  @override
  Future<List<Game>> fetchGames() async {
    final now = _clock();
    final interval = fakeKickoffInterval.inMilliseconds;
    final oldest = now.subtract(fakeGameLength + fakeFinishedWindow);
    final newest = now.add(fakeUpcomingWindow);
    final first = (oldest.millisecondsSinceEpoch / interval).ceil();
    final last = newest.millisecondsSinceEpoch ~/ interval;
    return List.unmodifiable([
      for (var slot = first; slot <= last; slot++) _game(slot, now),
    ]);
  }

  @override
  Future<List<Game>> fetchGamesById(Iterable<String> ids) async {
    final now = _clock();
    return [
      for (final id in ids)
        if (id.startsWith(_idPrefix))
          if (int.tryParse(id.substring(_idPrefix.length)) case final slot?)
            _game(slot, now),
    ];
  }

  Game _game(int slot, DateTime now) {
    final teams = Random(slot);
    final league = fakeTeams.keys.elementAt(teams.nextInt(fakeTeams.length));
    final names = List.of(fakeTeams[league]!)..shuffle(teams);

    final kickoff = DateTime.fromMillisecondsSinceEpoch(
      slot * fakeKickoffInterval.inMilliseconds,
    );
    final endsAt = kickoff.add(fakeGameLength);
    Game game(
      GameStatus status, {
      int home = 0,
      int away = 0,
      int? quarter,
      String? clock,
    }) => Game(
      id: '$_idPrefix$slot',
      league: league,
      homeTeam: names[0],
      awayTeam: names[1],
      status: status,
      homeScore: home,
      awayScore: away,
      quarter: quarter,
      clock: clock,
      kickoff: kickoff,
      endsAt: endsAt,
    );

    final elapsed = now.difference(kickoff);
    if (elapsed.isNegative) return game(GameStatus.upcoming);

    // Real time is scaled so the whole game fits in [fakeGameLength].
    final played = min(
      _gameSeconds,
      elapsed.inMilliseconds * _gameSeconds ~/ fakeGameLength.inMilliseconds,
    );
    var home = 0;
    var away = 0;
    for (var drive = 0; drive < played ~/ _secondsPerDrive; drive++) {
      final scoring = Random(slot * 64 + drive);
      home += _score(scoring);
      away += _score(scoring);
    }

    if (played < _gameSeconds) {
      final left = _quarterSeconds - played % _quarterSeconds;
      return game(
        GameStatus.live,
        home: home,
        away: away,
        quarter: played ~/ _quarterSeconds + 1,
        clock: '${left ~/ 60}:${(left % 60).toString().padLeft(2, '0')}',
      );
    }
    if (home == away) {
      if (Random(slot * 64 + 63).nextBool()) {
        home += 3;
      } else {
        away += 3;
      }
    }
    return game(GameStatus.finished, home: home, away: away);
  }

  static int _score(Random random) {
    final roll = random.nextInt(100);
    if (roll < 15) return 7;
    if (roll < 25) return 3;
    return 0;
  }
}
