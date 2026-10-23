import '../models/account.dart';
import '../models/bet.dart';
import '../models/crowd_stats.dart';
import '../models/game.dart';
import '../models/game_notification.dart';

export '../server/account_server.dart' show AuthException;
export '../server/betting_server.dart' show BetRejected, ShopRejected;

/// What the app can ask the accounts service. `AccountServer` answers in the
/// same process; `HttpAccountApi` forwards to the real server.
///
/// Failures the player should see come through as `AuthException`.
abstract interface class AccountApi {
  /// Creates an account and logs it in, returning the session token.
  Future<String> createAccount(String username, String password);

  /// Returns a new session token.
  Future<String> logIn(String username, String password);

  Future<void> logOut(String token);

  /// The account a session token belongs to.
  Future<Account> accountFor(String token);
}

/// What the app can ask the betting service. `BettingServer` answers in the
/// same process; `HttpBettingApi` forwards to the real server.
///
/// Every call that takes a token throws `AuthException` if it isn't valid.
/// Refused bets and purchases come through as `BetRejected` and
/// `ShopRejected`.
abstract interface class BettingApi {
  /// The latest games, live, upcoming and recently finished.
  Future<List<Game>> fetchGames();

  Future<int> balance(String token);

  Future<Set<String>> ownedShopItems(String token);

  Future<String> activeShopTheme(String token);

  Future<void> setActiveShopTheme(String token, String themeId);

  Future<String?> activeShopBackground(String token);

  Future<void> setActiveShopBackground(String token, String? backgroundId);

  /// Returns the balance after paying.
  Future<int> purchaseShopItem(String token, String itemId);

  Future<bool> canClaimDailyReward(String token);

  /// Returns the balance after the reward.
  Future<int> claimDailyReward(String token);

  /// Returns the coins given, or 0 if the player didn't get a bailout.
  Future<int> claimBailoutIfBroke(String token);

  /// Newest first.
  Future<List<GameNotification>> notifications(String token);

  Future<void> markNotificationsRead(String token);

  /// The player's bets keyed by game id.
  Future<Map<String, Bet>> bets(String token);

  /// Votes and coins bet on [game], leaving out the player [token] belongs
  /// to, if given.
  Future<CrowdStats> crowd(Game game, {String? token});

  Future<void> placeBet(
    String token,
    String gameId,
    TeamSide side,
    int amount, {
    ScoreRange? scoreRange,
  });

  /// Returns the coins given back.
  Future<int> cashOutHalf(String token, String gameId);

  /// Ids of games where the player's bet was settled since the last call.
  Future<List<String>> takeResults(String token);
}
