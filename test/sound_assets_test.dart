import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:footballapp/data/sound_effects.dart';

void main() {
  test('every sound has a file in assets/sounds', () {
    for (final sound in Sound.values) {
      expect(
        File('assets/sounds/${sound.name}.wav').existsSync(),
        isTrue,
        reason: 'Run tool/generate_sounds.py to make ${sound.name}.wav',
      );
    }
  });
}
