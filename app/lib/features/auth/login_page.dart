import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../design/welcome_frame.dart';
import '../../data/repositories.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  bool _busy = false;

  /// The router moves on by itself once the auth state changes.
  Future<void> _run(Future<SignInOutcome> Function() signIn) async {
    setState(() => _busy = true);
    try {
      final outcome = await signIn();
      if (outcome == SignInOutcome.cancelled && mounted) {
        _showMessage('ログインをキャンセルしました');
      }
    } catch (error) {
      // Recoverable here: the user can simply try again.
      debugPrint('Sign-in failed: $error');
      if (mounted) {
        _showMessage('ログインできませんでした。もう一度試してね');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authRepositoryProvider);
    return WelcomeFrame(
      title: 'AIと、できることを\nひとつずつ。',
      description: '1日5分、自分で考えて試すレッスン。\n知ることから、つくることへ進もう。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('学びのつづきを、ここから', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          const Text('アカウントで記録を残すか、ゲストで気軽に体験できます。'),
          const SizedBox(height: 32),
          FilledButton.icon(
            key: const Key('login-google'),
            onPressed: _busy ? null : () => _run(auth.signInWithGoogle),
            icon: const Icon(Icons.login),
            label: const Text('Google でログイン'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            key: const Key('login-guest'),
            onPressed: _busy
                ? null
                : () => _run(() async {
                    await auth.signInAnonymously();
                    return SignInOutcome.signedIn;
                  }),
            child: const Text('ゲストではじめる'),
          ),
          const SizedBox(height: 20),
          const Text(
            'ゲストの記録は、ログアウトすると引き継げなくなります',
            style: TextStyle(fontSize: 14, height: 1.6),
          ),
          if (_busy) ...[
            const SizedBox(height: 24),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
    );
  }
}
