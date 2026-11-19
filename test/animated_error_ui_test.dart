import 'dart:typed_data';

import 'package:coffee_customer/core/api.dart';
import 'package:coffee_customer/core/error_ui.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StatusAdapter implements HttpClientAdapter {
  _StatusAdapter(this.status, {this.body});

  final int status;
  final Object? body;
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
        statusCode: status,
        data: body ?? {'message': 'Private backend detail'},
      ),
      type: DioExceptionType.badResponse,
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late HttpClientAdapter previousAdapter;

  setUp(() {
    previousAdapter = Api.I.httpClientAdapterForTesting;
    Api.I.onHttp402 = null;
    Api.I.recoveryRetryDelaysForTesting = const [];
    Api.I.connectionRecoveryActive.value = false;
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    Api.I.onHttp402 = null;
    Api.I.httpClientAdapterForTesting = previousAdapter;
    Api.I.recoveryRetryDelaysForTesting = const [
      Duration(seconds: 1),
      Duration(seconds: 3),
      Duration(seconds: 5),
      Duration(seconds: 5),
      Duration(seconds: 5),
    ];
  });

  for (final status in <int>[
    400,
    401,
    403,
    404,
    405,
    408,
    409,
    413,
    419,
    422,
    429,
    500,
    502,
    503,
    504,
  ]) {
    test(
      'HTTP $status maps to a safe, coded API error without retry',
      () async {
        final adapter = _StatusAdapter(status);
        Api.I.httpClientAdapterForTesting = adapter;

        ApiException? caught;
        try {
          await Api.I.products();
        } on ApiException catch (error) {
          caught = error;
        }

        expect(caught, isNotNull);
        expect(caught!.statusCode, status);
        expect(caught.title, isNotEmpty);
        expect(caught.instruction, isNotEmpty);
        expect(caught.displayMessage, startsWith('HTTP $status'));
        if (![400, 409, 422].contains(status)) {
          expect(caught.message, isNot(contains('Private backend detail')));
        }
        expect(adapter.requests, 1);
      },
    );
  }

  test(
    '422 surfaces a validation message rather than backend internals',
    () async {
      Api.I.httpClientAdapterForTesting = _StatusAdapter(
        422,
        body: {
          'message': 'The given data was invalid.',
          'errors': {
            'email': ['Enter a valid email address.'],
          },
        },
      );

      ApiException? caught;
      try {
        await Api.I.products();
      } on ApiException catch (error) {
        caught = error;
      }

      expect(caught?.statusCode, 422);
      expect(caught?.message, 'Enter a valid email address.');
    },
  );

  testWidgets('error state stops loading animation and offers recovery', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: KjmErrorState(
            statusCode: 503,
            title: 'Service unavailable',
            message: 'Please try again shortly.',
            onRetry: _noop,
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
    expect(find.text('Refresh'), findsOneWidget);
    expect(find.text('Go Back'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('loading view uses only the rotating logo and compact label', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: KjmLoadingView(
            message: 'Loading orders',
            connectionRecovery: true,
          ),
        ),
      ),
    );
    expect(find.text('Loading...'), findsOneWidget);
    expect(find.text('Please wait while we load your page.'), findsNothing);
    expect(find.byType(Card), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName == 'assets/images/logo1.png',
      ),
      findsOneWidget,
    );
    final rotationFinder = find.descendant(
      of: find.byType(KjmLoadingView),
      matching: find.byType(RotationTransition),
    );
    expect(rotationFinder, findsOneWidget);
    expect(find.byIcon(Icons.coffee), findsNothing);
    final rotation = tester.widget<RotationTransition>(rotationFinder);
    final initialTurn = rotation.turns.value;
    await tester.pump(const Duration(milliseconds: 450));
    expect(rotation.turns.value, greaterThan(initialTurn));

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Done'))),
    );
    expect(
      find.descendant(
        of: find.byType(KjmLoadingView),
        matching: find.byType(RotationTransition),
      ),
      findsNothing,
    );
    expect(tester.binding.transientCallbackCount, 0);
  });
}

void _noop() {}
