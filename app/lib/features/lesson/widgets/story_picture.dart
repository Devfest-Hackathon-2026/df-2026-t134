import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/media.dart';
import '../../../design/chapter_theme.dart';
import '../../../models/story.dart';

/// Width / height of the generated scene pictures (`make illustrate`).
const storyPictureAspectRatio = 3 / 2;

/// A scene's picture from Cloud Storage. Until it loads, and whenever there
/// is none (not generated yet, offline, local emulators), a calm placeholder
/// in the unit's colors keeps the layout the same: never a broken image.
/// Decorative: the scene's text carries the story.
class StoryPicture extends ConsumerWidget {
  const StoryPicture({super.key, required this.illustration});

  final Illustration? illustration;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = illustration?.imagePath;
    final url = path == null ? null : ref.watch(mediaUrlProvider(path)).value;
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: AspectRatio(
          aspectRatio: storyPictureAspectRatio,
          child: url == null
              ? const StoryPicturePlaceholder()
              : Image.network(
                  url.toString(),
                  key: const Key('story-picture'),
                  fit: BoxFit.cover,
                  // Cloud Storage sends no CORS headers by default; an <img>
                  // element shows the picture anyway.
                  webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                  frameBuilder: (context, child, frame, synchronous) =>
                      synchronous || frame != null
                      ? child
                      : const StoryPicturePlaceholder(),
                  errorBuilder: (context, error, stackTrace) =>
                      const StoryPicturePlaceholder(),
                ),
        ),
      ),
    );
  }
}

/// A soft wash with a picture-book mark, in the chapter's colors. Still (no
/// animation): the header's motif is the screen's one moving decoration.
class StoryPicturePlaceholder extends StatelessWidget {
  const StoryPicturePlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = ChapterPalette.of(context);
    return DecoratedBox(
      key: const Key('story-picture-placeholder'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.wash, ChapterPalette.background],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.auto_stories_rounded,
          size: 56,
          color: palette.accent.withValues(alpha: .35),
        ),
      ),
    );
  }
}
