import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'util.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final String title;
  final String instruction;
  final bool retryable;
  final String? securityStatus;
  final int? retryAfterSeconds;
  final DateTime? lockedUntil;
  final int? lockoutDurationSeconds;
  final int? lockoutCycle;
  final bool passwordResetRequired;
  final String? authAction;

  ApiException(
    this.message, {
    this.statusCode,
    this.title = 'Something went wrong',
    this.instruction =
        'Please try again. If the problem continues, contact support.',
    this.retryable = false,
    this.securityStatus,
    this.retryAfterSeconds,
    this.lockedUntil,
    this.lockoutDurationSeconds,
    this.lockoutCycle,
    this.passwordResetRequired = false,
    this.authAction,
  });

  String get displayCode => statusCode?.toString() ?? 'N/A';
  String get displayMessage =>
      statusCode == null ? message : 'HTTP $statusCode: $message';

  @override
  String toString() => message;
}

class LoginLockoutState {
  const LoginLockoutState({
    required this.identifier,
    required this.expiresAt,
    this.durationSeconds = 0,
    this.cycle = 0,
  });

  final String identifier;
  final DateTime expiresAt;
  final int durationSeconds;
  final int cycle;
}

class Api {
  Api._();
  static final Api I = Api._();

  static const _lockoutUntilKey = 'login_lockout_until_ms';
  static const _lockoutIdentifierKey = 'login_lockout_identifier';
  static const _lockoutDurationKey = 'login_lockout_duration_seconds';
  static const _lockoutCycleKey = 'login_lockout_cycle';

