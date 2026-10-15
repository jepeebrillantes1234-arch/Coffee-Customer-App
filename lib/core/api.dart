import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'util.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class Api {
  Api._();
  static final Api I = Api._();

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
  String? get role => user?['role']?.toString();

  String? _resolveAvatarUrl(dynamic value) {
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    final parsed = Uri.tryParse(raw);
    if (parsed != null && parsed.hasScheme) return raw;
    if (raw.startsWith('/'))
      return Uri.parse(_dio.options.baseUrl).resolve(raw).toString();
    return raw;
  }

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    _token = p.getString('token');
    final name = p.getString('user_name');
    final email = p.getString('user_email');
    final phone = p.getString('user_phone');
    final role = p.getString('user_role');
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
        'role': role,
        if (avatar != null) 'avatar': avatar,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
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
    final p = await SharedPreferences.getInstance();
    if (token == null) {
      await p.remove('token');
      await p.remove('user_name');
      await p.remove('user_email');
      await p.remove('user_phone');
      await p.remove('user_role');
      await p.remove('user_avatar');
      await p.remove('user_avatar_url');
    } else {
      await p.setString('token', token);
      await p.setString('user_name', savedUser?['name']?.toString() ?? '');
      await p.setString('user_email', savedUser?['email']?.toString() ?? '');
      await p.setString('user_phone', savedUser?['phone']?.toString() ?? '');
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
  }

  Future<Map<String, dynamic>> _call(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool auth = true,
    String? tokenOverride,
  }) async {
    final token = tokenOverride ?? _token;
    try {
      final res = await _dio.request<dynamic>(
        path,
        data: body,
        queryParameters: query,
        options: Options(
          method: method,
          headers: (auth && token != null)
              ? {'Authorization': 'Bearer $token'}
              : null,
        ),
      );
      final data = res.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      throw ApiException(
        'The server returned invalid JSON. Check the URL in config.dart.',
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final d = e.response?.data;
      debugPrint(
        'API ERROR: $method $path | ${e.type} | status=$code | ${e.message} | ${e.error}',
      );

      if (code == 401 && auth && tokenOverride == null) {
        await _save(null, null);
        throw ApiException('Your session expired. Please log in again.');
      }
      if (d is Map) {
        final errs = d['errors'];
        if (errs is Map && errs.isNotEmpty) {
          final first = errs.values.first;
          throw ApiException(
            first is List && first.isNotEmpty
                ? first.first.toString()
                : first.toString(),
          );
        }
        if (d['message'] != null) throw ApiException(d['message'].toString());
      }
      if (code != null) throw ApiException('Server error (status $code).');
      throw ApiException(
        'Could not connect to the server. Check the URL and your internet connection.',
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
    final r = await _call(
      'POST',
      '/auth/google',
      body: {'id_token': idToken, 'device_name': 'kjm-google-app'},
      auth: false,
    );
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
        if (phone.isNotEmpty) 'phone': phone,
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
      await _call('POST', '/auth/logout');
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
    if (checkout is Map) order['checkout_url'] = checkout['url'];
    return order;
  }

  Future<List<Map<String, dynamic>>> orders() async =>
      mapList(_d(await _call('GET', '/orders')));

  Future<Map<String, dynamic>> order(int id) async =>
      Map<String, dynamic>.from(_d(await _call('GET', '/orders/$id')) as Map);

  Future<Map<String, dynamic>> tracking(int id) async =>
      Map<String, dynamic>.from(
        _d(await _call('GET', '/orders/$id/tracking')) as Map,
      );

  Future<void> cancel(int id) async {
    await _call('POST', '/orders/$id/cancel');
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

  Future<void> saveAddress(
    String label,
    String fullAddress,
    double lat,
    double lng,
  ) async {
    await _call(
      'POST',
      '/addresses',
      body: {
        'label': label,
        'full_address': fullAddress,
        'latitude': lat,
        'longitude': lng,
      },
    );
  }

  Future<void> deleteAddress(int id) async {
    await _call('DELETE', '/addresses/$id');
  }

  // ---------- NOTIFICATIONS ----------
  Future<Map<String, dynamic>> notifications() async =>
      Map<String, dynamic>.from(
        _d(await _call('GET', '/notifications')) as Map,
      );

  Future<void> readAllNotifications() async {
    await _call('POST', '/notifications/read-all');
  }

  // ---------- PROFILE ----------
  Future<void> updateProfile({
    String? name,
    String? phone,
  }) async {
    final r = await _call(
      'PUT',
      '/profile',
      body: {
        if (name != null && name.isNotEmpty) 'name': name,
        if (phone != null) 'phone': phone.isEmpty ? null : phone,
      },
    );
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
    final form = FormData.fromMap({
      '_method': 'PUT',
      'avatar': await MultipartFile.fromFile(filePath),
    });
    final response = await _call('POST', '/profile', body: form);
    final payload = response['data'] ?? response;
    if (payload is! Map) {
      throw ApiException(
        'The photo uploaded, but the server did not return profile data.',
      );
    }
    final body = Map<String, dynamic>.from(payload);
    final rawUser = body['user'] ?? body['data'];
    final user = rawUser is Map
        ? Map<String, dynamic>.from(rawUser)
        : (body['id'] != null || body['name'] != null ? body : null);
    if (user == null) {
      throw ApiException(
        body['message']?.toString() ?? 'The server did not return the profile after upload. Check the Laravel API /profile response.',
      );
    }
    await _save(_token, user);
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

  // ================= RIDER =================
  Future<Map<String, dynamic>> deliveries() async => Map<String, dynamic>.from(
    _d(await _call('GET', '/rider/deliveries')) as Map,
  );

  Future<Map<String, dynamic>> history() async => Map<String, dynamic>.from(
    _d(await _call('GET', '/rider/history')) as Map,
  );

  Future<Map<String, dynamic>> riderProfile() async =>
      Map<String, dynamic>.from(_d(await _call('GET', '/rider/profile')) as Map);

  Future<Map<String, dynamic>> updateRiderVehicle({
    required String vehicleType,
    required String plateNumber,
    required String licenseNumber,
  }) async => Map<String, dynamic>.from(
    _d(await _call('PUT', '/rider/profile', body: {
      'vehicle_type': vehicleType,
      'plate_number': plateNumber,
      'license_no': licenseNumber,
    })) as Map,
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
  Future<void> deliverWithProof(int id, String filePath, double? cash) async {
    final form = FormData.fromMap({
      'proof_photo': await MultipartFile.fromFile(
        filePath,
        filename: 'proof.jpg',
      ),
      if (cash != null) 'cash_collected': cash.toStringAsFixed(2),
    });
    await _call('POST', '/rider/deliveries/$id/delivered', body: form);
  }
}
