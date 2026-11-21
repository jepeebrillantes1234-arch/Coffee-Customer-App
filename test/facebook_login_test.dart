import 'dart:convert';
import 'dart:typed_data';

import 'package:coffee_customer/core/api.dart';
import 'package:coffee_customer/screens/auth_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FirebaseLoginAdapter implements HttpClientAdapter {
  _FirebaseLoginAdapter({this.status = 200, this.responseBody});

  final int status;
  final Map<String, dynamic>? responseBody;
  int requests = 0;
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    lastRequest = options;
    final body =
        responseBody ??
        {
          'success': true,
          'message': 'Logged in with Firebase',
          'data': {
            'user': {'id': 31, 'name': 'Facebook Customer', 'role': 'customer'},
            'token': 'mock-facebook-sanctum-token',
          },
          'errors': null,
        };
    if (status >= 400) {
      throw DioException(
        requestOptions: options,
        response: Response<dynamic>(
          requestOptions: options,
          statusCode: status,
          data: body,
        ),
        type: DioExceptionType.badResponse,
      );
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late HttpClientAdapter previousAdapter;
  late Future<void> Function()? previousAuthenticatedCallback;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    previousAdapter = Api.I.httpClientAdapterForTesting;
    previousAuthenticatedCallback = Api.I.onAuthenticated;
  });

  tearDown(() {
    Api.I.httpClientAdapterForTesting = previousAdapter;
    Api.I.onAuthenticated = previousAuthenticatedCallback;
  });

  test('Google login keeps its existing Firebase endpoint payload', () async {
    final adapter = _FirebaseLoginAdapter();
    Api.I.httpClientAdapterForTesting = adapter;

    await Api.I.loginWithGoogle('firebase-google-id-token');

    expect(adapter.requests, 1);
    expect(adapter.lastRequest?.uri.path, endsWith('/auth/google'));
    expect(adapter.lastRequest?.data, {
      'id_token': 'firebase-google-id-token',
      'device_name': 'kjm-google-app',
    });
  });

  test(
    'Facebook Firebase token uses existing backend and Sanctum persistence',
    () async {
      final adapter = _FirebaseLoginAdapter();
      var authenticatedCallbackCount = 0;
      Api.I.httpClientAdapterForTesting = adapter;
      Api.I.onAuthenticated = () async => authenticatedCallbackCount++;

      await Api.I.loginWithFacebook('firebase-facebook-id-token');
      await Future<void>.delayed(Duration.zero);

      expect(adapter.requests, 1);
      expect(adapter.lastRequest?.uri.path, endsWith('/auth/google'));
      expect(adapter.lastRequest?.data, {
        'id_token': 'firebase-facebook-id-token',
        'device_name': 'kjm-facebook-app',
        'provider': 'facebook',
      });
      expect(Api.I.loggedIn, isTrue);
      expect(Api.I.accessToken, 'mock-facebook-sanctum-token');
      expect(Api.I.role, 'customer');
      expect(authenticatedCallbackCount, 1);
    },
  );

  test(
    'parses the Facebook verification recovery action from Laravel',
    () async {
      Api.I.httpClientAdapterForTesting = _FirebaseLoginAdapter(
        status: 401,
        responseBody: {
          'success': false,
          'message': 'Use a verified email before continuing.',
          'data': {'auth_action': 'facebook_email_verification_required'},
          'errors': null,
        },
      );

      ApiException? actual;
      try {
        await Api.I.loginWithFacebook('mock-id-token');
      } on ApiException catch (error) {
        actual = error;
      }

      expect(actual?.statusCode, 401);
      expect(actual?.authAction, 'facebook_email_verification_required');
    },
  );

  testWidgets('Facebook sign-in action is available and invokes its handler', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    var invoked = false;
    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(facebookSignInForTesting: () async => invoked = true),
      ),
    );

    final button = find.text('Continue with Facebook');
    expect(button, findsOneWidget);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(invoked, isTrue);
  });

  testWidgets(
    'Facebook invalid-scope failure shows a clear configuration message',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: AuthScreen(
            facebookLoginResultForTesting: () async => LoginResult(
              status: LoginStatus.failed,
              message: 'Invalid Scopes: email',
            ),
          ),
        ),
      );

      final button = find.text('Continue with Facebook');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Facebook sign-in is not configured correctly. Please try another sign-in method or contact support.',
        ),
        findsOneWidget,
      );
      expect(find.text('Invalid Scopes: email'), findsNothing);
    },
  );
}
