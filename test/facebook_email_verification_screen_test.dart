import 'package:coffee_customer/screens/facebook_email_verification_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeVerification implements FacebookEmailVerification {
  @override
  String? facebookEmail = 'facebook@example.test';
  String? verifiedToken;
  String? updatedEmail;
  bool emailAlreadyInUse = false;
  int facebookEmailVerificationRequests = 0;
  int reloads = 0;

  @override
  Future<void> sendVerificationToFacebookEmail() async {
    facebookEmailVerificationRequests++;
  }

  @override
  Future<void> verifyBeforeUpdatingEmail(String newEmail) async {
    if (emailAlreadyInUse) {
      throw FirebaseAuthException(code: 'email-already-in-use');
    }
    updatedEmail = newEmail;
  }

  @override
  Future<String?> reloadAndGetVerifiedIdToken() async {
    reloads++;
    return verifiedToken;
  }
}

void main() {
  testWidgets('offers Facebook email verification and waits for verification', (
    tester,
  ) async {
    final verification = _FakeVerification();
    String? submittedToken;
    await tester.pumpWidget(
      MaterialApp(
        home: FacebookEmailVerificationScreen(
          verification: verification,
          onVerified: (token) async {
            submittedToken = token;
          },
        ),
      ),
    );

    await tester.tap(find.text('Verify Facebook email'));
    await tester.pumpAndSettle();
    expect(verification.facebookEmailVerificationRequests, 1);
    expect(
      find.text(
        'We sent a verification link. Open it, then return to this app.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text("I've verified my email"));
    await tester.pumpAndSettle();
    expect(verification.reloads, 1);
    expect(submittedToken, isNull);
    expect(
      find.text(
        'Email verification is not complete yet. Open the link and try again.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'verifies an alternate email then retries with a fresh ID token',
    (tester) async {
      final verification = _FakeVerification();
      String? submittedToken;
      await tester.pumpWidget(
        MaterialApp(
          home: FacebookEmailVerificationScreen(
            verification: verification,
            onVerified: (token) async {
              submittedToken = token;
            },
          ),
        ),
      );

      await tester.tap(find.text('Use another email address'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField),
        'alternate@example.test',
      );
      await tester.tap(find.text('Send verification'));
      await tester.pumpAndSettle();
      expect(verification.updatedEmail, 'alternate@example.test');
      expect(
        find.text(
          'We sent a verification link. Verify the new address, then return to this app.',
        ),
        findsOneWidget,
      );

      verification.verifiedToken = 'fresh-verified-firebase-id-token';
      await tester.tap(find.text("I've verified my email"));
      await tester.pumpAndSettle();
      expect(verification.reloads, 1);
      expect(submittedToken, 'fresh-verified-firebase-id-token');
    },
  );

  testWidgets('does not continue when alternate email is already in use', (
    tester,
  ) async {
    final verification = _FakeVerification()..emailAlreadyInUse = true;
    var continued = false;
    await tester.pumpWidget(
      MaterialApp(
        home: FacebookEmailVerificationScreen(
          verification: verification,
          onVerified: (_) async {
            continued = true;
          },
        ),
      ),
    );

    await tester.tap(find.text('Use another email address'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'taken@example.test');
    await tester.tap(find.text('Send verification'));
    await tester.pumpAndSettle();

    expect(verification.updatedEmail, isNull);
    expect(
      find.text(
        'That email cannot be used for this account. Try another address or contact support.',
      ),
      findsOneWidget,
    );
    expect(continued, isFalse);
  });

  testWidgets('canceling alternate-email entry does not change the account', (
    tester,
  ) async {
    final verification = _FakeVerification();
    await tester.pumpWidget(
      MaterialApp(
        home: FacebookEmailVerificationScreen(
          verification: verification,
          onVerified: (_) async {},
        ),
      ),
    );

    await tester.tap(find.text('Use another email address'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(verification.updatedEmail, isNull);
    expect(verification.reloads, 0);
  });
}
