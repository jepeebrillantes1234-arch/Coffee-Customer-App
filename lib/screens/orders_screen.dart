import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/realtime.dart';
import '../core/theme.dart';
import '../core/util.dart';
import '../core/widgets.dart';
import 'order_contents_screen.dart';
import 'order_detail_screen.dart';
import 'root_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  String? _error;
  StreamSubscription<Map<String, dynamic>>? _liveSubscription;
  String _filter = 'All';

  static const _filters = ['All', 'Completed', 'Cancelled', 'Pending'];
  @override
  void initState() {
    super.initState();
    rootTab.addListener(_onTab);
    Realtime.I.connect();
    _liveSubscription = Realtime.I.updates.listen((event) {
      if (rootTab.value == 3 && ['order', 'delivery', 'payment'].contains(event['kind'])) _load(silent: true);
    });
  }

  void _onTab() {
    if (rootTab.value == 3) _load();
  }

  @override
  void dispose() {
    rootTab.removeListener(_onTab);
    _liveSubscription?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final orders = await Api.I.orders();
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _error = null;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  bool _isCompleted(Map<String, dynamic> order) =>
      order['status'] == 'completed' || order['status'] == 'delivered';

  bool _isCancelled(Map<String, dynamic> order) =>
      order['status'] == 'cancelled' || order['status'] == 'rejected';

  int _count(String filter) => switch (filter) {
    'Completed' => _orders.where(_isCompleted).length,
    'Cancelled' => _orders.where(_isCancelled).length,
    'Pending' =>
      _orders.where((o) => !_isCompleted(o) && !_isCancelled(o)).length,
    _ => _orders.length,
  };

  List<Map<String, dynamic>> get _visibleOrders => switch (_filter) {
    'Completed' => _orders.where(_isCompleted).toList(),
    'Cancelled' => _orders.where(_isCancelled).toList(),
    'Pending' =>
      _orders.where((o) => !_isCompleted(o) && !_isCancelled(o)).toList(),
    _ => _orders,
  };

  String? _imageFor(Map<String, dynamic> order) {
    final rawItems = order['items'];
    if (rawItems is! List || rawItems.isEmpty || rawItems.first is! Map) {
      return null;
    }
    final item = Map<String, dynamic>.from(rawItems.first as Map);
    final product = item['product'] is Map
        ? Map<String, dynamic>.from(item['product'] as Map)
        : <String, dynamic>{};
    final url =
        item['image_url'] ??
        item['product_image_url'] ??
        item['product_image'] ??
        item['image'] ??
        product['image_url'];
    return url?.toString();
  }

  Future<void> _deleteOrder(Map<String, dynamic> order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete order?'),
        content: const Text(
          'This order will be removed from your order history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep order'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await Api.I.deleteOrder(order['id'] as int);
      if (!mounted) return;
      setState(() => _orders.removeWhere((item) => item['id'] == order['id']));
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Order deleted.')));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _openOrder(Map<String, dynamic> order) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OrderDetailScreen(id: order['id'] as int),
      ),
    );
    _load(silent: true);
  }

  Future<void> _viewOrderContents(Map<String, dynamic> order) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OrderContentsScreen(orderId: order['id'] as int),
      ),
    );
    _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'Back to Home',
          onPressed: () => rootTab.value = 0,
          icon: Icon(Icons.arrow_back_rounded, color: Theme.of(context).colorScheme.primary, size: 28),
        ),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'My Orders',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              'Track your orders and deliveries',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              color: Theme.of(context).colorScheme.primary,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
                children: [
                  SizedBox(
                    height: 48,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _filters.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final filter = _filters[index];
                        final selected = _filter == filter;
                        return InkWell(
                          borderRadius: BorderRadius.circular(30),
                          onTap: () => setState(() => _filter = filter),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: selected
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  filter,
                                  style: TextStyle(
                                    color: selected ? Colors.white : Theme.of(context).colorScheme.onSurface,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  constraints: const BoxConstraints(
                                    minWidth: 22,
                                  ),
                                  height: 22,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                  ),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? Colors.white24
                                        : _countColor(filter, context)
                                              .withValues(alpha: 0.18),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    '${_count(filter)}',
                                    style: TextStyle(
                                      color: selected
                                          ? Colors.white
                                          : _countColor(filter, context),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_error != null && _orders.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 72),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(
                              Icons.cloud_off_outlined,
                              size: 42,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 10),
                            Text(_error!, textAlign: TextAlign.center),
                            TextButton(
                              onPressed: _load,
                              child: const Text('Try again'),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (_visibleOrders.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 82),
                      child: Center(
                        child: Column(
                          children: [
                            const Icon(
                              Icons.receipt_long_rounded,
                              size: 48,
                              color: Color(0xFFB8A89B),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _orders.isEmpty
                                  ? 'You have no orders yet.'
                                  : 'No ${_filter.toLowerCase()} orders.',
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    for (final order in _visibleOrders) ...[
                      _orderCard(order),
                      const SizedBox(height: 12),
                    ],
                ],
              ),
            ),
    );
  }

  Color _countColor(String filter, BuildContext context) => switch (filter) {
    'Completed' => const Color(0xFF2D9A5F),
    'Cancelled' => const Color(0xFFE64444),
    'Pending' => const Color(0xFF737B83),
    _ => Theme.of(context).colorScheme.primary,
  };

  Widget _orderCard(Map<String, dynamic> order) {
    final status = '${order['status'] ?? ''}';
    final statusText = _englishStatus(
      status,
      '${order['order_type'] ?? 'delivery'}',
    );
    final color = statusColor(status);
    final image = _imageFor(order);
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _openOrder(order),
        child: Container(
          constraints: const BoxConstraints(minHeight: 112),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Theme.of(context).dividerColor),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0D382416),
                blurRadius: 14,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: image == null || image.isEmpty
                    ? Container(
                        width: 70,
                        height: 78,
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.receipt_long_rounded,
                          color: Theme.of(context).colorScheme.onSurface,
                          size: 34,
                        ),
                      )
                    : NetImage(image, width: 70, height: 78),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${order['order_number'] ?? 'Order'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_month_outlined,
                          size: 15,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${order['order_type'] == 'delivery' ? 'Delivery' : 'Pickup'} · ${dateTimeText(order['created_at'])}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      peso(dbl(order['total'])),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 118),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _statusIcon(status),
                            color: Colors.white,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              statusText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      minimumSize: const Size(0, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => _viewOrderContents(order),
                    icon: const Icon(Icons.visibility_outlined, size: 14),
                    label: const Text(
                      'View order',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (_isCompleted(order) || _isCancelled(order))
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red.shade600,
                        backgroundColor: Theme.of(context).colorScheme.errorContainer,
                        padding: const EdgeInsets.symmetric(horizontal: 7),
                        minimumSize: const Size(0, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => _deleteOrder(order),
                      icon: const Icon(Icons.delete_outline_rounded, size: 14),
                      label: const Text(
                        'Delete',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _statusIcon(String status) => switch (status) {
    'completed' || 'delivered' => Icons.check_rounded,
    'cancelled' || 'rejected' => Icons.close_rounded,
    _ => Icons.more_horiz_rounded,
  };

  String _englishStatus(String status, String type) => switch (status) {
    'awaiting_payment' => 'Awaiting payment',
    'pending' => 'Pending',
    'confirmed' => 'Confirmed',
    'preparing' => 'Preparing',
    'ready' => type == 'pickup' ? 'Ready for pickup' : 'Ready for rider',
    'rider_assigned' => 'Rider assigned',
    'accepted' => 'Accepted',
    'picked_up' => 'Picked up',
    'on_the_way' => 'On the way',
    'delivered' || 'completed' => 'Completed',
    'rejected' || 'cancelled' => 'Cancelled',
    _ => status.replaceAll('_', ' '),
  };
}
