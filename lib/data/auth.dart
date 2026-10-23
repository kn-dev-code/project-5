import 'package:football_core/api/betting_api.dart';
import 'package:football_core/models/account.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend.dart';

/// A logged-in player. [token] goes with every request to the servers.
class Session {
  const Session({required this.token, required this.account});

  final String token;
  final Account account;
}

/// Logs the player in and out, and remembers their session on the device so
/// they stay logged in between app launches. Server errors come through as
/// [AuthException].
class Auth {
  Auth({AccountApi? server}) : _server = server ?? accounts;

  static const _tokenKey = 'session_token';

  final AccountApi _server;

  /// The session saved on this device, or null if there isn't a valid one.
  Future<Session?> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    if (token == null) return null;
    try {
      return await _start(token);
    } on AuthException {
      await prefs.remove(_tokenKey);
      return null;
    }
  }

  Future<Session> logIn(String username, String password) async =>
      _start(await _server.logIn(username, password));

  Future<Session> createAccount(String username, String password) async =>
      _start(await _server.createAccount(username, password));

  Future<void> logOut(Session session) async {
    await _server.logOut(session.token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  Future<Session> _start(String token) async {
    final account = await _server.accountFor(token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    return Session(token: token, account: account);
  }
}
