import 'dart:typed_data';

import 'package:coffee_customer/core/api.dart';
import 'package:coffee_customer/screens/auth_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _LoginSecurityAdapter implements HttpClientAdapter {
  _LoginSecurityAdapter(this.security);

  final Map<String, dynamic> security;
  int requests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    throw DioException(
      requestOptions: options,
      response: Response<dynamic>(
        requestOptions: options,
        statusCode: 429,
        data: {
          'success': false,
          'message': security['status'] == 'locked'
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

  tearDown(() {
    Api.I.httpClientAdapterForTesting = previousAdapter;
  });

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

  testWidgets('lockout response shows remaining time and disables login', (
    tester,
  ) async {
    final adapter = _LoginSecurityAdapter({
      'status': 'locked',
      'retry_after_seconds': 10,
      'locked_until': '2026-11-20T10:00:10+00:00',
      'password_reset_required': false,
    });
    Api.I.httpClientAdapterForTesting = adapter;

    await submitLogin(tester);
    expect(find.textContaining('00:10'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Log In'))
          .onPressed,
      isNull,
    );
    expect(adapter.requests, 1);

    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('00:09'), findsOneWidget);
    expect(adapter.requests, 1);
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
