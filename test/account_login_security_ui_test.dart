import 'dart:convert';
import 'dart:typed_data';

import 'package:coffee_customer/core/api.dart';
import 'package:coffee_customer/screens/auth_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _LoginSecurityAdapter implements HttpClientAdapter {
  _LoginSecurityAdapter(
    this.security, {
    this.statusCode = 429,
    this.connectionFailure = false,
    this.loginStatuses,
  });

  final Map<String, dynamic> security;
  final int statusCode;
  final bool connectionFailure;
  final List<int>? loginStatuses;
  int _loginResponseIndex = 0;
  int requests = 0;
  final List<String> requestPaths = [];
  final List<dynamic> requestBodies = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    requestPaths.add(options.uri.path);
    requestBodies.add(options.data);
    if (options.path.endsWith('/auth/lockout-status')) {
      return ResponseBody.fromString(
        jsonEncode({
          'success': true,
          'data': {'security': security},
          'errors': null,
        }),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    if (connectionFailure) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: 'offline',
      );
    }
    final loginStatus = loginStatuses == null
        ? statusCode
        : loginStatuses![_loginResponseIndex < loginStatuses!.length
              ? _loginResponseIndex
              : loginStatuses!.length - 1];
    _loginResponseIndex++;
    if (loginStatus < 400) {
      return ResponseBody.fromString(
        jsonEncode({
          'success': true,
          'message': 'Logged in',
          'data': {
            'user': {'id': 7, 'name': 'Test Customer', 'role': 'customer'},
            'token': 'mock-sanctum-token',
          },
          'errors': null,
        }),
        loginStatus,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    throw DioException(
      requestOptions: options,
      response: Response<dynamic>(
        requestOptions: options,
        statusCode: loginStatus,
        data: {
          'success': false,
          'message': loginStatus == 401
              ? 'Invalid credentials'
              : security['status'] == 'locked'
              ? 'Too many failed login attempts. Please wait 5 minutes before trying again.'
              : 'A password reset is required before you can log in.',
          'data': {'security': security},
        },
      ),
      type: DioExceptionType.badResponse,
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late HttpClientAdapter previousAdapter;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    previousAdapter = Api.I.httpClientAdapterForTesting;
  });

  tearDown(() async {
    Api.I.httpClientAdapterForTesting = previousAdapter;
    await Api.I.clearLoginLockout();
  });

  test(
    'lockout status API uses login identifier and parses Laravel fields',
    () async {
      const identifier = 'customer@example.test';
      final expiry = DateTime.now().toUtc().add(const Duration(seconds: 75));
      final adapter = _LoginSecurityAdapter({
        'status': 'locked',
        'remaining_seconds': 75,
        'retry_after_seconds': 75,
        'locked_until': expiry.toIso8601String(),
        'lockout_duration_seconds': 120,
        'lockout_cycle': 2,
        'password_reset_required': false,
      });
      Api.I.httpClientAdapterForTesting = adapter;

      final state = await Api.I.checkLoginLockout(identifier);

      expect(adapter.requestPaths, ['/api/v1/auth/lockout-status']);
      expect(adapter.requestBodies.single, {'login': identifier});
      expect(state, isNotNull);
      expect(state!.identifier, identifier);
      expect(state.durationSeconds, 120);
      expect(state.cycle, 2);
      expect(state.expiresAt, expiry);
    },
  );

  Future<void> submitLogin(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(.85)),
          child: child!,
        ),
        home: const AuthScreen(),
      ),
    );
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'customer@example.test');
    await tester.enterText(fields.at(1), 'wrong-password');
    await tester.tap(find.text('Log In'));
    await tester.pumpAndSettle();
  }

  testWidgets('lockout response shows professional popup and live time', (
    tester,
  ) async {
    final expiresAt = DateTime.now().toUtc().add(const Duration(minutes: 1));
    final adapter = _LoginSecurityAdapter({
      'status': 'locked',
      'retry_after_seconds': 60,
      'lockout_duration_seconds': 60,
      'lockout_cycle': 1,
      'locked_until': expiresAt.toIso8601String(),
      'password_reset_required': false,
    });
    Api.I.httpClientAdapterForTesting = adapter;

    await submitLogin(tester);
    expect(find.text('Account Temporarily Locked'), findsOneWidget);
    expect(find.text('Too Many Failed Attempts'), findsOneWidget);
    expect(
      find.text(
        'You have entered the wrong password 3 times. Please wait for:',
      ),
      findsOneWidget,
    );
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
      tester.widget<Text>(find.byKey(const ValueKey('lockout-countdown'))).data,
      matches(RegExp(r'^00:\d{2}$')),
    );
    expect(find.text('Forgot Password?'), findsOneWidget);
    expect(find.text('OK'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Log In'))
          .onPressed,
      isNull,
    );
    expect(adapter.requests, 1);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Account Temporarily Locked'), findsOneWidget);
    expect(adapter.requests, 1);
    expect(find.text('OK'), findsNothing);
  });

  testWidgets(
    'three incorrect passwords activate lockout and disable sign-in options',
    (tester) async {
      final expiresAt = DateTime.now().toUtc().add(const Duration(minutes: 1));
      final adapter = _LoginSecurityAdapter(
        {
          'status': 'locked',
          'retry_after_seconds': 60,
          'lockout_duration_seconds': 60,
          'lockout_cycle': 1,
          'locked_until': expiresAt.toIso8601String(),
          'password_reset_required': false,
        },
        loginStatuses: [401, 401, 429],
      );
      Api.I.httpClientAdapterForTesting = adapter;

      await tester.pumpWidget(const MaterialApp(home: AuthScreen()));
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'customer@example.test');
      await tester.enterText(fields.at(1), 'wrong-password');

      for (var attempt = 1; attempt <= 3; attempt++) {
        await tester.ensureVisible(find.text('Log In'));
        await tester.tap(find.text('Log In'));
        await tester.pumpAndSettle();

        if (attempt < 3) {
          expect(find.text('Account Temporarily Locked'), findsNothing);
          expect(
            tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Log In'),
                )
                .onPressed,
            isNotNull,
          );
        }
      }

      expect(adapter.requests, 3);
      expect(find.text('Account Temporarily Locked'), findsOneWidget);
      expect(find.text('Too Many Failed Attempts'), findsOneWidget);
      expect(
        find.text(
          'You have entered the wrong password 3 times. Please wait for:',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Email, Google, and Facebook sign-in are temporarily disabled',
        ),
        findsOneWidget,
      );
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('Continue with Facebook'), findsOneWidget);
      expect(find.text('Forgot Password?'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Log In'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Continue with Google'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Continue with Facebook'),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets('saved lockout is restored after the login screen is recreated', (
    tester,
  ) async {
    final expiresAt = DateTime.now().toUtc().add(const Duration(minutes: 2));
    final adapter = _LoginSecurityAdapter({
      'status': 'locked',
      'retry_after_seconds': 120,
      'lockout_duration_seconds': 120,
      'lockout_cycle': 2,
      'locked_until': expiresAt.toIso8601String(),
      'password_reset_required': false,
    });
    Api.I.httpClientAdapterForTesting = adapter;

    await submitLogin(tester);
    expect(find.text('OK'), findsNothing);
    final saved = await Api.I.restoreLoginLockout();
    expect(saved, isNotNull);
    expect(
      saved!.expiresAt.millisecondsSinceEpoch,
      expiresAt.millisecondsSinceEpoch,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: AuthScreen(key: ValueKey('recreated-auth-screen')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Account Temporarily Locked'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Log In'))
          .onPressed,
      isNull,
    );
    expect(adapter.requests, 2);
  });

  testWidgets(
    'forgot password is accessible during lockout and return restores it',
    (tester) async {
      final expiresAt = DateTime.now().toUtc().add(const Duration(minutes: 1));
      final adapter = _LoginSecurityAdapter({
        'status': 'locked',
        'retry_after_seconds': 60,
        'locked_until': expiresAt.toIso8601String(),
        'lockout_duration_seconds': 60,
        'lockout_cycle': 1,
        'password_reset_required': false,
      });
      Api.I.httpClientAdapterForTesting = adapter;

      await submitLogin(tester);
      await tester.tap(find.text('Forgot Password?'));
      await tester.pumpAndSettle();
      expect(find.text('Forgot password'), findsOneWidget);
      await tester.tap(find.byTooltip('Back to login'));
      await tester.pumpAndSettle();
      expect(find.text('Account Temporarily Locked'), findsOneWidget);
      expect(adapter.requests, 2);
    },
  );

  testWidgets(
    'incorrect credentials show a friendly message without status codes',
    (tester) async {
      Api.I.httpClientAdapterForTesting = _LoginSecurityAdapter(const {
        'status': 'invalid',
      }, statusCode: 401);

      await submitLogin(tester);
      expect(
        find.text(
          'Incorrect username or password. Please check your credentials and try again.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('HTTP'), findsNothing);
      expect(find.textContaining('401'), findsNothing);
    },
  );

  testWidgets('empty username and password show field validation messages', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AuthScreen()));
    await tester.tap(find.text('Log In'));
    await tester.pumpAndSettle();
    expect(find.text('Please enter your username.'), findsOneWidget);
    expect(find.text('Please enter your password.'), findsOneWidget);
  });

  testWidgets('server errors show a friendly message without HTTP details', (
    tester,
  ) async {
    Api.I.httpClientAdapterForTesting = _LoginSecurityAdapter(const {
      'status': 'server_error',
    }, statusCode: 500);
    await submitLogin(tester);
    expect(
      find.text('Something went wrong. Please try again later.'),
      findsOneWidget,
    );
    expect(find.textContaining('500'), findsNothing);
  });

  testWidgets('connection failures show a friendly connection message', (
    tester,
  ) async {
    Api.I.httpClientAdapterForTesting = _LoginSecurityAdapter(
      const {},
      connectionFailure: true,
    );
    await submitLogin(tester);
    expect(
      find.text('Unable to connect to the server. Please try again later.'),
      findsOneWidget,
    );
    expect(find.textContaining('Dio'), findsNothing);
  });

  testWidgets('expired saved lockout restores the login form', (tester) async {
    Api.I.httpClientAdapterForTesting = _LoginSecurityAdapter(const {
      'status': 'available',
      'retry_after_seconds': 0,
      'locked_until': null,
      'lockout_duration_seconds': 0,
      'lockout_cycle': 0,
    });
    await Api.I.saveLoginLockout(
      LoginLockoutState(
        identifier: 'customer@example.test',
        expiresAt: DateTime.now().toUtc().add(const Duration(seconds: 2)),
      ),
    );
    await tester.pumpWidget(const MaterialApp(home: AuthScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Account Temporarily Locked'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Log In'))
          .onPressed,
      isNotNull,
    );
  });

  test('successful API login still stores the Sanctum token', () async {
    Api.I.httpClientAdapterForTesting = _LoginSecurityAdapter(
      const {},
      statusCode: 200,
    );
    await Api.I.login('customer@example.test', 'correct-password');
    expect(Api.I.loggedIn, isTrue);
    expect(Api.I.role, 'customer');
    expect(Api.I.accessToken, 'mock-sanctum-token');
    await Api.I.logout();
  });

  testWidgets('forced reset response offers reset and blocks login', (
    tester,
  ) async {
    final adapter = _LoginSecurityAdapter({
      'status': 'password_reset_required',
      'retry_after_seconds': 0,
      'locked_until': null,
      'password_reset_required': true,
    });
    Api.I.httpClientAdapterForTesting = adapter;

    await submitLogin(tester);
    expect(find.text('Reset password'), findsOneWidget);
    expect(find.textContaining('Reset your password'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Log In'))
          .onPressed,
      isNull,
    );
    expect(adapter.requests, 1);
  });
}
