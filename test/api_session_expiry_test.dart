import 'dart:typed_data';

import 'package:coffee_customer/core/api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FailureAdapter implements HttpClientAdapter {
  _FailureAdapter.httpStatus(this.status) : networkFailure = null;
  _FailureAdapter.network(this.networkFailure) : status = null;

  final int? status;
  final DioExceptionType? networkFailure;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (networkFailure != null) {
      throw DioException(requestOptions: options, type: networkFailure!);
    }
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.badResponse,
      response: Response<dynamic>(
        requestOptions: options,
        statusCode: status,
        data: {'message': 'Unauthenticated.'},
      ),
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late HttpClientAdapter previousAdapter;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    previousAdapter = Api.I.httpClientAdapterForTesting;
    Api.I.onSessionExpired = null;
    SharedPreferences.setMockInitialValues({
      'token': 'revoked-token',
      'user_name': 'Test Customer',
      'user_email': 'customer@example.test',
      'user_role': 'customer',
    });
    await Api.I.init();
  });

  tearDown(() {
    Api.I.onSessionExpired = null;
    Api.I.httpClientAdapterForTesting = previousAdapter;
  });

  test(
    'revoked-token 401 clears local credentials and notifies once',
    () async {
      final adapter = _FailureAdapter.httpStatus(401);
      var expiryNotifications = 0;
      Api.I.httpClientAdapterForTesting = adapter;
      Api.I.onSessionExpired = () async {
        expiryNotifications++;
      };

      await expectLater(Api.I.refreshProfile(), throwsA(isA<ApiException>()));

      expect(Api.I.loggedIn, isFalse);
      expect(Api.I.user, isNull);
      expect(expiryNotifications, 1);
      expect(
        (await SharedPreferences.getInstance()).getString('token'),
        isNull,
      );
    },
  );

  test(
    'temporary network failure does not clear credentials or expire session',
    () async {
      final adapter = _FailureAdapter.network(DioExceptionType.connectionError);
      var expiryNotifications = 0;
      Api.I.httpClientAdapterForTesting = adapter;
      Api.I.onSessionExpired = () async {
        expiryNotifications++;
      };

      await expectLater(Api.I.refreshProfile(), throwsA(isA<ApiException>()));

      expect(Api.I.loggedIn, isTrue);
      expect(expiryNotifications, 0);
      expect(
        (await SharedPreferences.getInstance()).getString('token'),
        'revoked-token',
      );
    },
  );
}
