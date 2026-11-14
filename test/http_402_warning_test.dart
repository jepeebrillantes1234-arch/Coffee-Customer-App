import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:coffee_customer/core/api.dart';
import 'package:coffee_customer/core/config.dart';
import 'package:coffee_customer/core/http_402_warning.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockAdapter implements HttpClientAdapter {
  _MockAdapter(this.statuses);

  final List<int> statuses;
  int requests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    final status = statuses[(requests - 1).clamp(0, statuses.length - 1)];
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
      jsonEncode({
        'data': {'data': []},
      }),
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
  final navigatorKey = GlobalKey<NavigatorState>();
  late HttpClientAdapter previousAdapter;

  setUp(() {
    previousAdapter = Api.I.httpClientAdapterForTesting;
    Api.I.onHttp402 = null;
  });

  tearDown(() {
    Api.I.onHttp402 = null;
    Api.I.httpClientAdapterForTesting = previousAdapter;
  });

  Future<void> mountWarning(
    WidgetTester tester, {
    required Http402RetryRequest? retryRequest,
    Uri? website,
    VoidCallback? onContact,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Http402Warning.show(
                navigatorKey: navigatorKey,
                productionWebsite: website,
                retryRequest: retryRequest,
                onContactAdministrator: onContact ?? () {},
              ),
              child: const Text('Open warning'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open warning'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'HTTP 402 shows safe retry and contact actions, no website by default',
    (tester) async {
      final adapter = _MockAdapter([402]);
      Api.I.httpClientAdapterForTesting = adapter;
      final result = Completer<Object?>();
      Api.I.onHttp402 = (retry, serverMessage) => Http402Warning.show(
        navigatorKey: navigatorKey,
        productionWebsite: null,
        retryRequest: retry,
        serverMessage: serverMessage,
        onContactAdministrator: () {},
      );

      await tester.pumpWidget(
        MaterialApp(navigatorKey: navigatorKey, home: const Scaffold()),
      );
      unawaited(
        Api.I.products().then<void>(
          (value) => result.complete(value),
          onError: (Object error, StackTrace stack) => result.complete(error),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Service requires attention'), findsOneWidget);
      expect(find.text('Server message: Mock HTTP 402'), findsOneWidget);
      expect(find.text('Retry Connection'), findsOneWidget);
      expect(find.text('Contact Administrator'), findsOneWidget);
      expect(find.text('Open Official Website'), findsNothing);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      final outcome = await tester.runAsync(() => result.future);
      expect(outcome, isA<ApiException>());
      expect((outcome as ApiException).statusCode, 402);
      expect(adapter.requests, 1);
    },
  );

  for (final status in [404, 500]) {
    testWidgets('HTTP $status does not show the HTTP 402 warning', (
      tester,
    ) async {
      final adapter = _MockAdapter([status]);
      Api.I.httpClientAdapterForTesting = adapter;
      final result = Completer<Object?>();
      await tester.pumpWidget(
        MaterialApp(navigatorKey: navigatorKey, home: const Scaffold()),
      );
      unawaited(
        Api.I.products().then<void>(
          (value) => result.complete(value),
          onError: (Object error, StackTrace stack) => result.complete(error),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Service requires attention'), findsNothing);
      final outcome = await tester.runAsync(() => result.future);
      expect(outcome, isA<ApiException>());
      expect(adapter.requests, 1);
    });
  }

  testWidgets(
    'Retry repeats only the failed GET and returns its successful response',
    (tester) async {
      final adapter = _MockAdapter([402, 200]);
      Api.I.httpClientAdapterForTesting = adapter;
      final result = Completer<Object?>();
      Api.I.onHttp402 = (retry, serverMessage) => Http402Warning.show(
        navigatorKey: navigatorKey,
        productionWebsite: null,
        retryRequest: retry,
        serverMessage: serverMessage,
        onContactAdministrator: () {},
      );

      await tester.pumpWidget(
        MaterialApp(navigatorKey: navigatorKey, home: const Scaffold()),
      );
      unawaited(
        Api.I.products().then<void>(
          (value) => result.complete(value),
          onError: (Object error, StackTrace stack) => result.complete(error),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry Connection'));
      await tester.pumpAndSettle();

      final outcome = await tester.runAsync(() => result.future);
      expect(outcome, isEmpty);
      expect(adapter.requests, 2);
      expect(find.text('Service requires attention'), findsNothing);
    },
  );

  testWidgets('HTTP 402 on checkout POST cannot be retried from the dialog', (
    tester,
  ) async {
    final adapter = _MockAdapter([402]);
    Api.I.httpClientAdapterForTesting = adapter;
    final result = Completer<Object?>();
    Api.I.onHttp402 = (retry, serverMessage) => Http402Warning.show(
      navigatorKey: navigatorKey,
      productionWebsite: null,
      retryRequest: retry,
      serverMessage: serverMessage,
      onContactAdministrator: () {},
    );

    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const Scaffold()),
    );
    unawaited(
      Api.I
          .placeOrder({})
          .then<void>(
            (value) => result.complete(value),
            onError: (Object error, StackTrace stack) => result.complete(error),
          ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Service requires attention'), findsOneWidget);
    expect(find.text('Retry Connection'), findsNothing);
    expect(adapter.requests, 1);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(() => result.future), isA<ApiException>());
    expect(adapter.requests, 1);
  });

  testWidgets(
    'failed retry displays an error and does not retry automatically',
    (tester) async {
      final adapter = _MockAdapter([402, 500]);
      Api.I.httpClientAdapterForTesting = adapter;
      final result = Completer<Object?>();
      Api.I.onHttp402 = (retry, serverMessage) => Http402Warning.show(
        navigatorKey: navigatorKey,
        productionWebsite: null,
        retryRequest: retry,
        serverMessage: serverMessage,
        onContactAdministrator: () {},
      );

      await tester.pumpWidget(
        MaterialApp(navigatorKey: navigatorKey, home: const Scaffold()),
      );
      unawaited(
        Api.I.products().then<void>(
          (value) => result.complete(value),
          onError: (Object error, StackTrace stack) => result.complete(error),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry Connection'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Retry failed:'), findsOneWidget);
      expect(adapter.requests, 2);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(await tester.runAsync(() => result.future), isA<ApiException>());
      expect(adapter.requests, 2);
    },
  );

  testWidgets(
    'official website action is shown only when an HTTPS URL is supplied',
    (tester) async {
      await mountWarning(
        tester,
        retryRequest: null,
        website: AppConfig.parseProductionWebsiteUri('https://example.org'),
      );
      expect(find.text('Open Official Website'), findsOneWidget);
      expect(find.text('Retry Connection'), findsNothing);
      expect(AppConfig.parseProductionWebsiteUri('http://example.org'), isNull);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('Contact Administrator invokes the configured support action', (
    tester,
  ) async {
    var contacted = false;
    await mountWarning(
      tester,
      retryRequest: null,
      onContact: () => contacted = true,
    );
    await tester.tap(find.text('Contact Administrator'));
    await tester.pumpAndSettle();
    expect(contacted, isTrue);
  });
}
