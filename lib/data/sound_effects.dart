import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app's sound effects, one file each in assets/sounds/.
enum Sound {
  /// Buttons and taps on cards.
  tap,

  /// Choosing an option, like a team or a switch.
  select,

  /// A bet went through.
  bet,

  /// Coins coming in: winnings, rewards, cash-outs.
  coins,

  /// Something was refused or failed.
  error,

  /// A new notification.
  notify,

  /// The team the player backed scored.
  fanfare,

  /// The other team scored, or a bet was lost.
  lose,

  /// Something was bought in the shop.
  purchase,

  /// The app opening.
  startup,
}

/// Plays a [Sound]. Swapped out in tests, which have no audio.
abstract interface class SoundPlayer {
  Future<void> play(Sound sound);
}

/// Plays sounds with the audioplayers package, alongside any music or audio
/// from other apps rather than pausing it.
class AudioplayersSoundPlayer implements SoundPlayer {
  final _players = <Sound, AudioPlayer>{};
  Future<void>? _setUp;

  @override
  Future<void> play(Sound sound) async {
    await (_setUp ??= _configure());
    final player = _players[sound] ??= AudioPlayer();
    await player.stop();
    await player.play(
      AssetSource('sounds/${sound.name}.wav'),
      // Android's low-latency mode suits short effects; other platforms
      // don't support it.
      mode: !kIsWeb && defaultTargetPlatform == TargetPlatform.android
          ? PlayerMode.lowLatency
          : PlayerMode.mediaPlayer,
    );
  }

  Future<void> _configure() async {
    try {
      await AudioPlayer.global.setAudioContext(
        AudioContext(
          // Game sounds on Android follow the media volume and don't take
          // audio focus, so music from other apps keeps playing.
          android: const AudioContextAndroid(
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.game,
            audioFocus: AndroidAudioFocus.none,
          ),
          // Ambient mixes with other apps' audio and stays quiet when the
          // iPhone's silent switch is on.
          iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
        ),
      );
    } on Object catch (e) {
      // Not every platform supports audio contexts; the defaults are fine.
      debugPrint('Sound setup skipped: $e');
    }
  }
}

/// Plays sound effects unless the player has muted them. The setting is
/// remembered on the device.
class SoundEffects {
  SoundEffects({SoundPlayer? player})
    : player = player ?? AudioplayersSoundPlayer();

  static const _mutedKey = 'sounds_muted';

  SoundPlayer player;

  /// Whether sounds are off. Listen to it to update a mute button.
  final muted = ValueNotifier<bool>(false);

  /// Reads the saved mute setting.
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    muted.value = prefs.getBool(_mutedKey) ?? false;
  }

  Future<void> setMuted(bool value) async {
    muted.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_mutedKey, value);
  }

  /// Plays [sound] without waiting for it. A sound that fails to play (for
  /// example a browser blocking audio before the first tap) is skipped rather
  /// than interrupting the app.
  void play(Sound sound) {
    if (muted.value) return;
    unawaited(
      player.play(sound).catchError((Object e) {
        debugPrint('Sound ${sound.name} failed: $e');
      }),
    );
  }

  /// [action] with a [sound] played first, or null if [action] is null, so a
  /// disabled button stays disabled.
  VoidCallback? withSound(VoidCallback? action, [Sound sound = Sound.tap]) {
    if (action == null) return null;
    return () {
      play(sound);
      action();
    };
  }
}

/// Shared sound effects for the app.
final sfx = SoundEffects();
