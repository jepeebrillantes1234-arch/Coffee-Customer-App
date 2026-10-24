import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/util.dart';

class PaymentMethodsScreen extends StatefulWidget {
  const PaymentMethodsScreen({super.key});

  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
  bool _loading = true;
  String? _error;
  List<String> _methods = const [];
  List<Map<String, dynamic>> _orders = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final results = await Future.wait<Object>([
        Api.I.appConfig(),
        Api.I.orders(),
      ]);
      final config = Map<String, dynamic>.from(results[0] as Map);
      final settings = config['settings'] is Map
          ? Map<String, dynamic>.from(config['settings'] as Map)
          : <String, dynamic>{};
      final available = settings['available_payment_methods'];
      final methods = available is List
          ? available.map((method) => method.toString().toLowerCase())
              .where((method) => method == 'qrph' || method == 'cod')
              .toSet()
              .toList()
          : <String>[];
      final orders = (results[1] as List<Map<String, dynamic>>)
          .where((order) {
            final method = order['payment_method']?.toString().toLowerCase();
            return method == 'qrph' || method == 'cod';
          })
          .toList()
        ..sort((a, b) => _date(b).compareTo(_date(a)));

      if (!mounted) return;
      setState(() {
        _methods = methods;
        _orders = orders;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load payment information. Please try again.';
        _loading = false;
      });
    }
  }

  DateTime _date(Map<String, dynamic> order) =>
      DateTime.tryParse(order['created_at']?.toString() ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0);

  String _formatDate(Map<String, dynamic> order) {
    final date = _date(order);
    if (date.millisecondsSinceEpoch == 0) return 'Date unavailable';
    final local = date.toLocal();
    final month = _monthName(local.month);
    final time = TimeOfDay.fromDateTime(local).format(context);
    return '$month ${local.day}, ${local.year} · $time';
  }

  String _monthName(int month) => const [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ][month - 1];

  String _status(Map<String, dynamic> order) {
    final status = order['payment_status']?.toString().trim();
    if (status == null || status.isEmpty) return 'Status unavailable';
    return status.replaceAll('_', ' ').split(' ').map((word) {
      if (word.isEmpty) return word;
      return '${word[0].toUpperCase()}${word.substring(1)}';
    }).join(' ');
  }

  Color _statusColor(BuildContext context, String status) {
    final colors = Theme.of(context).colorScheme;
    return switch (status.toLowerCase()) {
      'paid' => Colors.green.shade700,
      'refunded' => colors.primary,
      'failed' || 'expired' || 'cancelled' => colors.error,
      _ => colors.onSurfaceVariant,
    };
  }

  Widget _methodCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String label,
    required String description,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: colors.onPrimaryContainer),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
                      Text(label, style: TextStyle(fontSize: 11, color: colors.primary, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(description, style: TextStyle(fontSize: 13, height: 1.4, color: colors.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _historyRow(Map<String, dynamic> order) {
    final method = order['payment_method']?.toString().toLowerCase() ?? '';
    final status = _status(order);
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    order['order_number']?.toString() ?? 'Order',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(peso(dbl(order['total'])), style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(_formatDate(order), style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
                Text('·', style: TextStyle(color: colors.onSurfaceVariant)),
                Text(method.toUpperCase(), style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(context, status).withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _statusColor(context, status))),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Payment Methods')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_off_rounded, size: 44, color: colors.error),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                    children: [
                      Text('Available at checkout', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 12),
                      if (_methods.contains('qrph')) ...[
                        _methodCard(
                          context: context,
                          icon: Icons.qr_code_2_rounded,
                          title: 'QRPh',
                          label: 'PAYMONGO',
                          description: 'Pay online through PayMongo’s secure QRPh checkout. Scan with a QRPh-enabled wallet or banking app. Your order is confirmed only after the server verifies payment.',
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (_methods.contains('cod'))
                        _methodCard(
                          context: context,
                          icon: Icons.local_shipping_outlined,
                          title: 'Cash on Delivery',
                          label: 'PAY AT DELIVERY',
                          description: 'Pay the rider in cash when your delivery arrives. Cash collection is recorded through the delivery proof and shop confirmation process.',
                        ),
                      if (_methods.isEmpty)
                        Card(child: Padding(padding: const EdgeInsets.all(16), child: Text('No payment methods are currently available. Please check again later.', style: TextStyle(color: colors.onSurfaceVariant)))),
                      const SizedBox(height: 12),
                      Card(
                        color: colors.surfaceContainerLow,
                        child: const Padding(
                          padding: EdgeInsets.all(14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline_rounded),
                              SizedBox(width: 10),
                              Expanded(child: Text('Choose a method during checkout. Payment preferences are not saved to your profile, so this screen will not claim a preference was saved.')),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text('Payment History', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text('Orders linked to your signed-in account.', style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant)),
                      const SizedBox(height: 12),
                      if (_orders.isEmpty)
                        Card(child: Padding(padding: const EdgeInsets.all(18), child: Center(child: Text('No QRPh or Cash on Delivery payments yet.', style: TextStyle(color: colors.onSurfaceVariant)))))
                      else
                        ..._orders.map((order) => Padding(
                              padding: const EdgeInsets.only(bottom: 9),
                              child: _historyRow(order),
                            )),
                      const SizedBox(height: 8),
                      Text('History is loaded from your authenticated orders. Payment status reflects the server record.', style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
                    ],
                  ),
                ),
    );
  }
}
