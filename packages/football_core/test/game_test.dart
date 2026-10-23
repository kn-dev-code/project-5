import 'package:football_core/models/game.dart';
import 'package:test/test.dart';

Game _game(GameStatus status, {int? quarter, String? clock}) => Game(
  id: 'x1',
  league: 'NFL',
  homeTeam: 'Home',
  awayTeam: 'Away',
  status: status,
  quarter: quarter,
  clock: clock,
);

void main() {
  test('bets are taken before kickoff and through the first quarter', () {
    expect(_game(GameStatus.upcoming).isBettingOpen, isTrue);
    expect(
      _game(GameStatus.live, quarter: 1, clock: '15:00').isBettingOpen,
      isTrue,
    );
    expect(
      _game(GameStatus.live, quarter: 1, clock: '0:01').isBettingOpen,
      isTrue,
    );
    // A feed without a clock keeps the whole first quarter open.
    expect(_game(GameStatus.live, quarter: 1).isBettingOpen, isTrue);
  });

  test('bets close once the first quarter ends', () {
    expect(
      _game(GameStatus.live, quarter: 1, clock: '0:00').isBettingOpen,
      isFalse,
    );
    expect(
      _game(GameStatus.live, quarter: 2, clock: '15:00').isBettingOpen,
      isFalse,
    );
    expect(
      _game(GameStatus.live, quarter: 5, clock: '10:00').isBettingOpen,
      isFalse,
    );
    expect(_game(GameStatus.finished).isBettingOpen, isFalse);
    // Live, but the feed doesn't say which quarter: don't take the risk.
    expect(_game(GameStatus.live).isBettingOpen, isFalse);
  });

  test('halftime checks still read the clock', () {
    expect(
      _game(GameStatus.live, quarter: 2, clock: '0:30').isBeforeHalftime,
      isTrue,
    );
    expect(
      _game(GameStatus.live, quarter: 2, clock: '0:00').isBeforeHalftime,
      isFalse,
    );
    expect(
      _game(GameStatus.live, quarter: 2, clock: '0:00').isHalftimeOrLater,
      isTrue,
    );
  });
}
