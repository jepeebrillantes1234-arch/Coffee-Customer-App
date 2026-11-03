import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../rider/rider_delivery_screen.dart';
import '../screens/trackorder_screen.dart';
import '../screens/rider_chat_screen.dart';
import '../screens/product_screen.dart';
import '../screens/promos_screen.dart';
import 'api.dart';
import 'realtime.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class PushNotifications {
  PushNotifications._();
  static final PushNotifications I = PushNotifications._();

  static final navigatorKey = GlobalKey<NavigatorState>();
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();

  late final FirebaseMessaging _messaging;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  StreamSubscription<String>? _tokenSubscription;
  Timer? _tokenRetryTimer;
  Timer? _tokenFetchRetryTimer;
  String? _lastToken;
  String? _lastRegistration;
  String? _retryRegistrationKey;
  String? _inFlightRegistrationKey;
  int _tokenRetryAttempt = 0;
  int _tokenFetchRetryAttempt = 0;
  Future<void>? _registrationInFlight;
  bool _initialized = false;
  bool _localNotificationsReady = false;
  bool _navigationReady = false;
  Map<String, dynamic>? _pendingNavigation;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'kjm_order_updates',
    'KJM Order Updates',
    description: 'Order and delivery updates from KJM Coffee Shop.',
    importance: Importance.high,
  );

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    _messaging = FirebaseMessaging.instance;
    // Wire the auth callbacks before awaiting plugin setup. A login that
    // completes during local-notification initialization must still register
    // its FCM token.
    Api.I.onAuthenticated = syncToken;
    Api.I.onBeforeLogout = _removeTokenFromAccount;

    try {
      await _initializeLocalNotifications();
    } catch (_) {
      debugPrint('Local notifications could not be initialized.');
    }
    _foregroundSubscription = FirebaseMessaging.onMessage.listen(
      _showForegroundMessage,
    );
    _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
      _openMessage,
    );
    _tokenSubscription = _messaging.onTokenRefresh.listen(_registerToken);

    try {
      await _messaging.requestPermission(alert: true, badge: true, sound: true);
    } catch (_) {
      debugPrint('Notification permission request could not complete.');
    }
    // Token registration is independent of display permission. Android may
    // still issue an FCM token when notifications are denied; the system will
    // display pushes once the customer grants notification permission.
    await syncToken();

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _queueOrOpen(initialMessage.data);
    }

    final localLaunch = await _localNotifications
        .getNotificationAppLaunchDetails();
    final localPayload = localLaunch?.notificationResponse?.payload;
    if (localLaunch?.didNotificationLaunchApp == true && localPayload != null) {
      _queueOrOpen(_decodePayload(localPayload));
    }
  }

  Future<void> _initializeLocalNotifications() async {
    if (_localNotificationsReady) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('logo1'),
    );
    await _localNotifications.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null) _queueOrOpen(_decodePayload(payload));
      },
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);
    _localNotificationsReady = true;
  }

  Future<void> syncToken() async {
    if (!Api.I.loggedIn) return;
    try {
      final token = await _messaging.getToken();
      if (token != null && token.isNotEmpty) {
        _tokenFetchRetryTimer?.cancel();
        _tokenFetchRetryTimer = null;
        _tokenFetchRetryAttempt = 0;
        await _registerToken(token);
      } else {
        _scheduleTokenFetchRetry(Api.I.accessToken);
      }
    } catch (_) {
      debugPrint('Unable to get/register FCM token.');
      _scheduleTokenFetchRetry(Api.I.accessToken);
    }
  }

  void _scheduleTokenFetchRetry(String? accessToken) {
    const retryDelays = <Duration>[
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 15),
    ];
    if (accessToken == null ||
        _tokenFetchRetryTimer?.isActive == true ||
        _tokenFetchRetryAttempt >= retryDelays.length) {
      return;
    }

    final delay = retryDelays[_tokenFetchRetryAttempt++];
    _tokenFetchRetryTimer = Timer(delay, () {
      if (Api.I.loggedIn && Api.I.accessToken == accessToken) {
        unawaited(syncToken());
      }
    });
  }

  Future<void> _registerToken(String token) async {
    _lastToken = token;
    _tokenFetchRetryTimer?.cancel();
    _tokenFetchRetryTimer = null;
    _tokenFetchRetryAttempt = 0;
    if (!Api.I.loggedIn) return;
    final registrationKey = '${Api.I.accessToken}:$token';
    if (_lastRegistration == registrationKey) return;

    _tokenRetryTimer?.cancel();
    if (_retryRegistrationKey != registrationKey) {
      _retryRegistrationKey = registrationKey;
      _tokenRetryAttempt = 0;
    }

    final inFlight = _registrationInFlight;
    if (inFlight != null) {
      final inFlightKey = _inFlightRegistrationKey;
      await inFlight;
      if (_lastRegistration == registrationKey) return;
      if (inFlightKey == registrationKey) return;
      if (!Api.I.loggedIn || Api.I.accessToken == null) return;
    }

    final attempt = _sendTokenRegistration(token, registrationKey);
    _registrationInFlight = attempt;
    _inFlightRegistrationKey = registrationKey;
    try {
      await attempt;
    } finally {
      if (identical(_registrationInFlight, attempt)) {
        _registrationInFlight = null;
        _inFlightRegistrationKey = null;
      }
    }
  }

  Future<void> _sendTokenRegistration(
    String token,
    String registrationKey,
  ) async {
    try {
      await Api.I.registerFcmToken(token);
      if (registrationKey != '${Api.I.accessToken}:$_lastToken') return;
      _lastRegistration = registrationKey;
      _tokenRetryAttempt = 0;
      _tokenRetryTimer?.cancel();
    } on ApiException {
      debugPrint(
        'FCM token registration failed; a limited retry is scheduled.',
      );
      _scheduleTokenRegistrationRetry(token, registrationKey);
    }
  }

  void _scheduleTokenRegistrationRetry(String token, String registrationKey) {
    const retryDelays = <Duration>[
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 15),
    ];
    if (_tokenRetryAttempt >= retryDelays.length) return;

    final delay = retryDelays[_tokenRetryAttempt++];
    _tokenRetryTimer = Timer(delay, () {
      if (!Api.I.loggedIn ||
          Api.I.accessToken == null ||
          _lastToken != token ||
          registrationKey != '${Api.I.accessToken}:$token') {
        return;
      }
      unawaited(_registerToken(token));
    });
  }

  Future<void> _removeTokenFromAccount() async {
    _tokenRetryTimer?.cancel();
    _tokenRetryTimer = null;
    _tokenFetchRetryTimer?.cancel();
    _tokenFetchRetryTimer = null;
    _tokenFetchRetryAttempt = 0;
    _tokenRetryAttempt = 0;
    _retryRegistrationKey = null;
    final token = _lastToken;
    if (token == null || !Api.I.loggedIn) return;
    try {
      await Api.I.unregisterFcmToken(token);
      _lastRegistration = null;
    } on ApiException {
      debugPrint('FCM token removal failed.');
    }
  }

  Future<void> _showForegroundMessage(RemoteMessage message) async {
    if (_isCurrentRiderChat(message)) return;
    final copy = _notificationCopy(message);
    final text = '${copy.$1}\n${copy.$2}';
    if (text.isEmpty) return;

    final action = _action(message);
    if (_localNotificationsReady) {
      await _localNotifications.show(
        id:
            (message.messageId?.hashCode ??
                DateTime.now().millisecondsSinceEpoch) &
            0x7fffffff,
        title: copy.$1,
        body: copy.$2,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'kjm_order_updates',
            'KJM Order Updates',
            channelDescription:
                'Order and delivery updates from KJM Coffee Shop.',
            importance: Importance.high,
            priority: Priority.high,
            icon: 'logo1',
          ),
        ),
        payload: jsonEncode(message.data),
      );
    }
    messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(text),
        action: action == null
            ? null
            : SnackBarAction(label: action.$1, onPressed: action.$2),
      ),
    );
  }

  void _openMessage(RemoteMessage message) {
    _queueOrOpen(message.data);
  }

  void markNavigationReady() {
    _navigationReady = true;
    final pending = _pendingNavigation;
    _pendingNavigation = null;
    if (pending != null) _openData(pending);
  }

  void _queueOrOpen(Map<String, dynamic> data) {
    if (!_navigationReady) {
      _pendingNavigation = Map<String, dynamic>.from(data);
      return;
    }
    _openData(data);
  }

  Map<String, dynamic> _decodePayload(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return <String, dynamic>{};
  }

  void _openData(Map<String, dynamic> data) {
    final type = (data['type'] ?? data['notification_type'] ?? '').toString();
    if (type == 'rider_chat') {
      if (Api.I.role == 'rider') {
        final deliveryId = int.tryParse(data['delivery_id']?.toString() ?? '');
        if (deliveryId != null) _openRiderChat(deliveryId, isRider: true);
      } else {
        final orderId = int.tryParse(data['order_id']?.toString() ?? '');
        if (orderId != null) _openRiderChat(orderId, isRider: false);
      }
      return;
    }

    if (Api.I.role == 'rider') {
      if (type == 'delivery_assigned') {
        final orderId = int.tryParse(data['order_id']?.toString() ?? '');
        if (orderId != null) {
          unawaited(_openAssignedDeliveryForOrder(orderId));
        }
        return;
      }
      final deliveryId = int.tryParse(data['delivery_id']?.toString() ?? '');
      if (deliveryId != null) _openDelivery(deliveryId);
      return;
    }

    final orderId = int.tryParse(data['order_id']?.toString() ?? '');
    if (orderId != null) {
      _openOrder(orderId);
      return;
    }

    final productId = int.tryParse(data['product_id']?.toString() ?? '');
    if (productId != null) {
      _openProduct(productId);
      return;
    }

    if (type == 'promo' ||
        int.tryParse(data['promo_id']?.toString() ?? '') != null) {
      _openPromos();
    }
  }

  (String, String) _notificationCopy(RemoteMessage message) {
    final type = _type(message);
    final status =
        (message.data['event'] ??
                message.data['status'] ??
                message.data['order_status'] ??
                '')
            .toString()
            .toLowerCase()
            .replaceAll('-', '_')
            .replaceAll(' ', '_');

    if (type == 'rider_chat') {
      return (
        'New Message from Your Rider',
        'A new message is waiting in your order chat.',
      );
    }
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
      'confirmed' => (
        'Order Confirmed!',
        'Your order has been accepted by KJM Coffee. We will start preparing your order soon.',
      ),
      'payment_confirmed' => (
        'Payment confirmed',
        'Your payment was confirmed by KJM Coffee Shop.',
      ),
      'preparing' => (
        'Preparing Your Order',
        'Your order is now being prepared.',
      ),
      'ready' => (
        'Order Ready for Pickup',
        'Your order is ready for rider pickup.',
      ),
      'rider_assigned' => (
        'Rider assigned',
        'A rider has been assigned to your order.',
      ),
      'picked_up' => (
        'Order Picked Up',
        'Your rider has picked up your order.',
      ),
      'on_the_way' || 'out_for_delivery' || 'out_of_delivery' => (
        'Your Order Is On the Way!',
        'Your rider is now delivering your order.',
      ),
      'delivered' ||
      'completed' => ('Order Delivered!', 'Your order has been delivered.'),
      _ => null,
    };
    if (orderCopy != null) return orderCopy;

    if (_type(message) == 'delivery') {
      return switch (status) {
        'assigned' => (
          'New delivery assignment',
          'A delivery has been assigned to you.',
        ),
        'reassigned' => (
          'Delivery reassigned',
          'A delivery has been reassigned to you.',
        ),
        'ready_for_pickup' => (
          'Order ready for pickup',
          'The customer order is ready for pickup.',
        ),
        'cancelled' => (
          'Delivery cancelled',
          'The assigned order has been cancelled.',
        ),
        _ => (
          'Delivery update',
          'There is an update about your assigned delivery.',
        ),
      };
    }

    final title =
        _nonEmpty(message.notification?.title) ??
        _nonEmpty(message.data['title']) ??
        'KJM Coffee Shop';
    final body =
        _nonEmpty(message.notification?.body) ??
        _nonEmpty(message.data['body']) ??
        'You have a new update.';
    return (title, body);
  }

  (String, VoidCallback)? _action(RemoteMessage message) {
    if (_type(message) == 'rider_chat') {
      final targetId = Api.I.role == 'rider'
          ? _intData(message, 'delivery_id')
          : _orderId(message);
      return targetId == null
          ? null
          : (
              'Open chat',
              () => _openRiderChat(targetId, isRider: Api.I.role == 'rider'),
            );
    }
    if (Api.I.role == 'rider') {
      if (_type(message) == 'delivery_assigned') {
        final orderId = _orderId(message);
        return orderId == null
            ? null
            : (
                'View delivery',
                () => unawaited(_openAssignedDeliveryForOrder(orderId)),
              );
      }
      final deliveryId = int.tryParse(
        message.data['delivery_id']?.toString() ?? '',
      );
      return deliveryId == null
          ? null
          : ('View delivery', () => _openDelivery(deliveryId));
    }
    final orderId = _orderId(message);
    if (orderId != null) return ('View order', () => _openOrder(orderId));
    final productId = _intData(message, 'product_id');
    if (productId != null) {
      return ('View product', () => _openProduct(productId));
    }
    if (_type(message) == 'promo' || _intData(message, 'promo_id') != null) {
      return ('View promotions', _openPromos);
    }
    return null;
  }

  String _type(RemoteMessage message) =>
      (message.data['type'] ?? message.data['notification_type'] ?? '')
          .toString()
          .toLowerCase();

  bool _isCurrentRiderChat(RemoteMessage message) {
    if (_type(message) != 'rider_chat' || Api.I.role != 'customer') {
      return false;
    }
    final orderId = _orderId(message);
    return orderId != null &&
        Realtime.I.activeCustomerRiderChatOrderId == orderId;
  }

  int? _intData(RemoteMessage message, String key) =>
      int.tryParse(message.data[key]?.toString() ?? '');

  String? _nonEmpty(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  int? _orderId(RemoteMessage message) =>
      int.tryParse(message.data['order_id']?.toString() ?? '');

  void _openDelivery(int deliveryId) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _openDelivery(deliveryId),
      );
      return;
    }
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => RiderDeliveryScreen(id: deliveryId),
      ),
    );
  }

  Future<void> _openAssignedDeliveryForOrder(int orderId) async {
    try {
      final response = await Api.I.deliveries();
      final rawItems = response['items'];
      if (rawItems is List) {
        for (final rawItem in rawItems.whereType<Map>()) {
          final delivery = Map<String, dynamic>.from(rawItem);
          final rawOrder = delivery['order'];
          final order = rawOrder is Map
              ? Map<String, dynamic>.from(rawOrder)
              : <String, dynamic>{};
          final id = int.tryParse(delivery['id']?.toString() ?? '');
          final listedOrderId = int.tryParse(order['id']?.toString() ?? '');
          if (id != null && listedOrderId == orderId) {
            // RiderDeliveryScreen loads the latest delivery detail from Laravel.
            _openDelivery(id);
            return;
          }
        }
      }
      messengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('This delivery is no longer available.')),
      );
    } on ApiException {
      messengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text('Could not load this delivery. Try again.'),
        ),
      );
    } catch (_) {
      messengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text('Could not load this delivery. Try again.'),
        ),
      );
    }
  }

  void _openOrder(int orderId) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openOrder(orderId));
      return;
    }
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => TrackOrderScreen(orderId: orderId),
      ),
    );
  }

  void _openRiderChat(int targetId, {required bool isRider}) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _openRiderChat(targetId, isRider: isRider),
      );
      return;
    }
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => RiderChatScreen(targetId: targetId, isRider: isRider),
      ),
    );
  }

  void _openProduct(int productId) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _openProduct(productId),
      );
      return;
    }
    navigator.push(
      MaterialPageRoute<void>(builder: (_) => ProductScreen(id: productId)),
    );
  }

  void _openPromos() {
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openPromos());
      return;
    }
    navigator.push(
      MaterialPageRoute<void>(builder: (_) => const PromosScreen()),
    );
  }

  Future<void> dispose() async {
    _tokenRetryTimer?.cancel();
    _tokenFetchRetryTimer?.cancel();
    await _foregroundSubscription?.cancel();
    await _openedSubscription?.cancel();
    await _tokenSubscription?.cancel();
  }
}
