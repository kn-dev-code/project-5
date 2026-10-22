import 'dart:convert';

import 'package:crypto/crypto.dart';

/// PBKDF2 with HMAC-SHA256, producing a 32-byte key.
List<int> pbkdf2Sha256(String password, List<int> salt, int iterations) {
  final hmac = Hmac(sha256, utf8.encode(password));
  var block = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
  final key = List.of(block);
  for (var i = 1; i < iterations; i++) {
    block = hmac.convert(block).bytes;
    for (var j = 0; j < key.length; j++) {
      key[j] ^= block[j];
    }
  }
  return key;
}

/// Compares in time that doesn't depend on where the lists differ, so
/// response times don't leak how much of a hash matched.
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
