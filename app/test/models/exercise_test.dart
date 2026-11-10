import 'package:ailearn/models/content.dart';
import 'package:ailearn/models/exercise.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/unit1.dart';

Map<String, Object?> hallucinationJson() => {
  'id': 'u2-l1-q1',
  'lessonId': 'u2-l1',
  'type': 'hallucination',
  'question': 'まちがっている文をタップしよう',
  'topic': '光合成',
  'sentences': [
    {'index': 0, 'text': '光合成は植物が光のエネルギーを使って栄養をつくるしくみです。'},
    {'index': 1, 'text': '光合成は主に根の細胞で行われます。'},
  ],
  'errorCount': 1,
};

Map<String, Object?> promptJson() => {
  'id': 'u3-l1-q1',
  'lessonId': 'u3-l1',
  'type': 'prompt',
  'question': 'プロンプトを書こう',
  'task': '文化祭の出し物のアイデアを AI に出してもらおう',
};

void main() {
  group('Unit 1 content', () {
    test('every lesson and exercise parses', () {
      expect(unit1.lessons, hasLength(3));
      expect(unit1.exercises, hasLength(18));
      expect(unit1.exercises.map((e) => e.type).toSet(), {
        ExerciseType.choice,
        ExerciseType.order,
        ExerciseType.fillBlank,
      });
    });

    test('lessons keep the intro text with its line breaks', () {
      final lesson = unit1.lesson('u1-l1');

      expect(lesson.exerciseIds, hasLength(6));
      expect(lesson.intro?.text, contains('\n'));
      expect(lesson.intro?.audioPath, isNull);
    });

    test('a choice exercise has its options and no intro', () {
      final exercise = unit1.exercise<ChoiceExercise>('u1-l1-q1');

      expect(exercise.lessonId, 'u1-l1');
      expect(exercise.question, contains('生成 AI'));
      expect(exercise.options.map((o) => o.id), ['a', 'b', 'c', 'd']);
      expect(exercise.intro, isNull);
    });

    test('an order exercise keeps the authoring order of its items', () {
      final exercise = unit1.exercise<OrderExercise>('u1-l1-q4');

      expect(exercise.items.map((i) => i.id), [
        'repeat',
        'input',
        'append',
        'predict',
      ]);
    });

    test('a fill-in-the-blank template is split into text and slots', () {
      final exercise = unit1.exercise<FillBlankExercise>('u1-l1-q6');

      expect(exercise.blanks.map((b) => b.id), ['data', 'pattern']);
      final parts = exercise.parts;
      expect(parts, hasLength(5));
      expect((parts[0] as TemplateText).text, '生成 AI は、大量の');
      expect((parts[1] as TemplateSlot).blank.id, 'data');
      expect((parts[2] as TemplateText).text, 'から、ことばの');
      expect((parts[3] as TemplateSlot).blank.id, 'pattern');
      expect((parts[4] as TemplateText).text, 'を学び、次に来ることばを予測している。');
    });
  });

  group('Exercise.fromJson', () {
    test('parses the intro speech of an exercise', () {
      final json = unit1.exerciseJson('u1-l1-q1')
        ..['intro'] = {'text': 'よく考えてね', 'audioPath': 'tts/abc.mp3'};

      final exercise = Exercise.fromJson(json);

      expect(exercise.intro?.text, 'よく考えてね');
      expect(exercise.intro?.audioPath, 'tts/abc.mp3');
    });

    test('parses hallucination exercises', () {
      final exercise = Exercise.fromJson(hallucinationJson());

      expect(exercise, isA<HallucinationExercise>());
      exercise as HallucinationExercise;
      expect(exercise.topic, '光合成');
      expect(exercise.sentences.map((s) => s.index), [0, 1]);
      expect(exercise.errorCount, 1);
    });

    test('parses prompt exercises; a missing maxLength is the default', () {
      final exercise = Exercise.fromJson(promptJson()) as PromptExercise;

      expect(exercise.task, contains('文化祭'));
      expect(exercise.maxLength, PromptExercise.defaultMaxLength);
      expect(
        (Exercise.fromJson(
          promptJson()..['maxLength'] = 200,
        ) as PromptExercise).maxLength,
        200,
      );
    });

    test('rejects unknown types and unknown fields', () {
      expect(
        () => Exercise.fromJson(unit1.exerciseJson('u1-l1-q1')..['type'] = 'x'),
        throwsFormatException,
      );
      expect(
        () =>
            Exercise.fromJson(unit1.exerciseJson('u1-l1-q1')..['answer'] = 'b'),
        throwsFormatException,
      );
      expect(
        () => Exercise.fromJson(
          unit1.exerciseJson('u1-l1-q4')..['correctOrder'] = ['input'],
        ),
        throwsFormatException,
      );
      expect(() => Exercise.fromJson('choice'), throwsFormatException);
    });

    test('rejects missing or malformed fields', () {
      expect(
        () => Exercise.fromJson(
          unit1.exerciseJson('u1-l1-q1')..remove('question'),
        ),
        throwsFormatException,
      );
      expect(
        () => Exercise.fromJson(
          unit1.exerciseJson('u1-l1-q1')
            ..['options'] = [
              {'id': 'a', 'text': 'ひとつだけ'},
            ],
        ),
        throwsFormatException,
      );
      expect(
        () => Exercise.fromJson(
          unit1.exerciseJson('u1-l1-q1')
            ..['options'] = [
              {'id': 'a', 'text': 'A'},
              {'id': 'a', 'text': 'B'},
            ],
        ),
        throwsFormatException,
      );
      expect(
        () => Exercise.fromJson(
          unit1.exerciseJson('u1-l1-q1')..['lessonId'] = 'U1',
        ),
        throwsFormatException,
      );
      expect(
        () => Exercise.fromJson(hallucinationJson()..['errorCount'] = 2),
        throwsFormatException,
      );
      expect(
        () => Exercise.fromJson(
          hallucinationJson()
            ..['sentences'] = [
              {'index': 1, 'text': 'a'},
              {'index': 0, 'text': 'b'},
            ],
        ),
        throwsFormatException,
      );
      expect(
        () => Exercise.fromJson(promptJson()..['maxLength'] = 5),
        throwsFormatException,
      );
    });

    test('rejects templates that do not match the blanks', () {
      Map<String, Object?> withTemplate(String template) =>
          unit1.exerciseJson('u1-l1-q2')..['template'] = template;

      expect(
        () => Exercise.fromJson(withTemplate('空らんがない')),
        throwsFormatException,
      );
      expect(
        () => Exercise.fromJson(withTemplate('{{next}} と {{next}}')),
        throwsFormatException,
      );
      expect(
        () => Exercise.fromJson(withTemplate('{{next}} と {{other}}')),
        throwsFormatException,
      );
      final ok =
          Exercise.fromJson(withTemplate('{{next}}')) as FillBlankExercise;
      expect(ok.parts.single, isA<TemplateSlot>());
    });
  });

  test('Speech text keeps newlines', () {
    final speech = Speech.fromJson({'text': '1 行目\n2 行目'});

    expect(speech.text.split('\n'), ['1 行目', '2 行目']);
  });
}
