import 'package:flutter/material.dart';

import '../../../models/content.dart';

/// The mascot saying [speech] in a speech bubble. The text is always shown
/// (subtitles), so the lesson works with the sound off.
///
/// Audio seam: PR-15 adds playback of `speech.audioPath` here (e.g. a play
/// button next to the text); callers only pass the [Speech].
class MascotBubble extends StatelessWidget {
  const MascotBubble({super.key, required this.speech});

  final Speech speech;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: scheme.primary,
          child: Icon(
            Icons.smart_toy_rounded,
            size: 24,
            color: scheme.onPrimary,
            semanticLabel: 'マスコット',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            key: const Key('mascot-speech'),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
            ),
            // Text renders the `\n` between sentences as line breaks.
            child: Text(
              speech.text,
              style: TextStyle(
                fontSize: 16,
                height: 1.6,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
