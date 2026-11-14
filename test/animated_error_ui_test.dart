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
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    Api.I.onHttp402 = null;
    Api.I.httpClientAdapterForTesting = previousAdapter;
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

  testWidgets('error state gives a readable code and rotating feedback', (
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

    expect(find.text('503'), findsOneWidget);
    expect(find.text('Service unavailable'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    final rotation = tester.widget<RotationTransition>(
      find.byType(RotationTransition).first,
    );
    final before = rotation.turns.value;
    await tester.pump(const Duration(milliseconds: 200));
    final after = tester
        .widget<RotationTransition>(find.byType(RotationTransition).first)
        .turns
        .value;
    expect(after, isNot(before));
  });

  testWidgets('loading view announces progress and displays a real spinner', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: KjmLoadingView(message: 'Loading orders…')),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Loading orders…'), findsOneWidget);
  });
}

void _noop() {}
