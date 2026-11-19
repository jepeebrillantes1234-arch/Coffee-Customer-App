import 'package:coffee_customer/core/error_ui.dart';
import 'package:coffee_customer/core/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'normal page loading uses a local spinner without the logo screen',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: KjmLoadingView())),
      );

      expect(find.text('Loading...'), findsNothing);
      expect(find.text('Please wait while we load your page.'), findsNothing);
      expect(find.byType(Card), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(KjmLoadingView),
          matching: find.byType(RotationTransition),
        ),
        findsNothing,
      );
    },
  );

  testWidgets('logo loading screen appears only during connection recovery', (
    tester,
  ) async {
    Api.I.connectionRecoveryActive.value = false;
    await tester.pumpWidget(
      MaterialApp(
        home: const Scaffold(body: Text('Dashboard')),
        builder: (context, child) => KjmConnectionRecoveryOverlay(
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Loading...'), findsNothing);

    Api.I.connectionRecoveryActive.value = true;
    await tester.pump();
    expect(find.text('Loading...'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName == 'assets/images/logo1.png',
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(KjmLoadingView),
        matching: find.byType(RotationTransition),
      ),
      findsOneWidget,
    );

    Api.I.connectionRecoveryActive.value = false;
    await tester.pump();
    expect(find.text('Loading...'), findsNothing);
    expect(find.text('Dashboard'), findsOneWidget);
  });

  testWidgets(
    'error state shows one message, status, and exactly two actions',
    (tester) async {
      var retried = false;
      var wentBack = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KjmErrorState(
              statusCode: 503,
              message: 'private response detail',
              title: 'duplicate heading',
              instruction: 'duplicate instruction',
              onRetry: () => retried = true,
              onBack: () => wentBack = true,
            ),
          ),
        ),
      );

      expect(find.text('Unable to Load Page'), findsOneWidget);
      expect(
        find.text(
          'Something went wrong while loading this page. Would you like to try again?',
        ),
        findsOneWidget,
      );
      expect(find.text('HTTP 503'), findsOneWidget);
      expect(find.text('private response detail'), findsNothing);
      expect(find.text('duplicate heading'), findsNothing);
      expect(find.text('duplicate instruction'), findsNothing);
      expect(find.text('Refresh'), findsOneWidget);
      expect(find.text('Go Back'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(KjmErrorState),
          matching: find.byType(RotationTransition),
        ),
        findsNothing,
      );

      await tester.tap(find.text('Refresh'));
      await tester.tap(find.text('Go Back'));
      expect(retried, isTrue);
      expect(wentBack, isTrue);
    },
  );

  testWidgets('inline authentication errors preserve their original message', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: KjmInlineError(message: 'Email is invalid.')),
      ),
    );

    expect(find.text('Email is invalid.'), findsOneWidget);
    expect(find.text('Unable to Load Page'), findsNothing);
    expect(find.text('Refresh'), findsNothing);
    expect(find.text('Go Back'), findsNothing);
  });
}
