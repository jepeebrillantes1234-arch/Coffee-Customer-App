import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/util.dart';

class RefundHistoryScreen extends StatefulWidget {
  const RefundHistoryScreen({super.key, this.orderId});

  final int? orderId;

  @override
  State<RefundHistoryScreen> createState() => _RefundHistoryScreenState();
}

class _RefundHistoryScreenState extends State<RefundHistoryScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _requests = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final requests = widget.orderId == null
          ? await Api.I.refundHistory()
          : await Api.I.refundRequestsForOrder(widget.orderId!);
      if (mounted) setState(() => _requests = requests);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Refund history could not be loaded.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _label(String value) => value
      .split('_')
      .map(
        (part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.orderId == null ? 'Refund History' : 'Refund Request History',
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : _requests.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 44,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    const Text('No refund requests yet.'),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _requests.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final request = _requests[index];
                  final status = '${request['status'] ?? 'pending'}';
                  final attempts = (request['attempts'] as List?) ?? const [];
                  final rejectedReason = request['decision_reason']?.toString();
                  final amount =
                      request['refunded_amount'] ??
                      request['approved_amount'] ??
                      request['requested_amount'];
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Order ${request['order_number'] ?? request['order_id'] ?? ''}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              Chip(label: Text(_label(status))),
                            ],
                          ),
                          Text(
                            'Reason: ${_label('${request['reason'] ?? 'other'}')}',
                          ),
                          if (amount != null)
                            Text(
                              'Refund amount: ${peso((num.tryParse('$amount') ?? 0) / 100)}',
                            ),
                          if ((request['explanation'] ?? '')
                              .toString()
                              .isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(request['explanation'].toString()),
                            ),
                          if (rejectedReason != null &&
                              rejectedReason.trim().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Admin decision: $rejectedReason',
                              style: TextStyle(color: colors.error),
                            ),
                          ],
                          if (attempts.isNotEmpty) ...[
                            const Divider(height: 24),
                            Text(
                              'Refund processing',
                              style: TextStyle(
                                color: colors.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            for (final item in attempts.whereType<Map>())
                              Padding(
                                padding: const EdgeInsets.only(top: 5),
                                child: Text(
                                  '${_label('${item['status'] ?? 'pending'}')} · ${peso((num.tryParse('${item['amount_cents'] ?? 0}') ?? 0) / 100)}',
                                ),
                              ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            'Requested ${request['created_at'] ?? ''}',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
