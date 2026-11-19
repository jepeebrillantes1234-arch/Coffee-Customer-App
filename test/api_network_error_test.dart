import 'dart:typed_data';

import 'package:coffee_customer/core/api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _NetworkFailureAdapter implements HttpClientAdapter {
  _NetworkFailureAdapter(this.type);

  final DioExceptionType type;
  int requests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    throw DioException(requestOptions: options, type: type);
  }

  @override
  void close({bool force = false}) {}
}

class _SequenceAdapter implements HttpClientAdapter {
  _SequenceAdapter(this.statuses);

  final List<int> statuses;
  int requests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final status = statuses[requests.clamp(0, statuses.length - 1)];
    requests++;
    if (status >= 400) {
      throw DioException(
        requestOptions: options,
        response: Response<dynamic>(
          requestOptions: options,
          statusCode: status,
          data: {'message': 'Mock HTTP $status'},
        ),
        type: DioExceptionType.badResponse,
      );
    }
    return ResponseBody.fromString(
      '{"data":{"data":[]}}',
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

  setUp(() {
    previousAdapter = Api.I.httpClientAdapterForTesting;
    Api.I.onHttp402 = null;
    Api.I.connectionRecoveryActive.value = false;
    Api.I.recoveryRetryDelaysForTesting = const [];
  });

  tearDown(() {
    Api.I.httpClientAdapterForTesting = previousAdapter;
    Api.I.onHttp402 = null;
    Api.I.recoveryRetryDelaysForTesting = const [
      Duration(seconds: 1),
      Duration(seconds: 3),
      Duration(seconds: 5),
      Duration(seconds: 5),
      Duration(seconds: 5),
    ];
  });

  test(
    'network disconnection is surfaced without an automatic retry',
    () async {
      final adapter = _NetworkFailureAdapter(DioExceptionType.connectionError);
      Api.I.httpClientAdapterForTesting = adapter;

      ApiException? caught;
      try {
        await Api.I.products();
      } on ApiException catch (error) {
        caught = error;
      }

      expect(caught, isNotNull);
      expect(caught!.statusCode, isNull);
      expect(caught.retryable, isTrue);
      expect(caught.message, contains('could not reach the server'));
      expect(adapter.requests, 1);
    },
  );

  test('network timeout maps to HTTP 408 without an automatic retry', () async {
    final adapter = _NetworkFailureAdapter(DioExceptionType.receiveTimeout);
    Api.I.httpClientAdapterForTesting = adapter;

    ApiException? caught;
    try {
      await Api.I.products();
    } on ApiException catch (error) {
      caught = error;
    }

    expect(caught, isNotNull);
    expect(caught!.statusCode, 408);
    expect(caught.retryable, isFalse);
    expect(adapter.requests, 1);
  });

  test(
    'transient GET failure retries and returns once the server responds',
    () async {
      final adapter = _SequenceAdapter([503, 200]);
      Api.I.httpClientAdapterForTesting = adapter;
      Api.I.recoveryRetryDelaysForTesting = const [Duration.zero];

      final response = await Api.I.products();

      expect(response, isEmpty);
      expect(adapter.requests, 2);
      expect(Api.I.connectionRecoveryActive.value, isFalse);
    },
  );

  test(
    'transaction POST is never automatically retried after HTTP 503',
    () async {
      final adapter = _SequenceAdapter([503]);
      Api.I.httpClientAdapterForTesting = adapter;
      Api.I.recoveryRetryDelaysForTesting = const [
        Duration.zero,
        Duration.zero,
      ];

      ApiException? caught;
      try {
        await Api.I.placeOrder({});
      } on ApiException catch (error) {
        caught = error;
      }

      expect(caught?.statusCode, 503);
      expect(adapter.requests, 1);
    },
  );
}
