import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../screens/order_detail_screen.dart';
import '../screens/product_screen.dart';
import '../screens/promos_screen.dart';
import 'api.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class PushNotifications {
  PushNotifications._();
  static final PushNotifications I = PushNotifications._();

  static final navigatorKey = GlobalKey<NavigatorState>();
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  StreamSubscription<String>? _tokenSubscription;
  String? _lastToken;
  String? _lastRegistration;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    _foregroundSubscription = FirebaseMessaging.onMessage.listen(_showForegroundMessage);
    _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(_openMessage);
    _tokenSubscription = _messaging.onTokenRefresh.listen(_registerToken);
    Api.I.onAuthenticated = syncToken;
    Api.I.onBeforeLogout = _removeTokenFromAccount;

    final permission = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (permission.authorizationStatus == AuthorizationStatus.authorized ||
        permission.authorizationStatus == AuthorizationStatus.provisional) {
      await syncToken();
    }

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openMessage(initialMessage));
    }
  }

  Future<void> syncToken() async {
    if (!Api.I.loggedIn) return;
    try {
      final token = await _messaging.getToken();
      if (token != null && token.isNotEmpty) await _registerToken(token);
    } catch (error) {
      debugPrint('Unable to get/register FCM token: $error');
    }
  }

  Future<void> _registerToken(String token) async {
    _lastToken = token;
    if (!Api.I.loggedIn) return;
    final registrationKey = '${Api.I.accessToken}:$token';
    if (_lastRegistration == registrationKey) return;
    try {
      await Api.I.registerFcmToken(token);
      _lastRegistration = registrationKey;
    } on ApiException catch (error) {
      debugPrint('FCM token registration failed: ${error.message}');
    }
  }

  Future<void> _removeTokenFromAccount() async {
    final token = _lastToken;
    if (token == null || !Api.I.loggedIn) return;
    try {
      await Api.I.unregisterFcmToken(token);
      _lastRegistration = null;
    } on ApiException catch (error) {
      debugPrint('FCM token removal failed: ${error.message}');
    }
  }

  void _showForegroundMessage(RemoteMessage message) {
    final copy = _notificationCopy(message);
    final text = '${copy.$1}\n${copy.$2}';
    if (text.isEmpty) return;

    final action = _action(message);
    messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(text),
        action: action == null
            ? null
            : SnackBarAction(
                label: action.$1,
                onPressed: action.$2,
              ),
      ),
    );
  }

  void _openMessage(RemoteMessage message) {
    final orderId = _orderId(message);
    if (orderId != null) {
      _openOrder(orderId);
      return;
    }

    final productId = _intData(message, 'product_id');
    if (productId != null) {
      _openProduct(productId);
      return;
    }

    if (_type(message) == 'promo' || _intData(message, 'promo_id') != null) {
      _openPromos();
    }
  }

  (String, String) _notificationCopy(RemoteMessage message) {
    final type = _type(message);
    final status = (message.data['status'] ?? message.data['order_status'] ?? '')
        .toString()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');

    if (type == 'promo') {
      return (
        'New promotion',
        _nonEmpty(message.data['body']) ??
            'A new offer is available. Tap to view the latest promotions.',
      );
    }
    if (type == 'product') {
      return (
        'New product',
        _nonEmpty(message.data['body']) ??
            'A new menu item is available. Tap to explore the menu.',
      );
    }

    final orderCopy = switch (status) {
      'pending' || 'waiting_confirmation' || 'waiting_confirm' => (
        'Order received',
        'Your order is waiting for confirmation.',
      ),
      'confirmed' => ('Order confirmed', 'The shop has confirmed your order.'),
      'preparing' => ('Preparing your order', 'The shop is preparing your order.'),
      'ready' => ('Order ready', 'Your order is ready for pickup or delivery.'),
      'rider_assigned' => ('Rider assigned', 'A rider has been assigned to your order.'),
      'picked_up' || 'on_the_way' || 'out_for_delivery' || 'out_of_delivery' => (
        'Out for delivery',
        'Your rider is on the way with your order.',
      ),
      'delivered' || 'completed' => ('Order delivered', 'Your order has been delivered.'),
      _ => null,
    };
    if (orderCopy != null) return orderCopy;

    final title = _nonEmpty(message.notification?.title) ??
        _nonEmpty(message.data['title']) ??
        'KJM Coffee Shop';
    final body = _nonEmpty(message.notification?.body) ??
        _nonEmpty(message.data['body']) ??
        'You have a new update.';
    return (title, body);
  }

  (String, VoidCallback)? _action(RemoteMessage message) {
    final orderId = _orderId(message);
    if (orderId != null) return ('View order', () => _openOrder(orderId));
    final productId = _intData(message, 'product_id');
    if (productId != null) return ('View product', () => _openProduct(productId));
    if (_type(message) == 'promo' || _intData(message, 'promo_id') != null) {
      return ('View promotions', _openPromos);
    }
    return null;
  }

  String _type(RemoteMessage message) =>
      (message.data['type'] ?? message.data['notification_type'] ?? '')
          .toString()
          .toLowerCase();

  int? _intData(RemoteMessage message, String key) =>
      int.tryParse(message.data[key]?.toString() ?? '');

  String? _nonEmpty(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  int? _orderId(RemoteMessage message) =>
      int.tryParse(message.data['order_id']?.toString() ?? '');

  void _openOrder(int orderId) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openOrder(orderId));
      return;
    }
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => OrderDetailScreen(id: orderId),
      ),
    );
  }

  void _openProduct(int productId) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openProduct(productId));
      return;
    }
    navigator.push(MaterialPageRoute<void>(builder: (_) => ProductScreen(id: productId)));
  }

  void _openPromos() {
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openPromos());
      return;
    }
    navigator.push(MaterialPageRoute<void>(builder: (_) => const PromosScreen()));
  }

  Future<void> dispose() async {
    await _foregroundSubscription?.cancel();
    await _openedSubscription?.cancel();
    await _tokenSubscription?.cancel();
  }
}
