import 'package:ailearn/features/lesson/lesson_state.dart';
import 'package:ailearn/models/answer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/story.dart';
import 'lesson_controller_test.dart' show Harness;

Harness storyHarness() {
  final setup = storyFixture.setup();
  return Harness(
    StoryFixture.lessonId,
    content: setup.content,
    api: setup.api,
    answerKeys: storyFixture.answerKeys,
  );
}

StoryDraft draftOf(Harness h) => h.playing.draft as StoryDraft;

String bestOf(String exerciseId) =>
    storyFixture.answerKeys[exerciseId]!['bestOptionId']! as String;

/// Plays every scene with 「つぎへ」 until the question is asked.
void watchScenes(Harness h) {
  while (!draftOf(h).isDeciding) {
    h.controller.nextStoryScene();
  }
}

/// Plays the chosen outcome to its end.
void watchOutcome(Harness h) {
  final status = h.playing.status as Checked;
  final result = status.response.result as StoryResult;
  while (!draftOf(h).outcomeDone(result)) {
    h.controller.nextStoryScene();
  }
}

void main() {
  test('scenes, choice, outcome, then the next exercise', () async {
    final h = storyHarness();
    await h.start();
    final first = storyFixture.exercises.first;

    expect(draftOf(h).sceneIndex, 0);
    expect(draftOf(h).toAnswer(), isNull);
    expect(
      () => h.controller.selectStoryOption(bestOf(first.id)),
      throwsStateError,
      reason: 'the options come after the scenes',
    );
    h.controller.nextStoryScene();
    expect(draftOf(h).sceneIndex, 1);
    watchScenes(h);
    expect(draftOf(h).sceneIndex, first.scenes.length);

    h.controller.selectStoryOption(bestOf(first.id));
    expect(h.playing.draft.toAnswer()?.toJson(), {
      'type': 'story',
      'optionId': bestOf(first.id),
    });
    await h.controller.check();

    final checked = h.playing.status as Checked;
    expect(checked.response.correct, isTrue);
    final result = checked.response.result as StoryResult;
    expect(result.outcome, isNotEmpty);
    expect(
      (checked.correctAnswer as CorrectText).text,
      first.options.firstWhere((o) => o.id == bestOf(first.id)).text,
    );
    await expectLater(
      h.controller.next(),
      throwsStateError,
      reason: 'the outcome plays before moving on',
    );
    h.controller.nextStoryScene();
    expect(draftOf(h).outcomeIndex, 1);
    expect(h.playing.status, same(checked), reason: 'still checked');
    watchOutcome(h);
    expect(h.controller.nextStoryScene, throwsStateError);

    await h.controller.next();
    expect(h.playing.index, 1);
    expect(draftOf(h).exercise.id, storyFixture.exercises[1].id);
    expect(draftOf(h).sceneIndex, 0);
    expect(h.api.answerBodies.single['answer'], {
      'type': 'story',
      'optionId': bestOf(first.id),
    });
  });

  test('a wrong choice is played again once at the end', () async {
    final h = storyHarness();
    await h.start();
    final steps = h.playing.steps.length;

    h.fill(correct: false);
    await h.controller.check();
    expect((h.playing.status as Checked).response.correct, isFalse);
    expect(h.playing.steps, hasLength(steps + 1));
    expect(h.playing.steps.last.isReview, isTrue);
    watchOutcome(h);
    await h.controller.next();

    for (var i = 1; i < steps; i++) {
      h.fill(correct: true);
      await h.controller.check();
      watchOutcome(h);
      await h.controller.next();
    }

    // The review starts the story from its first scene and is not queued
    // again when it is wrong.
    expect(h.playing.step.isReview, isTrue);
    expect(draftOf(h).sceneIndex, 0);
    h.fill(correct: false);
    await h.controller.check();
    expect(h.playing.steps, hasLength(steps + 1));
    watchOutcome(h);
    await h.controller.next();

    expect(h.state, isA<LessonFinished>());
    expect(h.api.completed, {StoryFixture.lessonId});
  });

  test('taps while sending change nothing', () async {
    final h = storyHarness();
    await h.start();
    h.fill(correct: true);

    final sending = h.controller.check();
    h.controller.nextStoryScene();
    h.controller.selectStoryOption(storyFixture.exercises.first.options[0].id);
    await sending;

    final answer = h.api.answerBodies.single['answer']! as Map;
    expect(answer['optionId'], bestOf(storyFixture.exercises.first.id));
    expect(draftOf(h).outcomeIndex, 0);
  });
}
