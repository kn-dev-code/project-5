import 'dart:math';

import '../models/game.dart';
import 'fake_games.dart';

/// Source of the latest game scores and statuses.
abstract class GameFeed {
  Future<List<Game>> fetchGames();
}

/// Shared feed used by the app so game progress survives leaving the screen.
// TODO: swap for a real live-scores feed.
final GameFeed gameFeed = FakeGameFeed();

/// Simulates games progressing: every fetch after the first moves each live
/// game forward a few minutes, adds random scores, and ends games whose time
/// runs out.
class FakeGameFeed implements GameFeed {
  FakeGameFeed({List<Game>? games, Random? random})
    : _games = List.of(games ?? fakeGames),
      _random = random ?? Random();

  static const _secondsPerTick = 3 * 60;
  static const _quarterSeconds = 15 * 60;
  static const _overtimeSeconds = 10 * 60;

  final List<Game> _games;
  final Random _random;
  bool _started = false;

  @override
  Future<List<Game>> fetchGames() async {
    if (_started) {
      for (var i = 0; i < _games.length; i++) {
        _games[i] = _advance(_games[i]);
      }
    }
    _started = true;
    return List.unmodifiable(_games);
  }

  Game _advance(Game game) => switch (game.status) {
    GameStatus.upcoming => _maybeKickOff(game),
    GameStatus.live => _play(game),
    GameStatus.finished => game,
  };

  Game _maybeKickOff(Game game) {
    final kickoff = game.kickoff;
    if (kickoff != null && DateTime.now().isBefore(kickoff)) return game;
    return _copy(
      game,
      status: GameStatus.live,
      quarter: 1,
      seconds: _quarterSeconds,
    );
  }

  Game _play(Game game) {
    var quarter = game.quarter ?? 1;
    var seconds = _parseClock(game.clock) - _secondsPerTick;
    final home = game.homeScore + _randomScore();
    final away = game.awayScore + _randomScore();
    final tied = home == away;

    // Overtime is sudden death: any score ends it.
    final overtimeDecided = quarter > 4 && !tied;
    if (overtimeDecided ||
        (seconds <= 0 && (quarter > 4 || (quarter == 4 && !tied)))) {
      return _copy(
        game,
        status: GameStatus.finished,
        homeScore: home,
        awayScore: away,
      );
    }
    if (seconds <= 0) {
      quarter++;
      seconds = quarter > 4 ? _overtimeSeconds : _quarterSeconds;
    }
    return _copy(
      game,
      status: GameStatus.live,
      homeScore: home,
      awayScore: away,
      quarter: quarter,
      seconds: seconds,
    );
  }

  int _randomScore() {
    final roll = _random.nextInt(100);
    if (roll < 15) return 7;
    if (roll < 25) return 3;
    return 0;
  }

  static Game _copy(
    Game game, {
    required GameStatus status,
    int? homeScore,
    int? awayScore,
    int? quarter,
    int? seconds,
  }) {
    return Game(
      id: game.id,
      league: game.league,
      homeTeam: game.homeTeam,
      awayTeam: game.awayTeam,
      status: status,
      homeScore: homeScore ?? game.homeScore,
      awayScore: awayScore ?? game.awayScore,
      quarter: status == GameStatus.live ? quarter : null,
      clock: status == GameStatus.live && seconds != null
          ? _formatClock(seconds)
          : null,
      kickoff: status == GameStatus.upcoming ? game.kickoff : null,
    );
  }

  static int _parseClock(String? clock) {
    final parts = clock?.split(':');
    if (parts == null || parts.length != 2) return 0;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }

  static String _formatClock(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}
