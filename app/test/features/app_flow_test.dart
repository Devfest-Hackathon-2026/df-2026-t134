import 'package:ailearn/data/repositories.dart';
import 'package:ailearn/models/user_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

const googleUser = AppUser(uid: 'google-user', isAnonymous: false);

FakeContentRepository sampleContent() => FakeContentRepository(
  units: [unit('u1', 1, title: 'AI ってなに？')],
  lessons: [
    lesson('u1-l2', 'u1', 2, title: '得意と不得意'),
    lesson('u1-l1', 'u1', 1, title: 'AI は予測マシン'),
  ],
  exercises: [
    choiceExercise('u1-l1-q1', 'u1-l1'),
    choiceExercise('u1-l2-q1', 'u1-l2'),
  ],
);

void main() {
  group('login', () {
    testWidgets('signed-out users land on the login screen', (tester) async {
      await tester.pumpWidget(buildTestApp(auth: FakeAuthRepository()));
      await tester.pumpAndSettle();

      expect(find.text('Google でログイン'), findsOneWidget);
      expect(find.text('ゲストではじめる'), findsOneWidget);
    });

    testWidgets('guest sign-in without a profile goes to onboarding', (
      tester,
    ) async {
      final auth = FakeAuthRepository();
      await tester.pumpWidget(buildTestApp(auth: auth));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('login-guest')));
      await tester.pumpAndSettle();

      expect(auth.anonymousCalls, 1);
      expect(find.text('はじめまして！'), findsOneWidget);
    });

    testWidgets('Google sign-in with a profile goes to the path', (
      tester,
    ) async {
      final auth = FakeAuthRepository();
      await tester.pumpWidget(
        buildTestApp(
          auth: auth,
          profiles: FakeProfileRepository({'google-user': sampleProfile}),
          content: sampleContent(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('login-google')));
      await tester.pumpAndSettle();

      expect(auth.googleCalls, 1);
      expect(find.text('学習パス'), findsOneWidget);
    });

    testWidgets('closing the Google popup keeps the user on login', (
      tester,
    ) async {
      final auth = FakeAuthRepository()
        ..googleOutcome = SignInOutcome.cancelled;
      await tester.pumpWidget(buildTestApp(auth: auth));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('login-google')));
      await tester.pumpAndSettle();

      expect(find.text('ログインをキャンセルしました'), findsOneWidget);
      expect(find.text('Google でログイン'), findsOneWidget);
    });

    testWidgets('a sign-in error is shown and can be retried', (tester) async {
      final auth = FakeAuthRepository()..signInError = Exception('network');
      await tester.pumpWidget(buildTestApp(auth: auth));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('login-guest')));
      await tester.pumpAndSettle();

      expect(find.text('ログインできませんでした。もう一度試してね'), findsOneWidget);
      final guest = tester.widget<OutlinedButton>(
        find.byKey(const Key('login-guest')),
      );
      expect(guest.onPressed, isNotNull);
    });
  });

  group('onboarding', () {
    testWidgets('validates the nickname and grade, then creates the profile', (
      tester,
    ) async {
      final profiles = FakeProfileRepository();
      await tester.pumpWidget(
        buildTestApp(
          auth: FakeAuthRepository(initialUser: googleUser),
          profiles: profiles,
          content: sampleContent(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('はじめまして！'), findsOneWidget);
      expect(find.textContaining('本名は使わないでね'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('onboarding-submit')));
      await tester.tap(find.byKey(const Key('onboarding-submit')));
      await tester.pump();
      expect(find.text('ニックネームを入力してね'), findsOneWidget);
      expect(find.text('学年を選んでね'), findsOneWidget);
      expect(profiles.created, isEmpty);

      await tester.enterText(
        find.byKey(const Key('onboarding-nickname')),
        '  ひかり  ',
      );
      await tester.ensureVisible(find.byKey(const Key('onboarding-grade-h1')));
      await tester.tap(find.byKey(const Key('onboarding-grade-h1')));
      await tester.ensureVisible(find.byKey(const Key('onboarding-submit')));
      await tester.tap(find.byKey(const Key('onboarding-submit')));
      await tester.pumpAndSettle();

      final (uid, draft) = profiles.created.single;
      expect(uid, 'google-user');
      expect(draft.displayName, 'ひかり');
      expect(draft.grade, Grade.h1);
      expect(find.text('学習パス'), findsOneWidget);
      expect(find.text('こんにちは、ひかり さん！'), findsOneWidget);
    });

    testWidgets('a failed save is reported and the form stays', (tester) async {
      final profiles = FakeProfileRepository()
        ..createError = Exception('permission-denied');
      await tester.pumpWidget(
        buildTestApp(
          auth: FakeAuthRepository(initialUser: googleUser),
          profiles: profiles,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('onboarding-nickname')),
        'ひかり',
      );
      await tester.tap(find.byKey(const Key('onboarding-grade-j1')));
      await tester.ensureVisible(find.byKey(const Key('onboarding-submit')));
      await tester.tap(find.byKey(const Key('onboarding-submit')));
      await tester.pumpAndSettle();

      expect(find.text('保存できませんでした。もう一度試してね'), findsOneWidget);
      expect(find.text('はじめまして！'), findsOneWidget);
    });

    testWidgets('signing out from onboarding goes back to login', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestApp(auth: FakeAuthRepository(initialUser: googleUser)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('ログアウト'));
      await tester.pumpAndSettle();

      expect(find.text('Google でログイン'), findsOneWidget);
    });
  });

  group('learning path', () {
    Widget readyApp({
      FakeContentRepository? content,
      FakeProgressRepository? progress,
      FakeAuthRepository? auth,
    }) => buildTestApp(
      auth: auth ?? FakeAuthRepository(initialUser: googleUser),
      profiles: FakeProfileRepository({'google-user': sampleProfile}),
      content: content ?? sampleContent(),
      progress: progress,
    );

    testWidgets(
      'a new user sees the first lesson unlocked and the rest locked',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(readyApp());
        await tester.pumpAndSettle();

        expect(find.text('AI ってなに？'), findsOneWidget);
        expect(find.byKey(const Key('lesson-u1-l1-unlocked')), findsOneWidget);
        expect(find.byKey(const Key('lesson-u1-l2-locked')), findsOneWidget);
        expect(find.text('ここから！'), findsOneWidget);
        expect(find.text('0 XP'), findsOneWidget);
        expect(
          find.bySemanticsLabel('ここから！ AI は予測マシン（挑戦できます）'),
          findsOneWidget,
        );
        semantics.dispose();
      },
    );

    testWidgets('completed lessons are marked and unlock the next one', (
      tester,
    ) async {
      await tester.pumpWidget(
        readyApp(
          progress: FakeProgressRepository({
            'google-user': progressWith({'u1-l1'}, xp: 40),
          }),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('lesson-u1-l1-completed')), findsOneWidget);
      expect(find.byKey(const Key('lesson-u1-l2-unlocked')), findsOneWidget);
      expect(find.text('40 XP'), findsOneWidget);
    });

    testWidgets('tapping a locked lesson explains how to unlock it', (
      tester,
    ) async {
      await tester.pumpWidget(readyApp());
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('lesson-u1-l2-locked')));
      await tester.tap(find.byKey(const Key('lesson-u1-l2-locked')));
      await tester.pump();

      expect(find.text('前のレッスンをクリアするとひらきます'), findsOneWidget);
      expect(find.byKey(const Key('lesson-intro')), findsNothing);
    });

    testWidgets('tapping an unlocked lesson opens /lessons/:lessonId', (
      tester,
    ) async {
      await tester.pumpWidget(readyApp());
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const Key('lesson-u1-l1-unlocked')),
      );
      await tester.tap(find.byKey(const Key('lesson-u1-l1-unlocked')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('path-start-lesson')));
      await tester.tap(find.byKey(const Key('path-start-lesson')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('lesson-intro')), findsOneWidget);
      expect(find.text('AI は予測マシン'), findsOneWidget);
      expect(find.text('ぜんぶで 1 もん'), findsOneWidget);

      await tester.tap(find.byKey(const Key('lesson-close')));
      await tester.pumpAndSettle();
      expect(find.text('学習パス'), findsOneWidget);
    });

    testWidgets('shows a friendly message when there is no content', (
      tester,
    ) async {
      await tester.pumpWidget(readyApp(content: FakeContentRepository()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('path-empty')), findsOneWidget);
    });

    testWidgets('inconsistent content shows an error with a retry', (
      tester,
    ) async {
      final content = FakeContentRepository(
        units: [unit('u1', 1)],
        lessons: [lesson('u9-l1', 'u9', 1)],
      );
      await tester.pumpWidget(readyApp(content: content));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('path-error')), findsOneWidget);

      content.lessons = [lesson('u1-l1', 'u1', 1)];
      await tester.tap(find.text('もう一度試す'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('lesson-u1-l1-unlocked')), findsOneWidget);
    });

    testWidgets('signing out from the menu goes back to login', (tester) async {
      await tester.pumpWidget(readyApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('path-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('path-sign-out')));
      await tester.pumpAndSettle();

      expect(find.text('Google でログイン'), findsOneWidget);
    });

    testWidgets('a malformed profile is shown on the startup page', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestApp(
          auth: FakeAuthRepository(initialUser: googleUser),
          profiles: _FailingProfiles(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('startup-error')), findsOneWidget);
    });
  });
}

class _FailingProfiles extends FakeProfileRepository {
  @override
  Stream<UserProfile?> watchProfile(String uid) =>
      Stream.error(const FormatException('UserProfile.grade'));
}
