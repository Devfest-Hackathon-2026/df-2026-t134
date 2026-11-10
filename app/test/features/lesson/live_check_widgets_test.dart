import '../../support/answer_selection.dart';

import 'package:ailearn/design/motion.dart';
import 'package:ailearn/features/lesson/lesson_state.dart';
import 'package:ailearn/features/lesson/widgets/live_check_exercise_view.dart';
import 'package:ailearn/features/lesson/widgets/live_check_feedback_view.dart';
import 'package:ailearn/features/lesson/widgets/live_check_generating.dart';
import 'package:ailearn/features/lesson/widgets/web_source_list.dart';
import 'package:ailearn/features/lesson/hallucination_review.dart';
import 'package:ailearn/models/answer.dart';
import 'package:ailearn/models/live_check.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../models/live_check_test.dart' show startedJson;
import '../../support/live_check_lesson.dart';

typedef F = LiveCheckLessonFixture;

final session = LiveCheckStarted.fromJson(startedJson());

Future<void> pump(
  WidgetTester tester,
  Widget child, {
  List<Uri>? opened,
  bool reduced = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        linkOpenerProvider.overrideWithValue((uri) async => opened?.add(uri)),
        reducedMotionProvider.overrideWith(() => _Motion(reduced)),
      ],
      child: MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
  await tester.pump();
}

class _Motion extends MotionPreference {
  _Motion(this.reduced);

  final bool reduced;

  @override
  bool build() => reduced;
}

LiveCheckExerciseView view(
  LiveCheckDraft draft, {
  StepStatus status = const Answering(),
  Future<List<WebSource>?> Function(int)? onLookup,
  ValueChanged<int>? onToggle,
}) => LiveCheckExerciseView(
  draft: draft,
  status: status,
  review: null,
  onChanged: (_) {},
  onToggle: onToggle ?? (_) {},
  onLookup: onLookup ?? (_) async => const [],
);

void main() {
  testWidgets('the counter turns red past the limit', (tester) async {
    final draft = LiveCheckDraft(F.liveCheck).edit('あ' * 201);

    await pump(tester, view(draft));

    expect(find.text('201 / 200 文字'), findsOneWidget);
    expect(find.byKey(const Key('live-check-too-long')), findsOneWidget);
  });

  testWidgets('while the AI answers the question is shown, calmly', (
    tester,
  ) async {
    final draft = LiveCheckDraft(F.liveCheck).edit(' 富士山の高さは？ ');

    await pump(tester, view(draft, status: const Submitting()));

    expect(find.byType(LiveCheckGenerating), findsOneWidget);
    expect(find.text('富士山の高さは？'), findsOneWidget);
    expect(find.byKey(const Key('live-check-input')), findsNothing);
    // Reduced motion: nothing is scheduled, so the tree settles at once.
    await tester.pumpAndSettle();
  });

  testWidgets('without reduced motion the magnifier moves', (tester) async {
    final draft = LiveCheckDraft(F.liveCheck).edit('富士山の高さは？');

    await pump(tester, view(draft, status: const Submitting()), reduced: false);

    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpWidget(const SizedBox()); // stops the animation
  });

  testWidgets('each sentence can be marked and looked up', (tester) async {
    final toggled = <int>[];
    final looked = <int>[];
    final draft = LiveCheckDraft(F.liveCheck).started(session);

    await pump(
      tester,
      view(
        draft,
        onToggle: toggled.add,
        onLookup: (index) async {
          looked.add(index);
          return null;
        },
      ),
    );
    await toggleAnswerSentence(tester, 'live-check', 2);
    await lookupAnswerSentence(tester, 1);
    await tester.pumpAndSettle();

    expect(toggled, [2]);
    expect(looked, [1]);
  });

  testWidgets('looked-up pages are listed under the sentence and open in a '
      'new tab', (tester) async {
    final opened = <Uri>[];
    final draft = LiveCheckDraft(F.liveCheck)
        .started(session)
        .lookingUpSentence(1)
        .lookedUp(
          LookupResponse(
            sentenceIndex: 1,
            sources: const [
              WebSource(title: 'example.jp', uri: 'https://example.jp/a'),
            ],
            lookupsLeft: 1,
          ),
        );

    await pump(tester, view(draft), opened: opened);

    expect(find.byKey(const Key('live-check-sources-1')), findsOneWidget);
    expect(find.text('確かめた出典（1 件）'), findsOneWidget);
    expect(find.byKey(const Key('live-check-lookup-1')), findsNothing);
    await tester.tap(find.byKey(const Key('web-source-0')));
    expect(opened, [Uri.parse('https://example.jp/a')]);
    expect(find.textContaining('のこり 1 回'), findsOneWidget);
  });

  testWidgets('a used-up or failed lookup says so at its sentence', (
    tester,
  ) async {
    final draft = LiveCheckDraft(F.liveCheck)
        .started(session)
        .lookupFailed(0, LookupFailure.noneLeft);

    await pump(tester, view(draft));

    expect(find.textContaining('調べる回数を使い切ったよ。'), findsOneWidget);
    expect(
      find.byKey(const Key('live-check-lookup-failure-0')),
      findsOneWidget,
    );
    await lookupAnswerSentence(tester, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a sentence without pages says so', (tester) async {
    final draft = LiveCheckDraft(F.liveCheck)
        .started(session)
        .lookingUpSentence(0)
        .lookedUp(
          LookupResponse(sentenceIndex: 0, sources: const [], lookupsLeft: 1),
        );

    await pump(tester, view(draft));

    expect(find.text('確かめた出典（0 件）'), findsOneWidget);
    expect(find.byKey(const Key('web-sources-empty')), findsOneWidget);
  });

  testWidgets('pages that are not web pages are listed but not opened', (
    tester,
  ) async {
    final opened = <Uri>[];

    await pump(
      tester,
      const WebSourceList(
        sources: [WebSource(title: '', uri: 'javascript:alert(1)')],
        emptyText: 'none',
      ),
      opened: opened,
    );
    await tester.tap(find.byKey(const Key('web-source-0')));

    expect(opened, isEmpty);
  });

  testWidgets('the feedback lists the corrections and every source', (
    tester,
  ) async {
    final draft = LiveCheckDraft(F.liveCheck).started(session).toggle(0);
    final result = LiveCheckResult(
      errors: const [
        HallucinationError(
          index: 1,
          errorType: HallucinationErrorType.number,
          correction: '正しい二文目。',
          tip: '数字を確かめよう',
        ),
      ],
      found: const [],
      missed: const [1],
      falseAlarms: const [0],
      sources: const [
        WebSource(title: 'a.jp', uri: 'https://a.jp'),
        WebSource(title: 'b.jp', uri: 'https://b.jp'),
      ],
    );
    final review = HallucinationReview.resolve(
      draft.asHallucination(),
      result.asHallucination,
    );

    await pump(
      tester,
      LiveCheckFeedbackView(correct: CorrectLiveCheck(review, result.sources)),
    );

    expect(find.text('正しくは：正しい二文目。'), findsOneWidget);
    expect(find.text('見ぬくコツ：数字を確かめよう'), findsOneWidget);
    expect(find.text('a.jp'), findsOneWidget);
    expect(find.text('b.jp'), findsOneWidget);
  });
}
