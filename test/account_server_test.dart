import 'package:flutter_test/flutter_test.dart';
import 'package:football_core/server/account_server.dart';
import 'package:football_core/server/password_hash.dart';
import 'package:football_core/server/server_storage.dart';

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  test('PBKDF2 matches the published SHA-256 test vectors', () {
    final salt = 'salt'.codeUnits;
    expect(
      _hex(pbkdf2Sha256('password', salt, 1)),
      '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
    );
    expect(
      _hex(pbkdf2Sha256('password', salt, 2)),
      'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
    );
  });

  group('AccountServer', () {
    late MemoryStorage storage;
    late AccountServer server;
    setUp(() {
      storage = MemoryStorage();
      server = AccountServer(storage: storage, hashIterations: 1);
    });

    test('creates accounts and logs in with the right password', () async {
      final token = await server.createAccount('  Alice_1 ', 'hunter22');
      expect((await server.accountFor(token)).username, 'Alice_1');

      final again = await server.logIn('alice_1', 'hunter22');
      expect(again, isNot(token));
      expect(
        (await server.accountFor(again)).id,
        (await server.accountFor(token)).id,
      );
      expect(
        server.logIn('alice_1', 'hunter23'),
        throwsA(isA<AuthException>()),
      );
      expect(server.logIn('nobody', 'hunter22'), throwsA(isA<AuthException>()));
    });

    test('enforces username and password rules', () async {
      for (final (username, password) in [
        ('ab', 'longenough'),
        ('has space', 'longenough'),
        ('fine_name', 'short'),
      ]) {
        expect(
          server.createAccount(username, password),
          throwsA(isA<AuthException>()),
        );
      }
      await server.createAccount('Taken', 'longenough');
      expect(
        server.createAccount('taken', 'longenough'),
        throwsA(isA<AuthException>()),
      );
    });

    test('never stores passwords or session tokens', () async {
      final token = await server.createAccount('alice', 'hunter22');
      expect(storage.data, isNot(contains('hunter22')));
      expect(storage.data, isNot(contains(token)));

      // A fresh server reading the same data still knows the account.
      final restarted = AccountServer(storage: storage, hashIterations: 1);
      expect((await restarted.accountFor(token)).username, 'alice');
      await restarted.logIn('alice', 'hunter22');
    });

    test('ends sessions on log out and when they expire', () async {
      var now = DateTime(2026, 1, 1);
      server = AccountServer(
        storage: storage,
        hashIterations: 1,
        sessionLength: const Duration(days: 1),
        clock: () => now,
      );
      final first = await server.createAccount('alice', 'hunter22');
      final second = await server.logIn('alice', 'hunter22');

      await server.logOut(first);
      expect(server.accountFor(first), throwsA(isA<AuthException>()));
      expect((await server.accountFor(second)).username, 'alice');

      now = now.add(const Duration(days: 1));
      expect(server.accountFor(second), throwsA(isA<AuthException>()));
    });
  });
}
