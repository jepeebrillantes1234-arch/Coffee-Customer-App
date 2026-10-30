import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../core/util.dart';
import '../core/widgets.dart';

class OrderContentsScreen extends StatefulWidget {
  const OrderContentsScreen({
    super.key,
    required this.orderId,
    this.initialOrder,
  });

  final int orderId;
  final Map<String, dynamic>? initialOrder;

  @override
  State<OrderContentsScreen> createState() => _OrderContentsScreenState();
}

class _OrderContentsScreenState extends State<OrderContentsScreen> {
  Map<String, dynamic>? _order;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _order = widget.initialOrder;
    _loading = _order == null;
    _load();
  }

  Future<void> _load() async {
    if (_order == null) {
      setState(() => _loading = true);
    }
    setState(() => _error = null);
    try {
      final order = await Api.I.order(widget.orderId);
      if (!mounted) return;
      setState(() {
        _order = order;
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

  @override
  Widget build(BuildContext context) {
    final order = _order;
    final items = order == null
        ? <Map<String, dynamic>>[]
        : mapList(order['items'] ?? []);
    final quantity = items.fold<int>(
      0,
      (sum, item) => sum + ((item['qty'] as num?)?.toInt() ?? 0),
    );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        title: const Text('Order details'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : order == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error ?? 'Could not load order details.'),
                  TextButton(onPressed: _load, child: const Text('Try again')),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${order['order_number'] ?? 'Order'}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _statusBadge(order),
                      const SizedBox(height: 6),
                      Text(
                        '${order['order_type'] == 'delivery' ? 'Delivery' : 'Pickup'} · ${dateTimeText(order['created_at'])}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$quantity ${quantity == 1 ? 'item' : 'items'} ordered',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Items ordered',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (items.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: Text('Order items are unavailable.'),
                          ),
                        )
                      else
                        for (final item in items) _itemRow(item),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    children: [
                      _summaryRow('Subtotal', peso(dbl(order['subtotal']))),
                      if (dbl(order['discount']) > 0)
                        _summaryRow(
                          'Discount',
                          '-${peso(dbl(order['discount']))}',
                        ),
                      if (dbl(order['delivery_fee']) > 0)
                        _summaryRow(
                          'Delivery fee',
                          peso(dbl(order['delivery_fee'])),
                        ),
                      const Divider(height: 22),
                      _summaryRow(
                        'Total',
                        peso(dbl(order['total'])),
                        bold: true,
                      ),
                      const SizedBox(height: 8),
                      _summaryRow(
                        'Payment',
                        '${order['payment_method'] ?? '—'}'
                            .toString()
                            .toUpperCase(),
                      ),
                      if ((order['delivery_address'] ?? '')
                          .toString()
                          .isNotEmpty) ...[
                        const Divider(height: 22),
                        _summaryRow(
                          'Delivery address',
                          '${order['delivery_address']}',
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _statusBadge(Map<String, dynamic> order) {
    final status = '${order['status'] ?? ''}';
    final color = statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        statusLabel(status, '${order['order_type'] ?? 'delivery'}'),
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _itemRow(Map<String, dynamic> item) {
    final image = (item['image_url'] ?? '').toString();
    final options = item['options'] is List
        ? (item['options'] as List).map((option) => '$option').join(', ')
        : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: image.isEmpty
                ? Container(
                    width: 58,
                    height: 58,
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    child: Icon(
                      Icons.coffee_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  )
                : NetImage(image, width: 58, height: 58),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item['qty'] ?? 0} × ${item['name'] ?? 'Item'}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (options.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    options,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(peso(dbl(item['line_total']))),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
