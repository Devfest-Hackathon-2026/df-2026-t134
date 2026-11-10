import 'package:ailearn/models/content.dart';
import 'package:ailearn/models/exercise.dart';

import 'fake_api.dart';
import 'fakes.dart';

/// A short Unit 3 lesson: a choice exercise, then the Fuji live check, as
/// the JSON the seed writes from content/units/u3/u3-l1.yaml (q1 and q3).
/// The fake AI's answer is the one the real model gave in the manual check
/// (one rewritten number).
abstract final class LiveCheckLessonFixture {
  static const lessonId = 'u3-l1';
  static const choiceId = 'u3-l1-q1';
  static const liveId = 'u3-l1-q3';

  static final lesson = Lesson.fromJson({
    'id': lessonId,
    'unitId': 'u3',
    'order': 1,
    'title': 'AI の答えを確かめよう',
    'exerciseIds': [choiceId, liveId],
    'intro': {'text': '質問への AI の回答が正しいか、出典と見くらべて確かめよう。'},
  });

  static final choice = Exercise.fromJson({
    'id': choiceId,
    'lessonId': lessonId,
    'type': 'choice',
    'question': 'AI の答えが正しいか確かめるとき、いちばん手がかりになるのはどれ？',
    'options': [
      {'id': 'a', 'text': '同じ質問を AI にもう一度する'},
      {'id': 'b', 'text': '答えのもとになったウェブページ（出典）を開いて見くらべる'},
      {'id': 'c', 'text': 'AI が自信のある言い方をしているかを見る'},
    ],
  });

  static final liveCheck = Exercise.fromJson({
    'id': liveId,
    'lessonId': lessonId,
    'type': 'live_check',
    'question': 'AI に富士山のことを質問し、回答が正しいか確かめよう。',
    'intro': {'text': '例をタップしてもいいし、自分で質問を考えてもいいよ。'},
    'theme': '富士山',
    'suggestions': ['富士山の高さと、どこにあるかを教えて', '富士山が世界遺産になったのはいつ？'],
    'errorCount': 1,
    'lookupLimit': 2,
    'maxLength': 200,
  }) as LiveCheckExercise;

  static const answerKeys = {
    choiceId: {
      'type': 'choice',
      'correctOptionId': 'b',
      'explanation': '出典を開いて、自分の目で見くらべよう。',
    },
    liveId: {'type': 'live_check', 'topicGuide': '富士山の高さ・場所・歴史'},
  };

  static const wrongIndex = 0;
  static const correction = '富士山の高さは、3776メートルです。';
  static const tip = '富士山の正確な標高を、地図帳や教科書などで調べてみましょう。';

  static const answer = FakeLiveCheckAnswer(
    sentences: [
      '富士山の高さは、3876メートルです。',
      '日本で一番高い山として知られています。',
      '場所は、静岡県と山梨県の境にあります。',
      '富士山は二つの県にまたがってそびえています。',
      '美しい姿から、2013年には世界文化遺産に登録されました。',
    ],
    errors: [
      {
        'index': wrongIndex,
        'errorType': 'number',
        'correction': correction,
        'tip': tip,
      },
    ],
    sources: {
      0: [
        {'title': 'fuji-net.co.jp', 'uri': 'https://example.jp/fuji'},
      ],
      2: [
        {'title': 'pref.yamanashi.jp', 'uri': 'https://example.jp/yamanashi'},
      ],
    },
  );

  static FakeContentRepository content() => FakeContentRepository(
    units: [unit('u3', 1)],
    lessons: [lesson],
    exercises: [choice, liveCheck],
  );

  /// With the fake AI on; set `liveCheckAnswer = null` for AI off.
  static FakeLearningApi api() => FakeLearningApi(
    answerKeys: answerKeys,
    lessonExercises: {lessonId: lesson.exerciseIds},
  )..liveCheckAnswer = answer;
}
