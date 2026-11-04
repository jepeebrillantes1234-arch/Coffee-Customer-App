import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/realtime.dart';
import '../core/util.dart';
import '../rider/rider_delivery_screen.dart';
import '../rider/rider_theme.dart';
import 'rider_chat_screen.dart';
import 'trackorder_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, this.riderStyle = false});

  final bool riderStyle;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _hadUnread = false;
  String? _error;
  StreamSubscription<Map<String, dynamic>>? _liveSubscription;

  int? _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  @override
  void initState() {
    super.initState();
    _load();
    Realtime.I.connect();
    _liveSubscription = Realtime.I.updates.listen((event) {
      if (event['kind'] == 'notification') _load();
    });
  }

  @override
  void dispose() {
    _liveSubscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final response = await Api.I.notifications();
      if (!mounted) return;
      setState(() {
        _items = mapList(response['items']);
        _hadUnread = (_intValue(response['unread']) ?? 0) > 0;
        _loading = false;
        _error = null;
      });
      if ((_intValue(response['unread']) ?? 0) > 0) {
        await Api.I.readAllNotifications();
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  String _status(Map<String, dynamic> notification) {
    final data = notification['data'];
    return data is Map ? '${data['event'] ?? data['status'] ?? ''}' : '';
  }

  String _title(Map<String, dynamic> notification) {
    final status = _status(notification);
    final data = notification['data'];
    final type = '${notification['type'] ?? (data is Map ? data['type'] : '')}';
    if (type == 'rider_chat') return 'New Message from Your Rider';
    if (type == 'delivery') {
      return switch (status) {
        'assigned' => 'New delivery assignment',
        'reassigned' => 'Delivery reassigned',
        'ready_for_pickup' => 'Order ready for pickup',
        'cancelled' => 'Delivery cancelled',
        _ => 'Delivery update',
      };
    }
    return switch (status) {
      'payment_confirmed' => 'Payment confirmed',
      'pending' => 'Order received',
      'confirmed' => 'Order Confirmed!',
      'preparing' => 'Preparing Your Order',
      'ready' => 'Order Ready for Pickup',
      'rider_assigned' => 'Rider assigned',
      'picked_up' => 'Order Picked Up',
      'on_the_way' => 'Your Order Is On the Way!',
      'delivered' => 'Order Delivered!',
      'completed' => 'Order completed',
      'cancelled' => 'Order cancelled',
      'rejected' => 'Order declined',
      'expired' => 'Order expired',
      _ => switch ('${notification['type'] ?? ''}') {
        'refund' => 'Refund update',
        'promo' => 'New promotion',
        _ => 'New notification',
      },
    };
  }

  String _statusLabel(String status) => switch (status) {
    'payment_confirmed' => 'Paid',
    'assigned' || 'reassigned' => 'Assigned',
    'ready_for_pickup' => 'Pickup ready',
    'pending' => 'Received',
    'confirmed' => 'Confirmed',
    'preparing' => 'Preparing',
    'ready' => 'Ready',
    'rider_assigned' => 'Rider assigned',
    'picked_up' || 'on_the_way' => 'On the way',
    'delivered' => 'Delivered',
    'completed' => 'Completed',
    'cancelled' => 'Cancelled',
    'rejected' => 'Declined',
    'expired' => 'Expired',
    _ => 'Update',
  };

  String _message(Map<String, dynamic> notification) {
    final data = notification['data'];
    final status = _status(notification);
    final type = '${notification['type'] ?? (data is Map ? data['type'] : '')}';
    if (type == 'rider_chat') {
      return 'A new message is waiting in your order chat.';
    }
    if (type == 'delivery') {
      final message = '${notification['message'] ?? ''}'.trim();
      return message.isEmpty
          ? 'Open the delivery to view its latest details.'
          : message;
    }
    if (data is! Map || status.isEmpty) {
      return switch ('${notification['type'] ?? ''}') {
        'refund' => 'There is an update about your refund.',
        'promo' => 'Open Promos to see the latest offer.',
        _ => 'You have a new update.',
      };
    }
    final rawMessage = '${notification['message'] ?? ''}';
    final orderNumber =
        data['order_number'] ??
        data['order_code'] ??
        RegExp(r'(?:KJM|ORD)-[A-Z0-9-]+').firstMatch(rawMessage)?.group(0);
    final orderId = data['order_id'];
    final reference = orderNumber == null
        ? (orderId == null ? 'your order' : 'order #$orderId')
        : 'order $orderNumber';
    final phrase = switch (status) {
      'payment_confirmed' => 'has a confirmed payment',
      'pending' => 'has been received by the shop',
      'confirmed' => 'has been confirmed by the shop',
      'preparing' => 'is being prepared',
      'ready' => 'is ready',
      'rider_assigned' => 'has a rider assigned',
      'picked_up' => 'has been picked up by the rider',
      'on_the_way' => 'is on the way to you',
      'delivered' => 'has been delivered',
      'completed' => 'is complete',
      'cancelled' => 'has been cancelled',
      'rejected' => 'was declined by the shop',
      'expired' => 'has expired',
      _ => 'has an update',
    };
    return '${reference[0].toUpperCase()}${reference.substring(1)} $phrase.';
  }

  Color _statusColor(String status, BuildContext context) => switch (status) {
    'payment_confirmed' ||
    'assigned' ||
    'reassigned' => const Color(0xFF39845A),
    'pending' || 'confirmed' => const Color(0xFF39845A),
    'completed' || 'ready' => const Color(0xFFD98A18),
    'delivered' ||
    'cancelled' ||
    'rejected' ||
    'expired' => const Color(0xFFD83B4B),
    'picked_up' || 'on_the_way' => const Color(0xFF287CC1),
    'preparing' || 'ready_for_pickup' => const Color(0xFF119A94),
    'rider_assigned' => const Color(0xFF6A49A4),
    _ => Theme.of(context).colorScheme.primary,
  };

  IconData _icon(String status, Map<String, dynamic> notification) =>
      notification['type'] == 'rider_chat'
      ? Icons.chat_bubble_outline_rounded
      : switch (status) {
          'pending' || 'confirmed' => Icons.shopping_cart_outlined,
          'preparing' => Icons.soup_kitchen_outlined,
          'ready' => Icons.inventory_2_outlined,
          'rider_assigned' ||
          'picked_up' ||
          'on_the_way' ||
          'delivered' => Icons.delivery_dining_rounded,
          'completed' => Icons.check_circle_outline_rounded,
          'cancelled' || 'rejected' || 'expired' => Icons.info_outline_rounded,
          _ =>
            notification['type'] == 'refund'
                ? Icons.payments_outlined
                : Icons.notifications_none_rounded,
        };

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final page = widget.riderStyle
        ? dark
              ? const Color(0xFF1C1713)
              : riderCream
        : Theme.of(context).scaffoldBackgroundColor;
    final primary = widget.riderStyle
        ? riderAccent(context)
        : Theme.of(context).colorScheme.primary;
    final secondary = widget.riderStyle
        ? riderSecondaryText(context)
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final notificationAction = Padding(
      padding: const EdgeInsets.only(right: 18),
      child: _hadUnread
          ? Badge(
              smallSize: 10,
              backgroundColor: const Color(0xFFE24C54),
              child: Icon(
                Icons.notifications_none_rounded,
                color: widget.riderStyle ? riderCream : primary,
                size: 27,
              ),
            )
          : Icon(
              Icons.notifications_none_rounded,
              color: widget.riderStyle ? riderCream : primary,
              size: 27,
            ),
    );
    final screen = Scaffold(
      backgroundColor: page,
      appBar: widget.riderStyle
          ? const RiderAppBar(title: 'Notifications')
          : AppBar(
              backgroundColor: page,
              leading: IconButton(
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: Icon(
                  Icons.arrow_back_rounded,
                  color: Theme.of(context).colorScheme.primary,
                  size: 28,
                ),
              ),
              titleSpacing: 0,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Notifications',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                    ),
                  ),
                  Text(
                    'Stay updated with your orders and activities',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              actions: [notificationAction],
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              color: primary,
              onRefresh: _load,
              child: _items.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 140),
                        Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.notifications_none_rounded,
                                size: 48,
                                color: secondary,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _error ?? 'No notifications yet.',
                                style: TextStyle(color: secondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                      itemCount: _items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 11),
                      itemBuilder: (context, index) =>
                          _notificationCard(context, _items[index]),
                    ),
            ),
    );
    return widget.riderStyle ? RiderVisualTheme(child: screen) : screen;
  }

  Widget _notificationCard(
    BuildContext context,
    Map<String, dynamic> notification,
  ) {
    final status = _status(notification);
    final color = _statusColor(status, context);
    final data = notification['data'];
    final deliveryId = data is Map ? _intValue(data['delivery_id']) : null;
    final orderId = data is Map ? _intValue(data['order_id']) : null;
    final isRider = Api.I.role == 'rider';
    final isRiderChat = notification['type'] == 'rider_chat';
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(19),
      child: InkWell(
        borderRadius: BorderRadius.circular(19),
        onTap: isRiderChat && !isRider && orderId != null
            ? () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      RiderChatScreen(targetId: orderId, isRider: false),
                ),
              )
            : isRider
            ? deliveryId == null
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => RiderDeliveryScreen(id: deliveryId),
                      ),
                    )
            : orderId == null
            ? null
            : () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TrackOrderScreen(orderId: orderId),
                ),
              ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(19),
            border: Border.all(color: Theme.of(context).dividerColor),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0B000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _icon(status, notification),
                  color: color,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title(notification),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _message(notification),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time_rounded,
                          size: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            dateTimeText(notification['created_at']),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (status.isNotEmpty)
                    Container(
                      constraints: const BoxConstraints(maxWidth: 92),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Text(
                        _statusLabel(status),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  const SizedBox(height: 5),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
