import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

/// Plays one recorded line at a time (story scenes). Voices are optional:
/// the text is always on screen.
abstract interface class VoicePlayer {
  /// Plays [url] from the start, stopping whatever was playing. Completes
  /// when the line has finished or was stopped; throws when it cannot play.
  Future<void> play(Uri url);

  Future<void> stop();
}

/// Overridden in main() with [JustAudioVoicePlayer]. Without it (tests,
/// previews) the story shows no voice buttons.
final voicePlayerProvider = Provider<VoicePlayer?>((ref) => null);

/// [VoicePlayer] on just_audio (an HTML audio element on the web).
class JustAudioVoicePlayer implements VoicePlayer {
  final _player = AudioPlayer();

  @override
  Future<void> play(Uri url) async {
    await _player.stop();
    await _player.setUrl(url.toString());
    await _player.play();
  }

  @override
  Future<void> stop() => _player.stop();

  Future<void> dispose() => _player.dispose();
}
