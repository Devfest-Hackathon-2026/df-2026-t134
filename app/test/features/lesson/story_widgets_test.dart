import 'dart:async';

import 'package:ailearn/core/voice_player.dart';
import 'package:ailearn/data/media.dart';
import 'package:ailearn/design/chapter_theme.dart';
import 'package:ailearn/design/motion.dart';
import 'package:ailearn/features/lesson/lesson_state.dart';
import 'package:ailearn/features/lesson/widgets/story_exercise_view.dart';
import 'package:ailearn/models/answer.dart';
import 'package:ailearn/models/exercise.dart';
import 'package:ailearn/models/story.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../models/story_test.dart' show storyJson;

class FakeMedia implements MediaRepository {
  final asked = <String>[];

  @override
  Future<Uri> downloadUrl(String storagePath) async {
    asked.add(storagePath);
    return Uri.parse('https://media.example.invalid/$storagePath');
  }
}

class FakeVoicePlayer implements VoicePlayer {
  FakeVoicePlayer({this.fails = false});

  final bool fails;
  final played = <Uri>[];
  var stops = 0;
  Completer<void>? _line;

  @override
  Future<void> play(Uri url) {
    played.add(url);
    if (fails) {
      return Future.error(Exception('cannot play'));
    }
    _line = Completer<void>();
    return _line!.future;
  }

  void finish() => _line?.complete();

  @override
  Future<void> stop() async {
    stops++;
    if (_line case final line? when !line.isCompleted) {
      line.complete();
    }
  }
}

StoryExercise story() => Exercise.fromJson(storyJson()) as StoryExercise;

Future<void> pumpView(
  WidgetTester tester,
  Widget child, {
  MediaRepository? media,
  VoicePlayer? player,
  bool reduced = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        mediaRepositoryProvider.overrideWithValue(media),
        voicePlayerProvider.overrideWithValue(player),
        reducedMotionProvider.overrideWith(() => _Motion(reduced)),
      ],
      child: MaterialApp(
        theme: ailearnTheme(ChapterPalette.forUnit('u1')),
        home: Scaffold(body: ListView(children: [child])),
      ),
    ),
  );
  // Lets the media URLs resolve.
  await tester.pump();
  await tester.pump();
}

class _Motion extends MotionPreference {
  _Motion(this.reduced);
  final bool reduced;
  @override
  bool build() => reduced;
}

SceneCard card(Scene scene, {VoidCallback? onTap}) =>
    SceneCard(scene: scene, picture: scene.illustration, onTap: onTap);

const pictured = Scene(
  speaker: Speaker.narrator,
  text: 'ユイは自由研究をしています。',
  illustration: Illustration(
    prompt: 'Yui at her desk',
    imagePath: 'images/scenes/a.jpg',
  ),
);

const voiced = Scene(
  speaker: Speaker.ai,
  text: 'ホタルは電気で光ります。',
  audioPath: 'audio/lines/b.mp3',
);