  Future<void> saveLoginLockout(LoginLockoutState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _lockoutUntilKey,
      state.expiresAt.toUtc().millisecondsSinceEpoch,
    );
    await prefs.setString(_lockoutIdentifierKey, state.identifier);
    await prefs.setInt(_lockoutDurationKey, state.durationSeconds);
    await prefs.setInt(_lockoutCycleKey, state.cycle);
  }

  Future<LoginLockoutState?> restoreLoginLockout() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt(_lockoutUntilKey);
    if (timestamp == null) return null;
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(
      timestamp,
      isUtc: true,
    );
    if (!expiresAt.isAfter(DateTime.now().toUtc())) {
      await clearLoginLockout();
      return null;
    }
    return LoginLockoutState(
      identifier: prefs.getString(_lockoutIdentifierKey) ?? '',
      expiresAt: expiresAt,
      durationSeconds: prefs.getInt(_lockoutDurationKey) ?? 0,
      cycle: prefs.getInt(_lockoutCycleKey) ?? 0,
    );
  }

  Future<void> clearLoginLockout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lockoutUntilKey);
    await prefs.remove(_lockoutIdentifierKey);
    await prefs.remove(_lockoutDurationKey);
    await prefs.remove(_lockoutCycleKey);
  }

  /// Checks the anonymous server-side lockout state without attempting login.
  /// Laravel returns the same `available` state for unknown and unlocked IDs.
  Future<LoginLockoutState?> checkLoginLockout(String identifier) async {
    final response = await _call(
      'POST',
      '/auth/lockout-status',
      body: {'login': identifier.trim()},
      auth: false,
      allowConnectionRecovery: false,
    );
    final data = response['data'];
    final security = data is Map ? data['security'] : null;
    final securityFields = security is Map
        ? security.keys.map((key) => key.toString()).join(',')
        : '(none)';
    debugPrint(
      'LOGIN SECURITY: POST ${Uri.parse(AppConfig.apiBase).host}/auth/lockout-status '
      'status=200 security_fields=[$securityFields]',
    );
    if (security is! Map || security['status'] != 'locked') return null;
    final remainingSeconds = _parseSecurityInt(
      security['remaining_seconds'] ?? security['retry_after_seconds'],
    );
    final expiresAt =
        DateTime.tryParse(security['locked_until']?.toString() ?? '')
            ?.toUtc() ??
        (remainingSeconds != null && remainingSeconds > 0
            ? DateTime.now().toUtc().add(Duration(seconds: remainingSeconds))
            : null);
    if (expiresAt == null || !expiresAt.isAfter(DateTime.now().toUtc())) {
      return null;
    }
    return LoginLockoutState(
      identifier: identifier.trim(),
      expiresAt: expiresAt,
      durationSeconds:
          _parseSecurityInt(
            security['lockout_duration_seconds'] ??
                security['duration_seconds'],
          ) ??
          remainingSeconds ??
          0,
      cycle: _parseSecurityInt(security['lockout_cycle']) ?? 0,
    );
  }

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBase,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      headers: {
        'Accept': 'application/json',
        'ngrok-skip-browser-warning': 'true',
      },
    ),
  );

  String? _token;
  Map<String, dynamic>? user;
  bool get loggedIn => _token != null;
  String? get accessToken => _token;
  Map<String, String> get authenticatedHeaders => {
    if (_token != null) 'Authorization': 'Bearer $_token',
  };
  String? get role => user?['role']?.toString();
  Future<void> Function()? onAuthenticated;
  Future<void> Function()? onBeforeLogout;
  Future<void> Function()? onSessionExpired;
  bool _sessionExpiryHandled = false;
  final ValueNotifier<bool> connectionRecoveryActive = ValueNotifier(false);
  int _activeRecoveryRequests = 0;

  @visibleForTesting
  List<Duration> recoveryRetryDelaysForTesting = const [
    Duration(seconds: 1),
    Duration(seconds: 3),
    Duration(seconds: 5),
    Duration(seconds: 5),
    Duration(seconds: 5),
  ];
  Future<Map<String, dynamic>?> Function(
    Future<Map<String, dynamic>> Function()? retryRequest,
    String? serverMessage,
  )?
  onHttp402;

  @visibleForTesting
  HttpClientAdapter get httpClientAdapterForTesting => _dio.httpClientAdapter;

  @visibleForTesting
  set httpClientAdapterForTesting(HttpClientAdapter adapter) {
    _dio.httpClientAdapter = adapter;
  }

  String? _resolveAvatarUrl(dynamic value) {
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    final parsed = Uri.tryParse(raw);
    if (parsed != null && parsed.hasScheme) return raw;
    if (raw.startsWith('/')) {
      return Uri.parse(_dio.options.baseUrl).resolve(raw).toString();
    }
    return raw;
  }

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    _token = p.getString('token');
    final name = p.getString('user_name');
    final email = p.getString('user_email');
    final phone = p.getString('user_phone');
    final role = p.getString('user_role');
    final bio = p.getString('user_bio');
    final preferredLanguage = p.getString('user_preferred_language');
    final avatar = p.getString('user_avatar');
    final avatarUrl = _resolveAvatarUrl(
      p.getString('user_avatar_url') ??
          (avatar == null ? null : '/storage/$avatar'),
    );
    if (_token != null) {
      user = {
        'name': name,
        'email': email,
        'phone': phone,
        'bio': ?bio,
        'preferred_language': ?preferredLanguage,
        'role': role,
        'avatar': ?avatar,
        'avatar_url': ?avatarUrl,
      };
    }
  }

  Future<void> _save(String? token, Map<String, dynamic>? u) async {
    final savedUser = u == null ? null : Map<String, dynamic>.from(u);
    if (savedUser?['avatar_url'] != null) {
      savedUser!['avatar_url'] = _resolveAvatarUrl(savedUser['avatar_url']);
    }
    _token = token;
    user = savedUser;
    if (token != null) _sessionExpiryHandled = false;
    final p = await SharedPreferences.getInstance();
    if (token == null) {
      await p.remove('token');
      await p.remove('user_name');
      await p.remove('user_email');
      await p.remove('user_phone');
      await p.remove('user_bio');
      await p.remove('user_preferred_language');
      await p.remove('user_role');
      await p.remove('user_avatar');
      await p.remove('user_avatar_url');
    } else {
      await p.setString('token', token);
      await p.setString('user_name', savedUser?['name']?.toString() ?? '');
      await p.setString('user_email', savedUser?['email']?.toString() ?? '');
      await p.setString('user_phone', savedUser?['phone']?.toString() ?? '');
      await p.setString('user_bio', savedUser?['bio']?.toString() ?? '');
      await p.setString(
        'user_preferred_language',
        savedUser?['preferred_language']?.toString() ?? 'en',
      );
      await p.setString(
        'user_role',
        savedUser?['role']?.toString() ?? 'customer',
      );
      final avatar = savedUser?['avatar']?.toString();
      final avatarUrl = savedUser?['avatar_url']?.toString();
      if (avatar == null || avatar.isEmpty) {
        await p.remove('user_avatar');
      } else {
        await p.setString('user_avatar', avatar);
      }
      if (avatarUrl == null || avatarUrl.isEmpty) {
        await p.remove('user_avatar_url');
      } else {
        await p.setString('user_avatar_url', avatarUrl);
      }
    }
    final callback = onAuthenticated;
    if (token != null && callback != null) {
      unawaited(callback());
    }
  }

  Future<Map<String, dynamic>> _call(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool auth = true,
    String? tokenOverride,
    Map<String, String>? extraHeaders,
    Duration? connectTimeout,
    Duration? sendTimeout,
    Duration? receiveTimeout,
    void Function(int sent, int total)? onSendProgress,
    bool allow402Recovery = true,
    bool handleSessionExpiry = true,
    bool allowConnectionRecovery = true,
  }) async {
    final token = tokenOverride ?? _token;
    try {
      final res = await _dio.request<dynamic>(
        path,
        data: body,
        queryParameters: query,
        options: Options(
          method: method,
          connectTimeout: connectTimeout,
          sendTimeout: sendTimeout,
          receiveTimeout: receiveTimeout,
          headers: {
            if (auth && token != null) 'Authorization': 'Bearer $token',
            ...?extraHeaders,
          },
        ),
        onSendProgress: onSendProgress,
      );
      final data = res.data;
      if (path == '/auth/login' || path == '/auth/lockout-status') {
        final fields = data is Map
            ? data.keys.map((key) => key.toString()).join(',')
            : '(non-object)';
        final rawData = data is Map ? data['data'] : null;
        final security = rawData is Map ? rawData['security'] : null;
        final securityFields = security is Map
            ? security.keys.map((key) => key.toString()).join(',')
            : '(none)';
        debugPrint(
          'LOGIN SECURITY: $method ${Uri.parse(_dio.options.baseUrl).host}$path '
          'status=${res.statusCode} response_fields=[$fields] '
          'security_fields=[$securityFields]',
        );
      }
      if (data is Map) return Map<String, dynamic>.from(data);
      throw ApiException(
        'The server returned an unexpected response. Check your connection and try again.',
        statusCode: res.statusCode,
        title: 'Unexpected server response',
        instruction: 'If this keeps happening, contact support.',
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final d = e.response?.data;
      debugPrint('API ERROR: $method $path | ${e.type} | status=$code');
      if (path == '/auth/login' || path == '/auth/lockout-status') {
        final fields = d is Map
            ? d.keys.map((key) => key.toString()).join(',')
            : '(non-object)';
        final rawData = d is Map ? d['data'] : null;
        final security = rawData is Map ? rawData['security'] : null;
        final securityFields = security is Map
            ? security.keys.map((key) => key.toString()).join(',')
            : '(none)';
        debugPrint(
          'LOGIN SECURITY: $method ${Uri.parse(_dio.options.baseUrl).host}$path '
          'status=$code response_fields=[$fields] '
          'security_fields=[$securityFields]',
        );
      }

      if (code == 401 &&
          auth &&
          tokenOverride == null &&
          handleSessionExpiry &&
          token != null &&
          token == _token) {
        await _save(null, null);
        if (!_sessionExpiryHandled) {
          _sessionExpiryHandled = true;
          await onSessionExpired?.call();
        }
        throw ApiException(
          'Your session expired. Please log in again.',
          statusCode: 401,
          title: 'Sign in again',
          instruction: 'Your account is safe. Sign in again to continue.',
        );
      }
      if (code == 402) {
        final providerMessage = d is Map
            ? d['message']?.toString().trim()
            : null;
        final serverMessage = providerMessage == null || providerMessage.isEmpty
            ? null
            : providerMessage.substring(
                0,
                providerMessage.length.clamp(0, 500),
              );
        if (method.toUpperCase() == 'GET' && allow402Recovery) {
          final recovered = await onHttp402?.call(
            () => _call(
              method,
              path,
              body: body,
              query: query,
              auth: auth,
              tokenOverride: token,
              extraHeaders: extraHeaders,
              sendTimeout: sendTimeout,
              receiveTimeout: receiveTimeout,
              onSendProgress: onSendProgress,
              allow402Recovery: false,
              allowConnectionRecovery: false,
            ),
            serverMessage,
          );
          if (recovered != null) return recovered;
        } else if (allow402Recovery) {
          await onHttp402?.call(null, serverMessage);
        }
        throw ApiException(
          'The request was rejected with HTTP 402 (Payment Required). A connection retry may help with a temporary gateway issue, but it will not resolve billing, payment, or account restrictions. Your request was not reported as successful.',
          statusCode: code,
          title: 'Payment service requires attention',
          instruction:
              'Check the payment or order status before submitting again.',
        );
      }
      if (path.startsWith('/rider/deliveries/') &&
          path.endsWith('/delivered') &&
          (e.type == DioExceptionType.sendTimeout ||
              e.type == DioExceptionType.receiveTimeout ||
              e.type == DioExceptionType.connectionTimeout)) {
        throw ApiException(
          'The connection is slow and the server response was not received. '
          'Your delivery may already be recorded. Keep this screen open and '
          'refresh the delivery status before taking another action.',
          statusCode: 408,
          title: 'Delivery update timed out',
          instruction: 'Do not send the delivery update again until you have checked its current status.',
          retryable: false,
        );
      }
      final failure = code == null ? _networkError(e) : _httpError(code, d);
      final retryableRead =
          method.toUpperCase() == 'GET' &&
          allowConnectionRecovery &&
          _isTransientReadFailure(e, code);
      if (retryableRead) {
        final recovered = await _retryRead(
          () => _call(
            method,
            path,
            body: body,
            query: query,
            auth: auth,
            tokenOverride: token,
            extraHeaders: extraHeaders,
            connectTimeout: const Duration(seconds: 3),
            sendTimeout: const Duration(seconds: 4),
            receiveTimeout: const Duration(seconds: 5),
            onSendProgress: onSendProgress,
            allow402Recovery: false,
            handleSessionExpiry: handleSessionExpiry,
            allowConnectionRecovery: false,
          ),
        );
        if (recovered != null) return recovered;
      }
      throw failure;
    } catch (error) {
      if (error is ApiException) rethrow;
      debugPrint(
        'Unexpected API failure: $method $path | ${error.runtimeType}',
      );
      throw ApiException(
        'The request could not be completed. Please try again later.',
        title: 'Unexpected error',
        instruction: 'Your information was not changed by an automatic retry.',
      );
    }
  }

  bool _isTransientReadFailure(DioException error, int? statusCode) {
    if (statusCode != null) {
      return const {408, 500, 502, 503, 504}.contains(statusCode);
    }
    return const {
      DioExceptionType.connectionError,
      DioExceptionType.connectionTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout,
    }.contains(error.type);
  }

  Future<Map<String, dynamic>?> _retryRead(
    Future<Map<String, dynamic>> Function() request,
  ) async {
    _activeRecoveryRequests++;
    connectionRecoveryActive.value = true;
    try {
      for (final delay in recoveryRetryDelaysForTesting) {
        if (delay > Duration.zero) await Future<void>.delayed(delay);
        try {
          return await request();
        } on ApiException {
          // Keep the recovery screen visible between bounded read retries.
        }
      }
      return null;
    } finally {
      _activeRecoveryRequests--;
      connectionRecoveryActive.value = _activeRecoveryRequests > 0;
    }
  }

  ApiException _networkError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return ApiException(
          'The server took too long to respond. Check the result before repeating the request.',
          statusCode: 408,
          title: 'Request timed out',
          instruction: 'For an order or payment, check its status before submitting again.',
          retryable: false,
        );
      case DioExceptionType.connectionError:
        return ApiException(
          'We could not reach the server. Check your internet connection and try again.',
          title: 'Connection problem',
          instruction: 'Reconnect to the internet, then retry the action when you are ready.',
          retryable: true,
        );
      case DioExceptionType.cancel:
        return ApiException(
          'The request was cancelled before it finished.',
          title: 'Request cancelled',
          instruction: 'You can start the action again when ready.',
        );
      case DioExceptionType.badCertificate:
        return ApiException(
          'A secure connection to the server could not be established.',
          title: 'Secure connection failed',
          instruction: 'Please try again later or contact support.',
        );
      case DioExceptionType.badResponse:
        return ApiException(
          'The server returned a response the app could not process.',
          title: 'Unexpected server response',
          instruction: 'Please try again later. Check the order status first for payments or orders.',
        );
      case DioExceptionType.unknown:
        return ApiException(
          'The request could not be completed. Check your connection and try again.',
          title: 'Request failed',
          instruction: 'If the problem continues, contact support.',
        );
    }
  }

  ApiException _httpError(int status, dynamic body) {
    String? serverMessage;
    Map<String, dynamic>? validationErrors;
    Map<String, dynamic>? security;
    String? authAction;
    if (body is Map) {
      final rawMessage = body['message']?.toString().trim();
      if (rawMessage != null && rawMessage.isNotEmpty) {
        serverMessage = rawMessage.length > 400
            ? rawMessage.substring(0, 400)
            : rawMessage;
      }
      final rawErrors = body['errors'];
      if (rawErrors is Map) {
        validationErrors = Map<String, dynamic>.from(rawErrors);
      }
      final rawData = body['data'];
      if (rawData is Map) {
        if (rawData['security'] is Map) {
          security = Map<String, dynamic>.from(rawData['security'] as Map);
        }
        if (rawData['auth_action'] == 'facebook_email_verification_required') {
          authAction = rawData['auth_action'] as String;
        }
      }
    }

    String? firstValidationMessage;
    if (validationErrors != null && validationErrors.isNotEmpty) {
      final first = validationErrors.values.first;
      if (first is List && first.isNotEmpty) {
        firstValidationMessage = first.first.toString();
      } else if (first != null) {
        firstValidationMessage = first.toString();
      }
    }

    final (title, fallback, instruction, retryable) = switch (status) {
      400 => (
        'Request could not be understood',
        'Check the information and try again.',
        'Review the form before continuing.',
        false,
      ),
      401 => (
        'Sign in again',
        'Your session expired. Please log in again.',
        'Sign in again to continue.',
        false,
      ),
      403 => (
        'Access denied',
        'You do not have permission to do that.',
        'Return to your account home or contact support.',
        false,
      ),
      404 => (
        'Not found',
        'We could not find what you requested.',
        'Refresh the page or return to the previous screen.',
        false,
      ),
      405 => (
        'Action unavailable',
        'This action is not supported.',
        'Return to the previous screen and choose an available action.',
        false,
      ),
      408 => (
        'Request timed out',
        'The server took too long to respond.',
        'Check the result before repeating an order or payment.',
        false,
      ),
      409 => (
        'Information changed',
        'This request conflicts with the latest information.',
        'Refresh the screen and review the current status.',
        false,
      ),
      413 => (
        'File is too large',
        'This file is too large to upload.',
        'Choose a smaller file and try again.',
        false,
      ),
      419 => (
        'Session expired',
        'This page has expired. Please refresh and try again.',
        'Review the form before submitting again.',
        false,
      ),
      422 => (
        'Check your information',
        'Some information needs your attention.',
        'Review the highlighted fields and correct them.',
        false,
      ),
      429 => (
        'Please wait',
        'Too many requests were sent. Wait a moment, then try again.',
        'Wait for the limit to clear before trying again.',
        true,
      ),
      502 => (
        'Service interruption',
        'A service interruption stopped this request.',
        'Please wait a moment and check the result before retrying.',
        true,
      ),
      503 => (
        'Service unavailable',
        'KJM Coffee Shop is temporarily unavailable.',
        'Please wait a moment and try again.',
        true,
      ),
      504 => (
        'Request timed out',
        'The service did not respond in time.',
        'Check the order or payment status before submitting again.',
        false,
      ),
      _ when status >= 500 => (
        'Server error',
        'Something went wrong on our side.',
        'Please try again later. Check order status before repeating a submission.',
        false,
      ),
      _ => (
        'Request failed',
        'The request could not be completed.',
        'Review the information and try again.',
        false,
      ),
    };
    final message = switch (status) {
      409 || 422 => firstValidationMessage ?? serverMessage ?? fallback,
      400 => serverMessage ?? fallback,
      429 when security != null => serverMessage ?? fallback,
      _ => fallback,
    };

    return ApiException(
      message,
      statusCode: status,
      title: title,
      instruction: instruction,
      retryable: retryable,
      securityStatus: security?['status']?.toString(),
      retryAfterSeconds: _parseSecurityInt(
        security?['retry_after_seconds'] ?? security?['remaining_seconds'],
      ),
      lockedUntil: DateTime.tryParse(
        security?['locked_until']?.toString() ?? '',
      )?.toUtc(),
      lockoutDurationSeconds: _parseSecurityInt(
        security?['lockout_duration_seconds'] ?? security?['duration_seconds'],
      ),
      lockoutCycle: _parseSecurityInt(security?['lockout_cycle']),
      passwordResetRequired:
          security?['password_reset_required'] == true ||
          security?['status'] == 'password_reset_required',
      authAction: authAction,
    );
  }

  int? _parseSecurityInt(dynamic value) =>
      int.tryParse(value?.toString() ?? '');

  Future<MultipartFile> _uploadFile(String path, {String? filename}) async {
    try {
      return await MultipartFile.fromFile(path, filename: filename);
    } catch (_) {
      throw ApiException(
        'The selected file could not be opened. Choose it again and retry.',
        title: 'File upload failed',
        instruction: 'Make sure the file is still available on your device.',
      );
    }
  }

  dynamic _d(Map<String, dynamic> r) => r['data'];

  // ---------- AUTH ----------
  Future<void> login(String login, String password) async {
    final r = await _call(
      'POST',
      '/auth/login',
      body: {'login': login, 'password': password, 'device_name': 'kjm-app'},
      auth: false,
    );
    final data = Map<String, dynamic>.from(_d(r) as Map);
    final u = Map<String, dynamic>.from(data['user'] as Map);
    final token = data['token'] as String;
    if (u['role'] != 'customer' && u['role'] != 'rider') {
      try {
        await _call('POST', '/auth/logout', tokenOverride: token);
      } catch (_) {}
      throw ApiException(
        'This app is for customers and riders. Staff and admins should use the web panel.',
      );
    }
    await _save(token, u);
  }

  Future<void> loginWithGoogle(String idToken) async {
    await loginWithFirebaseToken(idToken, deviceName: 'kjm-google-app');
  }

  Future<void> loginWithFacebook(String idToken) async {
    await loginWithFirebaseToken(
      idToken,
      deviceName: 'kjm-facebook-app',
      provider: 'facebook',
    );
  }

  Future<void> loginWithFirebaseToken(
    String idToken, {
    required String deviceName,
    String? provider,
  }) async {
    final body = <String, dynamic>{
      'id_token': idToken,
      'device_name': deviceName,
    };
    if (provider != null) body['provider'] = provider;
    final r = await _call('POST', '/auth/google', body: body, auth: false);
    final data = Map<String, dynamic>.from(_d(r) as Map);
    await _save(
      data['token'] as String,
      Map<String, dynamic>.from(data['user'] as Map),
    );
  }

  Future<void> forgotPassword(String email) async {
    await _call(
      'POST',
      '/auth/forgot-password',
      body: {'email': email},
      auth: false,
    );
  }

  /// Public support contact configured by an administrator in Laravel.
  Future<Map<String, dynamic>> supportContact() async =>
      Map<String, dynamic>.from(
        _d(await _call('GET', '/support/contact', auth: false)) as Map,
      );

  Future<Map<String, dynamic>?> supportConversation() async {
    final value = _d(await _call('GET', '/support/conversation'));
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  Future<Map<String, dynamic>> startSupportConversation() async =>
      Map<String, dynamic>.from(
        _d(await _call('POST', '/support/conversations')) as Map,
      );

  Future<Map<String, dynamic>> startGuestSupportConversation({
    required String name,
    required String contact,
  }) async => Map<String, dynamic>.from(
    _d(
      await _call(
        'POST',
        '/support/guest/conversations',
        auth: false,
        body: {'name': name, 'contact': contact},
      ),
    ) as Map,
  );

  Future<Map<String, dynamic>> supportConversationMessages(int id) async =>
      Map<String, dynamic>.from(
        _d(await _call('GET', '/support/conversations/$id')) as Map,
      );

  Future<Map<String, dynamic>> guestSupportConversationMessages(
    String uuid,
    String token,
  ) async => Map<String, dynamic>.from(
    _d(
      await _call(
        'GET',
        '/support/guest/conversations/$uuid',
        auth: false,
        extraHeaders: {'X-Support-Token': token},
      ),
    ) as Map,
  );

  Future<Map<String, dynamic>> sendSupportMessage({
    required int conversationId,
    required String body,
    String? attachmentPath,
    int? orderId,
    String? guestUuid,
    String? guestToken,
  }) async {
    final form = FormData.fromMap({
      if (body.trim().isNotEmpty) 'body': body.trim(),
      'order_id': ?orderId,
      if (attachmentPath != null)
        'attachment': await _uploadFile(attachmentPath),
    });
    final path = guestUuid == null
        ? '/support/conversations/$conversationId/messages'
        : '/support/guest/conversations/$guestUuid/messages';
    return Map<String, dynamic>.from(
      _d(
        await _call(
          'POST',
          path,
          body: form,
          auth: guestUuid == null,
          extraHeaders: guestToken == null
              ? null
              : {'X-Support-Token': guestToken},
        ),
      ) as Map,
    );
  }

  Future<void> register(
    String name,
    String username,
    String email,
    String phone,
    String password,
    String passwordConfirmation,
  ) async {
    final r = await _call(
      'POST',
      '/auth/register',
      body: {
        'name': name,
        'username': username,
        'email': email,
        'phone': phone,
        'password': password,
        'password_confirmation': passwordConfirmation,
        'device_name': 'customer-app',
      },
      auth: false,
    );
    final data = Map<String, dynamic>.from(_d(r) as Map);
    await _save(
      data['token'] as String,
      Map<String, dynamic>.from(data['user'] as Map),
    );
  }

  Future<void> logout() async {
    try {
      await onBeforeLogout?.call();
    } catch (_) {}
    try {
      await _call('POST', '/auth/logout', handleSessionExpiry: false);
    } catch (_) {}
    await _save(null, null);
  }

  // ---------- MENU ----------
  Future<List<Map<String, dynamic>>> categories() async =>
      mapList(_d(await _call('GET', '/categories', auth: false)));

  Future<List<Map<String, dynamic>>> products({
    int? categoryId,
    String? search,
  }) async {
    final r = await _call(
      'GET',
      '/products',
      auth: false,
      query: {
        'category_id': ?categoryId,
        if (search != null && search.isNotEmpty) 'search': search,
      },
    );
    final page = Map<String, dynamic>.from(_d(r) as Map);
    return mapList(page['data']);
  }

  Future<Map<String, dynamic>> product(int id) async =>
      Map<String, dynamic>.from(
        _d(await _call('GET', '/products/$id', auth: false)) as Map,
      );

  // ---------- ORDERS ----------
  Future<Map<String, dynamic>> preview(Map<String, dynamic> payload) async =>
      Map<String, dynamic>.from(
        _d(await _call('POST', '/checkout/preview', body: payload)) as Map,
      );

  Future<Map<String, dynamic>> placeOrder(Map<String, dynamic> payload) async {
    final data = Map<String, dynamic>.from(
      _d(await _call('POST', '/orders', body: payload)) as Map,
    );
    final order = Map<String, dynamic>.from(data['order'] as Map);
    final checkout = data['checkout'];
    if (checkout is Map) {
      // Keep the order's own status (awaiting_payment) distinct from the
      // payment attempt status returned by the gateway.
      final checkoutDetails = Map<String, dynamic>.from(checkout);
      final paymentAttemptStatus = checkoutDetails.remove('status');
      final checkoutUrl = checkoutDetails.remove('url');
      order.addAll(checkoutDetails);
      order['payment_attempt_status'] = paymentAttemptStatus;
      order['checkout_url'] = checkoutUrl;
    }
    final contactPhone = payload['contact_phone']?.toString();
    if (contactPhone != null && user != null) {
      user = {...user!, 'phone': contactPhone};
      order['customer_phone'] = contactPhone;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_phone', contactPhone);
    }
    return order;
  }

  Future<List<Map<String, dynamic>>> orders() async =>
      mapList(_d(await _call('GET', '/orders')));

  Future<Map<String, dynamic>> order(int id) async =>
      Map<String, dynamic>.from(_d(await _call('GET', '/orders/$id')) as Map);

  /// Refreshes the signed-in profile from Laravel and persists the current
  /// phone value, so checkout does not rely only on a potentially stale cache.
  Future<Map<String, dynamic>> refreshProfile() async {
    final remote = Map<String, dynamic>.from(
      _d(await _call('GET', '/profile')) as Map,
    );
    final updated = <String, dynamic>{...?user, ...remote};
    if (updated['avatar_url'] != null) {
      updated['avatar_url'] = _resolveAvatarUrl(updated['avatar_url']);
    }
    user = updated;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_phone', updated['phone']?.toString() ?? '');
    return updated;
  }

  Future<Map<String, dynamic>> tracking(int id) async =>
      Map<String, dynamic>.from(
        _d(await _call('GET', '/orders/$id/tracking')) as Map,
      );

  Future<Map<String, dynamic>> customerRiderChat(int orderId) async =>
      Map<String, dynamic>.from(
        _d(await _call('GET', '/orders/$orderId/rider-chat')) as Map,
      );

  Future<Map<String, dynamic>> riderDeliveryChat(int deliveryId) async =>
      Map<String, dynamic>.from(
        _d(await _call('GET', '/rider/deliveries/$deliveryId/chat')) as Map,
      );

  Future<Map<String, dynamic>> sendCustomerRiderChatMessage({
    required int orderId,
    String? body,
    required String clientMessageId,
    String? imagePath,
  }) async {
    final payload = await _sendRiderChatMessage(
      '/orders/$orderId/rider-chat/messages',
      body: body,
      clientMessageId: clientMessageId,
      imagePath: imagePath,
    );
    return Map<String, dynamic>.from(_d(payload) as Map);
  }

  Future<Map<String, dynamic>> sendRiderChatMessage({
    required int deliveryId,
    String? body,
    required String clientMessageId,
    String? imagePath,
  }) async {
    final payload = await _sendRiderChatMessage(
      '/rider/deliveries/$deliveryId/chat/messages',
      body: body,
      clientMessageId: clientMessageId,
      imagePath: imagePath,
    );
    return Map<String, dynamic>.from(_d(payload) as Map);
  }

  Future<Map<String, dynamic>> _sendRiderChatMessage(
    String path, {
    String? body,
    required String clientMessageId,
    String? imagePath,
  }) async {
    Object data;
    if (imagePath != null) {
      data = FormData.fromMap({
        if (body != null && body.trim().isNotEmpty) 'body': body.trim(),
        'client_message_id': clientMessageId,
        'attachment': await _uploadFile(imagePath),
      });
    } else {
      data = {'body': body?.trim() ?? '', 'client_message_id': clientMessageId};
    }
    return _call('POST', path, body: data);
  }

  Future<Map<String, dynamic>> cancel(int id, {required String reason}) async {
    return Map<String, dynamic>.from(
      _d(await _call('POST', '/orders/$id/cancel', body: {'reason': reason}))
          as Map,
    );
  }

  Future<Map<String, dynamic>> submitRefundRequest(
    int orderId, {
    required String reason,
    required String explanation,
    List<String> photoPaths = const [],
  }) async {
    final form = FormData.fromMap({
      'reason': reason,
      'explanation': explanation,
    });
    for (final path in photoPaths) {
      form.files.add(MapEntry('photos[]', await _uploadFile(path)));
    }
    return Map<String, dynamic>.from(
      _d(await _call('POST', '/orders/$orderId/refund-requests', body: form))
          as Map,
    );
  }

  Future<List<Map<String, dynamic>>> refundRequestsForOrder(int orderId) async {
    final data = _d(await _call('GET', '/orders/$orderId/refund-requests'));
    return data is List
        ? data
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
        : const [];
  }

  Future<List<Map<String, dynamic>>> refundHistory() async {
    final data = _d(await _call('GET', '/refund-requests'));
    return data is List
        ? data
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
        : const [];
  }

  Future<void> deleteOrder(int id) async {
    await _call('DELETE', '/orders/$id');
  }

  Future<void> review(int id, int rating, String comment) async {
    await _call(
      'POST',
      '/orders/$id/review',
      body: {'rating': rating, 'comment': comment},
    );
  }

  // ---------- PAYMENT ----------
  Future<Map<String, dynamic>> payOrder(int id) async =>
      Map<String, dynamic>.from(
        _d(await _call('POST', '/orders/$id/pay')) as Map,
      );

  Future<Map<String, dynamic>> verifyPayment(int id) async =>
      Map<String, dynamic>.from(
        _d(await _call('POST', '/orders/$id/payment/verify')) as Map,
      );

  // ---------- FAVORITES ----------
  Future<List<Map<String, dynamic>>> favorites() async =>
      mapList(_d(await _call('GET', '/favorites')));

  Future<void> addFavorite(int productId) async {
    await _call('POST', '/favorites', body: {'product_id': productId});
  }

  Future<void> removeFavorite(int productId) async {
    await _call('DELETE', '/favorites/$productId');
  }

  // ---------- ADDRESSES ----------
  Future<List<Map<String, dynamic>>> addresses() async =>
      mapList(_d(await _call('GET', '/addresses')));

  Future<Map<String, dynamic>> address(int id) async =>
      Map<String, dynamic>.from(
        _d(await _call('GET', '/addresses/$id')) as Map,
      );

  Future<void> saveAddress(
    String label,
    String fullAddress,
    double lat,
    double lng, {
    String street = '',
    String barangay = '',
    String city = '',
    String province = '',
    String postalCode = '',
    String? formattedAddress,
    bool? isDefault,
  }) async {
    await _call(
      'POST',
      '/addresses',
      body: <String, dynamic>{
        'label': label,
        'full_address': fullAddress,
        'formatted_address': formattedAddress ?? fullAddress,
        'street': street,
        'barangay': barangay,
        'city': city,
        'province': province,
        'postal_code': postalCode,
        'latitude': lat,
        'longitude': lng,
        'is_default': ?isDefault,
      },
    );
  }

  Future<void> updateAddress(
    int id,
    String label,
    String fullAddress,
    double lat,
    double lng, {
    String street = '',
    String barangay = '',
    String city = '',
    String province = '',
    String postalCode = '',
    String? formattedAddress,
    bool? isDefault,
  }) async {
    await _call(
      'PUT',
      '/addresses/$id',
      body: {
        'label': label,
        'full_address': fullAddress,
        'formatted_address': formattedAddress ?? fullAddress,
        'street': street,
        'barangay': barangay,
        'city': city,
        'province': province,
        'postal_code': postalCode,
        'latitude': lat,
        'longitude': lng,
        'is_default': ?isDefault,
      },
    );
  }

  Future<void> deleteAddress(int id) async {
    await _call('DELETE', '/addresses/$id');
  }

  Future<Map<String, dynamic>> reverseGeocode(
    double latitude,
    double longitude,
  ) async => Map<String, dynamic>.from(
    _d(
      await _call(
        'GET',
        '/location/reverse-geocode',
        query: {'latitude': latitude, 'longitude': longitude},
      ),
    ) as Map,
  );

  // ---------- NOTIFICATIONS ----------
  Future<Map<String, dynamic>> notifications() async =>
      Map<String, dynamic>.from(
        _d(await _call('GET', '/notifications')) as Map,
      );

  Future<void> readAllNotifications() async {
    await _call('POST', '/notifications/read-all');
  }

  /// Requires the Laravel API to authenticate this token and upsert it for
  /// the signed-in user at POST /notifications/device-token.
  Future<void> registerFcmToken(String token) async {
    await _call(
      'POST',
      '/notifications/device-token',
      body: {'token': token, 'platform': defaultTargetPlatform.name},
    );
  }

  Future<void> unregisterFcmToken(String token) async {
    await _call(
      'DELETE',
      '/notifications/device-token',
      body: {'token': token},
    );
  }

  // ---------- PROFILE ----------
  Future<void> updateProfile({
    String? name,
    String? phone,
    String? bio,
    String? preferredLanguage,
    String? avatarPath,
  }) async {
    final fields = <String, dynamic>{
      if (name != null && name.isNotEmpty) 'name': name,
      if (phone != null) 'phone': phone.trim(),
      if (bio != null) 'bio': bio.trim(),
      'preferred_language': ?preferredLanguage,
    };
    var method = 'PUT';
    Object body = fields;
    if (avatarPath != null) {
      fields['_method'] = 'PUT';
      fields['avatar'] = await _uploadFile(avatarPath);
      body = FormData.fromMap(fields);
      method = 'POST';
    }
    final r = await _call(method, '/profile', body: body);
    final u = Map<String, dynamic>.from(_d(r) as Map);
    await _save(_token, u);
  }

  Future<void> changePassword({
    required String currentPassword,
    required String password,
    required String passwordConfirmation,
  }) async {
    await _call(
      'PUT',
      '/profile',
      body: {
        'current_password': currentPassword,
        'password': password,
        'password_confirmation': passwordConfirmation,
      },
    );
  }

  Future<void> uploadAvatar(String filePath) async {
    await updateProfile(avatarPath: filePath);
  }

  Future<void> deleteAccount(String password) async {
    await _call('DELETE', '/profile', body: {'password': password});
    await _save(null, null);
  }

  // ---------- PRODUCT REVIEWS ----------
  Future<Map<String, dynamic>> productReviews(int id) async =>
      Map<String, dynamic>.from(
        _d(await _call('GET', '/products/$id/reviews', auth: false)) as Map,
      );

  // ---------- HOME ----------
  Future<Map<String, dynamic>> appConfig() async =>
      Map<String, dynamic>.from(_d(await _call('GET', '/app-config')) as Map);

  Future<Map<String, dynamic>> shopHours() async => Map<String, dynamic>.from(
    _d(await _call('GET', '/shop-hours', auth: false)) as Map,
  );

  Future<List<Map<String, dynamic>>> homeBanners() async =>
      mapList(_d(await _call('GET', '/home-banners', auth: false)));

  Future<List<Map<String, dynamic>>> promos() async =>
      mapList(_d(await _call('GET', '/promos', auth: false)));

  // ---------- MEMBERSHIP & LOYALTY ----------
  Future<Map<String, dynamic>> loyaltySummary() async =>
      Map<String, dynamic>.from(_d(await _call('GET', '/loyalty')) as Map);

  Future<Map<String, dynamic>> startMembershipCheckout() async =>
      Map<String, dynamic>.from(
        _d(await _call('POST', '/membership/checkout')) as Map,
      );

  Future<Map<String, dynamic>> verifyMembershipPayment() async =>
      Map<String, dynamic>.from(
        _d(await _call('POST', '/membership/payment/verify')) as Map,
      );

  Future<Map<String, dynamic>> membershipCardDeliveries() async =>
      Map<String, dynamic>.from(
        _d(await _call('GET', '/membership/card-deliveries')) as Map,
      );

  Future<Map<String, dynamic>> requestMembershipCardDelivery({
    required int addressId,
    String? deliveryNotes,
  }) async => Map<String, dynamic>.from(
    _d(
      await _call(
        'POST',
        '/membership/card-deliveries',
        body: {
          'address_id': addressId,
          if (deliveryNotes != null && deliveryNotes.trim().isNotEmpty)
            'delivery_notes': deliveryNotes.trim(),
        },
      ),
    ) as Map,
  );

  Future<List<Map<String, dynamic>>> rewards() async =>
      mapList(_d(await _call('GET', '/rewards')));

  Future<Map<String, dynamic>> redeemReward(
    int rewardId,
    String idempotencyKey, {
    String fulfillmentType = 'pickup',
    int? addressId,
  }) async {
    final response = await _call(
      'POST',
      '/rewards/$rewardId/redeem',
      body: {
        'idempotency_key': idempotencyKey,
        'fulfillment_type': fulfillmentType,
        'address_id': addressId,
      },
    );
    return Map<String, dynamic>.from(_d(response) as Map);
  }

  Future<Map<String, dynamic>> rewardDeliveryQuote(
    int rewardId,
    int addressId,
  ) async {
    final response = await _call(
      'POST',
      '/rewards/$rewardId/delivery-quote',
      body: {'address_id': addressId},
    );
    return Map<String, dynamic>.from(_d(response) as Map);
  }

  Future<Map<String, dynamic>> cancelRewardRedemption(int redemptionId) async {
    final response = await _call(
      'POST',
      '/rewards/redemptions/$redemptionId/cancel',
    );
    return Map<String, dynamic>.from(_d(response) as Map);
  }

  Future<List<Map<String, dynamic>>> rewardRedemptions() async =>
      mapList(_d(await _call('GET', '/rewards/redemptions')));

  // ================= RIDER =================
  Future<Map<String, dynamic>> deliveries() async => Map<String, dynamic>.from(
    _d(await _call('GET', '/rider/deliveries')) as Map,
  );

  Future<Map<String, dynamic>> riderMembershipCardDeliveries() async =>
      Map<String, dynamic>.from(
        _d(await _call('GET', '/rider/membership-card-deliveries')) as Map,
      );

  Future<Map<String, dynamic>> riderMembershipCardDelivery(int id) async =>
      Map<String, dynamic>.from(
        _d(await _call('GET', '/rider/membership-card-deliveries/$id')) as Map,
      );

  Future<Map<String, dynamic>> riderMembershipCardDeliveryAction(
    int id,
    String action,
  ) async => Map<String, dynamic>.from(
    _d(await _call('POST', '/rider/membership-card-deliveries/$id/$action'))
        as Map,
  );

  Future<void> sendMembershipCardDeliveryLocation(
    int deliveryId,
    double latitude,
    double longitude,
    double accuracy,
  ) async {
    await _call(
      'POST',
      '/rider/membership-card-delivery-location',
      body: {
        'delivery_id': deliveryId,
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
      },
    );
  }

  Future<Map<String, dynamic>> history() async => Map<String, dynamic>.from(
    _d(await _call('GET', '/rider/history')) as Map,
  );

  Future<Map<String, dynamic>> riderProfile() async =>
      Map<String, dynamic>.from(
        _d(await _call('GET', '/rider/profile')) as Map,
      );

  Future<Map<String, dynamic>> updateRiderVehicle({
    required String vehicleType,
    required String plateNumber,
    required String licenseNumber,
  }) async => Map<String, dynamic>.from(
    _d(
      await _call(
        'PUT',
        '/rider/profile',
        body: {
          'vehicle_type': vehicleType,
          'plate_number': plateNumber,
          'license_no': licenseNumber,
        },
      ),
    ) as Map,
  );

  Future<Map<String, dynamic>> delivery(int id) async =>
      Map<String, dynamic>.from(
        _d(await _call('GET', '/rider/deliveries/$id')) as Map,
      );

  Future<void> action(int id, String name) async {
    await _call('POST', '/rider/deliveries/$id/$name');
  }

  Future<void> sendLocation(
    int deliveryId,
    double lat,
    double lng,
    double speedKmh,
  ) async {
    await _call(
      'POST',
      '/rider/location',
      body: {
        'delivery_id': deliveryId,
        'latitude': lat,
        'longitude': lng,
        'speed': speedKmh,
      },
    );
  }

  Future<bool> setAvailability(bool value) async {
    final r = await _call(
      'PUT',
      '/rider/availability',
      body: {'is_available': value},
    );
    return Map<String, dynamic>.from(_d(r) as Map)['is_available'] == true;
  }

  /// Mark delivered: may larawan (patunay) at cash na natanggap (kung COD)
  Future<void> deliverWithProof(
    int id,
    String filePath,
    double? cash, {
    void Function(int sent, int total)? onSendProgress,
  }) async {
    final form = FormData.fromMap({
      'proof_photo': await _uploadFile(filePath, filename: 'proof.jpg'),
      if (cash != null) 'cash_collected': cash.toStringAsFixed(2),
    });
    await _call(
      'POST',
      '/rider/deliveries/$id/delivered',
      body: form,
      sendTimeout: const Duration(seconds: 90),
      receiveTimeout: const Duration(seconds: 90),
      onSendProgress: onSendProgress,
    );
  }
}
