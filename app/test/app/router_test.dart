import 'package:ailearn/app/router.dart';
import 'package:ailearn/data/repositories.dart';
import 'package:ailearn/features/auth/session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

const user = AppUser(uid: 'u', isAnonymous: false);

String? redirect(Session session, String location) =>
    redirectFor(session, Uri.parse(location));

void main() {
  group('loading', () {
    test('goes to /startup and remembers where the user was', () {
      expect(
        redirect(const SessionLoading(), '/lessons/u1-l1'),
        '/startup?from=%2Flessons%2Fu1-l1',
      );
      expect(redirect(const SessionLoading(), '/'), '/startup?from=%2F');
    });

    test('stays on /startup and does not remember gate pages', () {
      expect(redirect(const SessionLoading(), '/startup'), isNull);
      expect(redirect(const SessionLoading(), '/login'), '/startup');
    });

    test('errors are shown on /startup too', () {
      expect(redirect(SessionFailed(Exception('x')), '/'), '/startup?from=%2F');
    });
  });

  test('signed out always goes to /login', () {
    expect(redirect(const SignedOut(), '/'), '/login');
    expect(redirect(const SignedOut(), '/lessons/u1-l1'), '/login');
    expect(redirect(const SignedOut(), '/onboarding'), '/login');
    expect(redirect(const SignedOut(), '/login'), isNull);
  });

  test('without a profile always goes to /onboarding', () {
    expect(redirect(const NeedsProfile(user), '/'), '/onboarding');
    expect(redirect(const NeedsProfile(user), '/login'), '/onboarding');
    expect(redirect(const NeedsProfile(user), '/onboarding'), isNull);
  });

  group('ready', () {
    final ready = Ready(user, sampleProfile);

    test('leaves gate pages for the path', () {
      expect(redirect(ready, '/login'), '/');
      expect(redirect(ready, '/onboarding'), '/');
      expect(redirect(ready, '/startup'), '/');
    });

    test('returns to the remembered in-app location', () {
      expect(
        redirect(ready, '/startup?from=%2Flessons%2Fu1-l1'),
        '/lessons/u1-l1',
      );
    });

    test('ignores remembered locations that leave the app or loop', () {
      expect(redirect(ready, '/startup?from=https%3A%2F%2Fevil.example'), '/');
      expect(redirect(ready, '/startup?from=%2F%2Fevil.example'), '/');
      expect(redirect(ready, '/startup?from=%2Flogin'), '/');
    });

    test('stays on app pages', () {
      expect(redirect(ready, '/'), isNull);
      expect(redirect(ready, '/lessons/u1-l1'), isNull);
    });
  });
}
