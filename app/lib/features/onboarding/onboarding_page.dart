import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../design/welcome_frame.dart';
import '../../models/user_profile.dart';
import '../auth/session.dart';

/// Asks a new user for a nickname and school year, then creates `users/{uid}`.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _nickname = TextEditingController();
  Grade? _grade;
  NicknameProblem? _nicknameProblem;
  bool _showGradeError = false;
  bool _saving = false;

  @override
  void dispose() {
    _nickname.dispose();
    super.dispose();
  }

  Future<void> _submit(String uid) async {
    final problem = checkNickname(_nickname.text);
    final grade = _grade;
    setState(() {
      _nicknameProblem = problem;
      _showGradeError = grade == null;
    });
    if (problem != null || grade == null) {
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(profileRepositoryProvider)
          .createProfile(
            uid,
            ProfileDraft(displayName: _nickname.text, grade: grade),
          );
      // The profile stream now emits the new document and the router moves on.
    } catch (error) {
      // Recoverable here: the user can submit again.
      debugPrint('Creating the profile failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('保存できませんでした。もう一度試してね')));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  String? get _nicknameErrorText => switch (_nicknameProblem) {
    NicknameProblem.empty => 'ニックネームを入力してね',
    NicknameProblem.tooLong => '$nicknameMaxLength 文字以内にしてね',
    null => null,
  };

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    if (session is! NeedsProfile) {
      // The router is about to leave this page.
      return const Scaffold(body: SizedBox.shrink());
    }
    final theme = Theme.of(context);
    return WelcomeFrame(
      title: 'はじめまして！',
      description: 'あなたのペースで、少しずつ。\nまずは学びの準備をしよう。',
      actions: [
        TextButton(
          onPressed: _saving
              ? null
              : () => ref.read(authRepositoryProvider).signOut(),
          child: const Text('ログアウト'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'あなたのことを少しだけ教えてね',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            key: const Key('onboarding-nickname'),
            controller: _nickname,
            maxLength: nicknameMaxLength,
            enabled: !_saving,
            decoration: InputDecoration(
              labelText: 'ニックネーム',
              helperText: '本名は使わないでね。アプリの中で表示される名前です',
              helperMaxLines: 4,
              errorText: _nicknameErrorText,
            ),
          ),
          const SizedBox(height: 24),
          Text('学年', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final grade in Grade.values)
                ChoiceChip(
                  key: Key('onboarding-grade-${grade.code}'),
                  label: Text(grade.label),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
                  selected: _grade == grade,
                  onSelected: _saving
                      ? null
                      : (_) => setState(() {
                          _grade = grade;
                          _showGradeError = false;
                        }),
                ),
            ],
          ),
          if (_showGradeError) ...[
            const SizedBox(height: 8),
            Text('学年を選んでね', style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 32),
          FilledButton(
            key: const Key('onboarding-submit'),
            onPressed: _saving ? null : () => _submit(session.user.uid),
            child: _saving
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  )
                : const Text('はじめる'),
          ),
        ],
      ),
    );
  }
}
