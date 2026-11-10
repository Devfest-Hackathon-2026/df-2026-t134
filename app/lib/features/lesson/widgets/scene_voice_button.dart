import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/voice_player.dart';
import '../../../data/media.dart';

/// A small button that reads a scene's line aloud. Nothing is played on its
/// own (classrooms may be quiet) and the text is always shown, so the button
/// is left out when the line has no voice or the app has no player.
class SceneVoiceButton extends ConsumerStatefulWidget {
  const SceneVoiceButton({super.key, required this.audioPath});

  /// Cloud Storage path of the line's voice (`audio/lines/...`).
  final String audioPath;

  @override
  ConsumerState<SceneVoiceButton> createState() => _SceneVoiceButtonState();
}

enum _Voice { idle, playing, failed }

class _SceneVoiceButtonState extends ConsumerState<SceneVoiceButton> {
  _Voice _voice = _Voice.idle;
  VoicePlayer? _player;

  @override
  void dispose() {
    // Leaving the scene stops its line.
    if (_voice == _Voice.playing) {
      _player?.stop();
    }
    super.dispose();
  }

  Future<void> _toggle(VoicePlayer player, MediaRepository media) async {
    if (_voice == _Voice.playing) {
      await player.stop();
      return;
    }
    _player = player;
    setState(() => _voice = _Voice.playing);
    var next = _Voice.idle;
    try {
      await player.play(await media.downloadUrl(widget.audioPath));
    } on Exception {
      next = _Voice.failed;
    }
    if (mounted) {
      setState(() => _voice = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(voicePlayerProvider);
    final media = ref.watch(mediaRepositoryProvider);
    if (player == null || media == null) {
      return const SizedBox.shrink();
    }
    final (icon, tooltip) = switch (_voice) {
      _Voice.idle => (Icons.volume_up_rounded, 'よみあげる'),
      _Voice.playing => (Icons.stop_circle_outlined, 'よみあげをとめる'),
      _Voice.failed => (Icons.volume_off_rounded, '音声を再生できませんでした。もう一度ためす'),
    };
    return IconButton.filledTonal(
      key: const Key('story-voice'),
      tooltip: tooltip,
      icon: Icon(icon),
      onPressed: () => _toggle(player, media),
    );
  }
}
