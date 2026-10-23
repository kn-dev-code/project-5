import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../models/account.dart';
import '../api/betting_api.dart';
import 'password_hash.dart';
import 'server_storage.dart';

/// Thrown when an account can't be created or a session isn't valid.
/// [message] is safe to show to the user.
class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The accounts backend. It creates accounts, checks passwords
/// and hands out session tokens that the app sends with every other request.
///
/// Passwords are only stored as salted PBKDF2 hashes, and session tokens only
/// as SHA-256 hashes, so a copy of the stored data can't be used to sign in.
///
/// It doesn't use Flutter. The football_server package serves it over HTTP,
/// and the app runs it in-process for tests and offline play.
class AccountServer implements AccountApi {
  AccountServer({
    required this._storage,
    this.hashIterations = 100000,
    this.sessionLength = const Duration(days: 30),
    DateTime Function()? clock,
    Random? random,
  }) : _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  static const minPasswordLength = 8;
  static final _usernamePattern = RegExp(r'^[A-Za-z0-9_]{3,20}$');

  /// PBKDF2 rounds for new passwords. Each account stores its own count, so
  /// raising this later doesn't break existing passwords.
  final int hashIterations;

  /// How long a session stays valid after logging in.
  final Duration sessionLength;

  final ServerStorage _storage;
  final DateTime Function() _clock;
  final Random _random;

  // Loaded once and then changed in memory between awaits, so overlapping
  // calls can't overwrite each other's changes.
  _AccountDb? _loaded;

  /// Creates an account and logs it in, returning the session token.
  @override
  Future<String> createAccount(String username, String password) async {
    username = username.trim();
    if (!_usernamePattern.hasMatch(username)) {
      throw const AuthException(
        'Usernames must be 3 to 20 letters, numbers or underscores.',
      );
    }
    if (password.length < minPasswordLength) {
      throw const AuthException(
        'Passwords must be at least $minPasswordLength characters.',
      );
    }
    final db = await _db();
    if (db.byUsername(username) != null) {
      throw const AuthException('That username is taken.');
    }

    final salt = _randomBytes(16);
    final account = _StoredAccount(
      id: _hex(_randomBytes(16)),
      username: username,
      salt: salt,
      hash: pbkdf2Sha256(password, salt, hashIterations),
      iterations: hashIterations,
    );
    db.accounts[account.id] = account;
    final token = _startSession(db, account);
    await _save(db);
    return token;
  }

  /// Checks [username] and [password] and returns a new session token.
  @override
  Future<String> logIn(String username, String password) async {
    final db = await _db();
    final account = db.byUsername(username.trim());
    // Hash even for unknown usernames so the response time doesn't reveal
    // which usernames exist.
    final hash = pbkdf2Sha256(
      password,
      account?.salt ?? const [0],
      account?.iterations ?? hashIterations,
    );
    if (account == null || !constantTimeEquals(hash, account.hash)) {
      throw const AuthException('Wrong username or password.');
    }
    final token = _startSession(db, account);
    await _save(db);
    return token;
  }

  /// Ends the session for [token]. Does nothing if it already ended.
  @override
  Future<void> logOut(String token) async {
    final db = await _db();
    if (db.sessions.remove(_hashToken(token)) != null) await _save(db);
  }

  /// The account [token] belongs to. Throws [AuthException] if the session
  /// has ended or never existed.
  @override
  Future<Account> accountFor(String token) async {
    final db = await _db();
    final key = _hashToken(token);
    final session = db.sessions[key];
    final account = db.accounts[session?.accountId];
    if (session == null || account == null) {
      throw const AuthException('Please log in again.');
    }
    if (!_clock().isBefore(session.expires)) {
      db.sessions.remove(key);
      await _save(db);
      throw const AuthException('Your session expired. Please log in again.');
    }
    return Account(id: account.id, username: account.username);
  }

  String _startSession(_AccountDb db, _StoredAccount account) {
    final token = _hex(_randomBytes(32));
    db.sessions[_hashToken(token)] = (
      accountId: account.id,
      expires: _clock().add(sessionLength),
    );
    return token;
  }

  List<int> _randomBytes(int length) =>
      List.generate(length, (_) => _random.nextInt(256));

  static String _hashToken(String token) =>
      sha256.convert(utf8.encode(token)).toString();

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  Future<_AccountDb> _db() async => _loaded ??= await _load();

  Future<_AccountDb> _load() async {
    final raw = await _storage.read();
    if (raw == null) return _AccountDb();
    return _AccountDb.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> _save(_AccountDb db) => _storage.write(jsonEncode(db.toJson()));
}

class _StoredAccount {
  const _StoredAccount({
    required this.id,
    required this.username,
    required this.salt,
    required this.hash,
    required this.iterations,
  });

  factory _StoredAccount.fromJson(Map<String, dynamic> json) => _StoredAccount(
    id: json['id'] as String,
    username: json['username'] as String,
    salt: base64Decode(json['salt'] as String),
    hash: base64Decode(json['hash'] as String),
    iterations: json['iterations'] as int,
  );

  final String id;
  final String username;
  final List<int> salt;
  final List<int> hash;
  final int iterations;

  Map<String, Object?> toJson() => {
    'id': id,
    'username': username,
    'salt': base64Encode(salt),
    'hash': base64Encode(hash),
    'iterations': iterations,
  };
}

/// Everything the account server stores.
class _AccountDb {
  _AccountDb();

  factory _AccountDb.fromJson(Map<String, dynamic> json) => _AccountDb()
    ..accounts.addAll({
      for (final account in (json['accounts'] as List).map(
        (value) => _StoredAccount.fromJson(value as Map<String, dynamic>),
      ))
        account.id: account,
    })
    ..sessions.addAll({
      for (final MapEntry(:key, :value)
          in (json['sessions'] as Map<String, dynamic>).entries)
        key: (
          accountId: value['accountId'] as String,
          expires: DateTime.parse(value['expires'] as String),
        ),
    });

  /// Accounts keyed by id.
  final accounts = <String, _StoredAccount>{};

  /// Sessions keyed by the SHA-256 hash of their token.
  final sessions = <String, ({String accountId, DateTime expires})>{};

  /// Usernames are unique regardless of case.
  _StoredAccount? byUsername(String username) {
    final lower = username.toLowerCase();
    for (final account in accounts.values) {
      if (account.username.toLowerCase() == lower) return account;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'accounts': [for (final a in accounts.values) a.toJson()],
    'sessions': {
      for (final MapEntry(:key, :value) in sessions.entries)
        key: {
          'accountId': value.accountId,
          'expires': value.expires.toUtc().toIso8601String(),
        },
    },
  };
}
