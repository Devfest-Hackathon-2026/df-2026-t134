import 'package:ailearn/models/content.dart';
import 'package:ailearn/models/exercise.dart';

import 'fake_api.dart';
import 'fakes.dart';

/// A short lesson ending with a prompt exercise, taken from the Unit 2 draft
/// content (content/units/u2/u2-l1.yaml, q2 and q6) as the JSON the seed
/// writes to Firestore.
abstract final class PromptLessonFixture {
  static const lessonId = 'u2-l1';
  static const choiceId = 'u2-l1-q2';
  static const promptId = 'u2-l1-q6';

  static final lesson = Lesson.fromJson({
    'id': lessonId,
    'unitId': 'u2',
    'order': 1,
    'title': 'AI に伝わるお願いって？',
    'exerciseIds': [choiceId, promptId],
    'intro': {'text': 'AI へのお願いの文を「プロンプト」というよ。'},
  });

  static final choice = Exercise.fromJson({
    'id': choiceId,
    'lessonId': lessonId,
    'type': 'choice',
    'question': 'ほしい答えが返ってきやすいプロンプトはどっち？',
    'options': [
      {'id': 'a', 'text': '「おすすめの本を教えて」'},
      {'id': 'b', 'text': '「中学 1 年生が夏休みに読める、冒険がテーマの小説を 3 冊、あらすじつきで教えて」'},
    ],
  });

  static final prompt = Exercise.fromJson({
    'id': promptId,
    'lessonId': lessonId,
    'type': 'prompt',
    'question': 'プロンプトを書いてみよう',
    'task': '日曜日に家族で出かける場所のアイデアを、AI に出してもらうプロンプトを書こう。',
    'intro': {'text': '今日のポイントを使って、自分でプロンプトを書いてみよう！'},
  }) as PromptExercise;

  static const answerKeys = {
    choiceId: {
      'type': 'choice',
      'correctOptionId': 'b',
      'explanation': 'くわしく伝えるほど、AI はあなたに合った答えを返しやすくなるよ。',
    },
  };

  /// A prompt with every element and no personal information.
  static const goodPrompt =
      'あなたは旅行の案内係です。日曜日に家族 4 人（小学生の弟がいます）で'
      '日帰りで出かける場所を決めたいです。電車で 1 時間以内、雨でも楽しめる'
      '場所を 3 つ、おすすめの理由つきの箇条書きで教えてください。';

  static FakeContentRepository content() => FakeContentRepository(
    units: [unit('u2', 1)],
    lessons: [lesson],
    exercises: [choice, prompt],
  );

  static FakeLearningApi api() => FakeLearningApi(
    answerKeys: answerKeys,
    lessonExercises: {lessonId: lesson.exerciseIds},
  );
}
