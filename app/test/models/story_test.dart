import 'package:ailearn/models/answer.dart';
import 'package:ailearn/models/exercise.dart';
import 'package:ailearn/models/story.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/story.dart';

Map<String, Object?> storyJson() => {
  'id': 'u9-l1-q1',
  'lessonId': 'u9-l1',
  'type': 'story',
  'title': '自由研究',
  'question': 'ユイはどうする？',
  'scenes': [
    {
      'speaker': 'narrator',
      'text': 'ユイは自由研究をしています。',
      'illustration': {
        'prompt': 'Yui at her desk',
        'imagePath': 'images/scenes/a.jpg',
      },
    },
    {'speaker': 'ai', 'text': 'ホタルは電気で光ります。', 'audioPath': 'audio/lines/b.mp3'},
  ],
  'options': [
    {'id': 'copy', 'text': 'そのまま書く'},
    {'id': 'check', 'text': '確かめる'},
  ],
};

Map<String, Object?> storyResultJson() => {
  'type': 'story',
  'bestOptionId': 'check',
  'outcome': [
    // The API sends unset media as null.
    {
      'speaker': 'teacher',
      'text': 'どこで調べたの？',
      'audioPath': null,
      'illustration': null,
    },
  ],
  'explanation': '確かめよう。',
};

void main() {
  group('StoryExercise', () {
    test('parses scenes with speakers, pictures and voices', () {
      final exercise = Exercise.fromJson(storyJson()) as StoryExercise;

      expect(exercise.type, ExerciseType.story);
      expect(exercise.title, '自由研究');
      expect(exercise.scenes.map((s) => s.speaker), [
        Speaker.narrator,
        Speaker.ai,
      ]);
      expect(exercise.scenes[0].illustration?.imagePath, 'images/scenes/a.jpg');
      expect(exercise.scenes[0].audioPath, isNull);
      expect(exercise.scenes[1].illustration, isNull);
      expect(exercise.scenes[1].audioPath, 'audio/lines/b.mp3');
      expect(exercise.options.map((o) => o.id), ['copy', 'check']);
    });

    test('the real story lesson parses', () {
      expect(storyFixture.exercises, hasLength(3));
      for (final exercise in storyFixture.exercises) {
        expect(exercise.scenes.length, inInclusiveRange(3, 6));
        expect(exercise.scenes.first.illustration, isNotNull);
      }
    });

    for (final (name, edit) in <(String, void Function(Map<String, Object?>))>[
      ('an unknown field', (j) => j['mood'] = 'calm'),
      (
        'an unknown speaker',
        (j) => (j['scenes']! as List)[0]['speaker'] = 'cat',
      ),
      ('an empty line', (j) => (j['scenes']! as List)[1]['text'] = ''),
      ('no scenes', (j) => j['scenes'] = []),
      (
        'too many options',
        (j) => j['options'] = [
          for (final id in ['a', 'b', 'c', 'd', 'e']) {'id': id, 'text': id},
        ],
      ),
      (
        'duplicate option ids',
        (j) => j['options'] = [
          {'id': 'a', 'text': 'A'},
          {'id': 'a', 'text': 'B'},
        ],
      ),
      (
        'an unknown illustration field',
        (j) => ((j['scenes']! as List)[0]['illustration'] as Map)['alt'] = 'x',
      ),
    ]) {
      test('rejects $name', () {
        final json = storyJson();
        edit(json);

        expect(() => Exercise.fromJson(json), throwsFormatException);
      });
    }
  });

  group('StoryResult', () {
    test('parses the outcome, treating null media as unset', () {
      final result = AnswerResult.fromJson(storyResultJson()) as StoryResult;

      expect(result.type, ExerciseType.story);
      expect(result.bestOptionId, 'check');
      expect(result.outcome.single.speaker, Speaker.teacher);
      expect(result.outcome.single.audioPath, isNull);
      expect(result.explanation, '確かめよう。');
    });

    test('rejects an empty outcome and unknown fields', () {
      expect(
        () => AnswerResult.fromJson({...storyResultJson(), 'outcome': []}),
        throwsFormatException,
      );
      expect(
        () => AnswerResult.fromJson({...storyResultJson(), 'score': 1}),
        throwsFormatException,
      );
    });

    test('a story answer sends the chosen option', () {
      expect(const StoryAnswer('check').toJson(), {
        'type': 'story',
        'optionId': 'check',
      });
    });
  });

  test('a scene without a picture keeps the one before it', () {
    final exercise = Exercise.fromJson(storyJson()) as StoryExercise;
    const later = Scene(speaker: Speaker.student, text: 'え？');

    expect(pictureAt(exercise.scenes, 1)?.imagePath, 'images/scenes/a.jpg');
    expect(pictureAt([later], 0), isNull);
    expect(
      pictureAt([...exercise.scenes, later], 2)?.prompt,
      'Yui at her desk',
    );
  });
}