void main() {
  group('SceneCard picture', () {
    testWidgets('a scene without a picture shows the calm placeholder', (
      tester,
    ) async {
      await pumpView(tester, card(voiced), media: FakeMedia());

      expect(find.byKey(const Key('story-picture-placeholder')), findsOne);
      expect(find.byKey(const Key('story-picture')), findsNothing);
      expect(find.text('AI アシスタント'), findsOne);
      expect(find.text('ホタルは電気で光ります。'), findsOne);
    });

    testWidgets('a generated picture is loaded from Cloud Storage', (
      tester,
    ) async {
      final media = FakeMedia();
      await pumpView(tester, card(pictured), media: media);

      expect(media.asked, ['images/scenes/a.jpg']);
      final image = tester.widget<Image>(
        find.byKey(const Key('story-picture')),
      );
      expect(
        (image.image as NetworkImage).url,
        'https://media.example.invalid/images/scenes/a.jpg',
      );
      // Until (or unless) the picture arrives, the placeholder holds its place.
      expect(find.byKey(const Key('story-picture-placeholder')), findsOne);
      expect(tester.takeException(), isNull);
    });

    testWidgets('without Cloud Storage the picture is a placeholder', (
      tester,
    ) async {
      await pumpView(tester, card(pictured));

      expect(find.byKey(const Key('story-picture')), findsNothing);
      expect(find.byKey(const Key('story-picture-placeholder')), findsOne);
    });

    testWidgets('tapping the scene moves on', (tester) async {
      var taps = 0;
      await pumpView(tester, card(pictured, onTap: () => taps++));

      await tester.tap(find.byType(SceneCard));
      expect(taps, 1);
    });
  });

  group('SceneCard voice', () {
    testWidgets('no button without a voice or a player', (tester) async {
      await pumpView(tester, card(pictured), player: FakeVoicePlayer());
      expect(find.byKey(const Key('story-voice')), findsNothing);

      await pumpView(tester, card(voiced), media: FakeMedia());
      expect(find.byKey(const Key('story-voice')), findsNothing);
    });

    testWidgets('plays the line on request and can stop it', (tester) async {
      final player = FakeVoicePlayer();
      await pumpView(tester, card(voiced), media: FakeMedia(), player: player);
      expect(player.played, isEmpty, reason: 'never plays by itself');

      await tester.tap(find.byKey(const Key('story-voice')));
      await tester.pump();
      expect(player.played, [
        Uri.parse('https://media.example.invalid/audio/lines/b.mp3'),
      ]);
      expect(find.byTooltip('よみあげをとめる'), findsOne);

      await tester.tap(find.byKey(const Key('story-voice')));
      await tester.pump();
      expect(player.stops, 1);
      expect(find.byTooltip('よみあげる'), findsOne);
    });

    testWidgets('a line that cannot play keeps the text and says so', (
      tester,
    ) async {
      await pumpView(
        tester,
        card(voiced),
        media: FakeMedia(),
        player: FakeVoicePlayer(fails: true),
      );

      await tester.tap(find.byKey(const Key('story-voice')));
      await tester.pump();

      expect(find.byIcon(Icons.volume_off_rounded), findsOne);
      expect(find.text('ホタルは電気で光ります。'), findsOne);
    });

    testWidgets('leaving the scene stops its line', (tester) async {
      final player = FakeVoicePlayer();
      await pumpView(tester, card(voiced), media: FakeMedia(), player: player);
      await tester.tap(find.byKey(const Key('story-voice')));
      await tester.pump();

      await pumpView(
        tester,
        card(pictured),
        media: FakeMedia(),
        player: player,
      );

      expect(player.stops, 1);
    });
  });

  group('StoryExerciseView', () {
    testWidgets('plays scenes, then asks, then shows the outcome', (
      tester,
    ) async {
      final exercise = story();
      await pumpView(
        tester,
        StoryExerciseView(
          draft: StoryDraft(exercise),
          result: null,
          onAdvance: () {},
          onSelect: null,
        ),
      );
      expect(find.text('場面 1 / 2'), findsOne);
      expect(find.byKey(const Key('story-question')), findsNothing);
      expect(find.byKey(const Key('choice-option-copy')), findsNothing);

      await pumpView(
        tester,
        StoryExerciseView(
          draft: StoryDraft(exercise).skipScenes().select('copy'),
          result: null,
          onAdvance: null,
          onSelect: (_) {},
        ),
      );
      expect(find.text('ユイはどうする？'), findsOne);
      expect(find.text('ホタルは電気で光ります。'), findsOne, reason: 'last scene');
      expect(find.byKey(const Key('choice-option-check')), findsOne);

      final result = StoryResult(
        bestOptionId: 'check',
        outcome: const [
          Scene(speaker: Speaker.teacher, text: 'どこで調べたの？'),
          Scene(speaker: Speaker.student, text: 'まちがえた……。'),
        ],
        explanation: '確かめよう。',
      );
      final chosen = StoryDraft(exercise).skipScenes().select('copy');
      await pumpView(
        tester,
        StoryExerciseView(
          draft: chosen,
          result: result,
          onAdvance: () {},
          onSelect: null,
        ),
      );
      expect(find.text('えらんだ：そのまま書く'), findsOne);
      expect(find.text('そのあと 1 / 2'), findsOne);
      expect(find.text('どこで調べたの？'), findsOne);
      expect(find.byKey(const Key('story-speaker-teacher')), findsOne);
      // The outcome keeps the story's last picture.
      expect(find.byKey(const Key('story-picture-placeholder')), findsOne);
      expect(find.byKey(const Key('choice-option-check')), findsNothing);

      await pumpView(
        tester,
        StoryExerciseView(
          draft: chosen.nextOutcomeScene(result).nextOutcomeScene(result),
          result: result,
          onAdvance: null,
          onSelect: null,
        ),
      );
      expect(find.text('まちがえた……。'), findsOne, reason: 'stays on the last');
      expect(find.text('せいかい'), findsOne);
      expect(find.text('ちがうよ'), findsOne);
    });

    for (final reduced in [true, false]) {
      testWidgets('scene changes ${reduced ? 'are instant' : 'fade'} '
          'when motion is ${reduced ? '' : 'not '}reduced', (tester) async {
        await pumpView(
          tester,
          StoryExerciseView(
            draft: StoryDraft(story()),
            result: null,
            onAdvance: () {},
            onSelect: null,
          ),
          reduced: reduced,
        );

        final switcher = tester.widget<AnimatedSwitcher>(
          find.byType(AnimatedSwitcher),
        );
        expect(
          switcher.duration,
          reduced ? Duration.zero : const Duration(milliseconds: 320),
        );
      });
    }
  });
}
