import 'dart:math';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/api.dart';
import '../core/util.dart';
import '../core/widgets.dart';
import 'addresses_screen.dart';

class RedeemPointsScreen extends StatefulWidget {
  const RedeemPointsScreen({super.key});

  @override
  State<RedeemPointsScreen> createState() => _RedeemPointsScreenState();
}

class _RedeemPointsScreenState extends State<RedeemPointsScreen> {
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  int _points = 0;
  bool _active = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait([
        Api.I.loyaltySummary(),
        Api.I.rewards(),
        Api.I.rewardRedemptions(),
      ]);
      final summary = values[0] as Map<String, dynamic>;
      final membership = summary['membership'] is Map
          ? Map<String, dynamic>.from(summary['membership'] as Map)
          : <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _active = membership['active'] == true;
        _points = (membership['points_balance'] as num?)?.toInt() ?? 0;
        _products = (values[1] as List<Map<String, dynamic>>)
            .where((reward) => reward['reward_type'] == 'free_product')
            .toList();
        _history = values[2] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Could not load redeemable products: $error';
          _loading = false;
        });
      }
    }
  }

  Future<void> _chooseFulfillment(Map<String, dynamic> reward) async {
    if (!_active) {
      _message('An active membership is required to redeem points.');
      return;
    }
    final cost = (reward['points_cost'] as num?)?.toInt() ?? 0;
    if (_points < cost) {
      _message('You need $cost points, but your balance is $_points.');
      return;
    }
    if ((reward['stock'] is num) && (reward['stock'] as num).toInt() <= 0) {
      _message('This product is currently out of stock.');
      return;
    }

    final fulfillment = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _productName(reward),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text('$cost points · current balance $_points'),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.delivery_dining_rounded),
                title: const Text('Delivery'),
                subtitle: const Text(
                  'Points cover the product; delivery fee is paid separately.',
                ),
                onTap: () => Navigator.pop(context, 'delivery'),
              ),
              ListTile(
                leading: const Icon(Icons.storefront_rounded),
                title: const Text('Store Pickup'),
                subtitle: const Text(
                  'Redeem at the shop with no delivery fee.',
                ),
                onTap: () => Navigator.pop(context, 'pickup'),
              ),
            ],
          ),
        ),
      ),
    );
    if (fulfillment == null || !mounted) return;

    Map<String, dynamic>? address;
    double deliveryFee = 0;
    if (fulfillment == 'delivery') {
      address = await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(
          builder: (_) => const AddressesScreen(selectionMode: true),
        ),
      );
      if (address == null || !mounted) return;
      setState(() => _busy = true);
      try {
        final quote = await Api.I.rewardDeliveryQuote(
          (reward['id'] as num).toInt(),
          (address['id'] as num).toInt(),
        );
        deliveryFee = (quote['delivery_fee'] as num?)?.toDouble() ?? 0;
      } on ApiException catch (error) {
        _message(error.message);
        return;
      } catch (_) {
        _message('Could not calculate the delivery fee. Please try again.');
        return;
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
    if (mounted) {
      await _confirmRedemption(reward, fulfillment, address, deliveryFee);
    }
  }

  Future<void> _confirmRedemption(
    Map<String, dynamic> reward,
    String fulfillment,
    Map<String, dynamic>? address,
    double deliveryFee,
  ) async {
    final cost = (reward['points_cost'] as num?)?.toInt() ?? 0;
    final details = StringBuffer(
      '${_productName(reward)}\n\n$cost points will be deducted.',
    );
    if (fulfillment == 'delivery') {
      details.write(
        '\nDelivery fee: ${peso(deliveryFee)} (separate from points).',
      );
      details.write(
        '\nDelivery to: ${address?['full_address'] ?? address?['label'] ?? 'Saved address'}',
      );
    } else {
      details.write('\nStore pickup: no delivery fee.');
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm product redemption'),
        content: Text(details.toString()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Go back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm redeem'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final key =
          '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
      final result = await Api.I.redeemReward(
        (reward['id'] as num).toInt(),
        key,
        fulfillmentType: fulfillment,
        addressId: address == null ? null : (address['id'] as num).toInt(),
      );
      final redemption = result['redemption'] is Map
          ? Map<String, dynamic>.from(result['redemption'] as Map)
          : result;
      await _load();
      if (mounted) await _showRedemption(redemption);
    } on ApiException catch (error) {
      _message(error.message);
      await _load();
    } catch (error) {
      _message('Could not redeem this product: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel(Map<String, dynamic> redemption) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel redemption?'),
        content: const Text(
          'If the order is still eligible for cancellation, the backend will restore your points once.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel redemption'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await Api.I.cancelRewardRedemption((redemption['id'] as num).toInt());
      await _load();
      _message('Redemption cancelled. Points were updated by the server.');
    } on ApiException catch (error) {
      _message(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showRedemption(Map<String, dynamic> redemption) async {
    final code = redemption['code']?.toString() ?? '';
    final fee = _doubleValue(redemption['delivery_fee']);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Redemption created'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (code.isNotEmpty)
                QrImageView(data: code, version: QrVersions.auto, size: 180),
              SelectableText(
                code,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text('Delivery fee: ${peso(fee)}'),
              Text('Order: ${redemption['order_number'] ?? 'Pickup'}'),
              Text(
                'Status: ${redemption['order_status'] ?? redemption['status'] ?? 'pending'}',
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  String _productName(Map<String, dynamic> reward) {
    final product = reward['product'];
    if (product is Map && product['name'] != null) {
      return product['name'].toString();
    }
    return reward['name']?.toString() ?? 'Redeemable product';
  }

  String? _productImage(Map<String, dynamic> reward) {
    final product = reward['product'];
    return (reward['image_url'] ??
            (product is Map ? product['image_url'] : null))
        ?.toString();
  }

  double _doubleValue(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Redeem Points')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: LayoutBuilder(
                builder: (context, constraints) => ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  children: [
                    Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1000),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _pointsBalanceCard(),
                              const SizedBox(height: 12),
                              _membershipStatusCard(),
                              if (_error != null) ...[
                                const SizedBox(height: 12),
                                Card(
                                  child: ListTile(
                                    leading: const Icon(
                                      Icons.cloud_off_rounded,
                                    ),
                                    title: Text(_error!),
                                    trailing: IconButton(
                                      onPressed: _load,
                                      icon: const Icon(Icons.refresh_rounded),
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 24),
                              _sectionHeading(
                                'Redeemable products',
                                subtitle: 'Choose a reward and redeem it with your points.',
                              ),
                              const SizedBox(height: 12),
                              if (_products.isEmpty)
                                _emptyState(
                                  icon: Icons.coffee_outlined,
                                  title: 'No rewards available yet',
                                  message: 'Check back soon for products you can redeem with points.',
                                )
                              else
                                GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount:
                                            constraints.maxWidth >= 720 ? 2 : 1,
                                        mainAxisSpacing: 14,
                                        crossAxisSpacing: 14,
                                        childAspectRatio:
                                            constraints.maxWidth >= 720
                                            ? 0.9
                                            : 0.84,
                                      ),
                                  itemCount: _products.length,
                                  itemBuilder: (context, index) =>
                                      _productCard(_products[index]),
                                ),
                              const SizedBox(height: 26),
                              _sectionHeading(
                                'Redemption history',
                                subtitle:
                                    'Your recent rewards and order status.',
                              ),
                              const SizedBox(height: 12),
                              if (_history.isEmpty)
                                _emptyState(
                                  icon: Icons.receipt_long_rounded,
                                  title: 'Your redemptions will appear here',
                                  message: 'Once you redeem a reward, you can track its reference and status here.',
                                )
                              else
                                for (final row in _history) _historyCard(row),
                              const SizedBox(height: 30),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      floatingActionButton: _busy
          ? const FloatingActionButton(
              onPressed: null,
              child: CircularProgressIndicator(),
            )
          : null,
    );
  }

  Widget _pointsBalanceCard() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      color: Theme.of(context).colorScheme.primary,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.3),
            ),
          ),
          child: Icon(
            Icons.stars_rounded,
            color: Theme.of(context).colorScheme.onPrimary,
            size: 30,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AVAILABLE POINTS',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.75),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.3,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '$_points',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontSize: 34,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                'points to enjoy your next reward',
                style: TextStyle(color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.75), fontSize: 12),
              ),
            ],
          ),
        ),
        Icon(
          Icons.local_cafe_rounded,
          color: Theme.of(context).colorScheme.onPrimary,
          size: 27,
        ),
      ],
    ),
  );

  Widget _membershipStatusCard() {
    final active = _active;
    final accent = active ? Colors.green.shade700 : Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              active ? Icons.verified_rounded : Icons.credit_card_rounded,
              color: accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  active ? 'Membership active' : 'Activate your membership',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  active
                      ? 'You can redeem available rewards.'
                      : 'An active membership is needed to redeem points.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (!active)
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
              child: const Text('View'),
            )
          else
            Icon(Icons.check_circle_rounded, color: Colors.green.shade700),
        ],
      ),
    );
  }

  Widget _sectionHeading(String title, {required String subtitle}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w900,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        subtitle,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 13,
        ),
      ),
    ],
  );

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String message,
  }) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Theme.of(context).dividerColor),
    ),
    child: Column(
      children: [
        Icon(icon, size: 38, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 10),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          message,
          textAlign: TextAlign.center,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
        ),
      ],
    ),
  );

  Widget _productCard(Map<String, dynamic> reward) {
    final cost = (reward['points_cost'] as num?)?.toInt() ?? 0;
    final stock = reward['stock'];
    final image = _productImage(reward);
    final inStock = stock == null || (stock is num && stock > 0);
    final canRedeem = _active && _points >= cost && inStock && !_busy;
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 1.75,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (image == null || image.isEmpty)
                  ColoredBox(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Icon(
                      Icons.coffee_rounded,
                      size: 42,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  NetImage(fixUrl(image)),
                Positioned(
                  top: 10,
                  right: 10,
                  child: _stockBadge(stock, inStock),
                ),
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.75),
                      ),
                    ),
                    child: Text(
                      '$cost points',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _productName(reward),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: Text(
                      (reward['description'] ??
                              'Redeem this favorite with your loyalty points.')
                          .toString(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.3,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: canRedeem
                          ? () => _chooseFulfillment(reward)
                          : null,
                      icon: const Icon(Icons.redeem_rounded, size: 18),
                      label: Text(
                        !inStock
                            ? 'Out of stock'
                            : (!_active
                                  ? 'Membership required'
                                  : 'Redeem Reward'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stockBadge(dynamic stock, bool inStock) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: inStock ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(
        color: inStock ? Colors.green.shade200 : Colors.red.shade200,
      ),
    ),
    child: Text(
      stock == null ? 'In stock' : (inStock ? 'Stock: $stock' : 'Out of stock'),
      style: TextStyle(
        color: inStock ? Colors.green.shade800 : Colors.red.shade800,
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
    ),
  );

  Widget _historyCard(Map<String, dynamic> row) {
    final fee = _doubleValue(row['delivery_fee']);
    final status = '${row['order_status'] ?? row['status'] ?? 'pending'}';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    Icons.redeem_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${row['reward_name'] ?? 'Redeemed product'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _historyStatus(status),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _historyDetail(
                  Icons.confirmation_number_outlined,
                  'Ref ${row['code'] ?? '-'}',
                ),
                _historyDetail(
                  Icons.storefront_outlined,
                  '${row['fulfillment_type'] ?? 'pickup'}',
                ),
                _historyDetail(
                  Icons.local_shipping_outlined,
                  'Delivery ${peso(fee)}',
                ),
                _historyDetail(
                  Icons.receipt_long_outlined,
                  'Order ${row['order_number'] ?? '-'}',
                ),
              ],
            ),
            if (status == 'pending') ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _busy ? null : () => _cancel(row),
                  icon: const Icon(Icons.cancel_outlined, size: 18),
                  label: const Text('Cancel redemption'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _historyStatus(String status) {
    final cancelled = status.toLowerCase() == 'cancelled';
    final color = cancelled ? Colors.red.shade700 : Colors.green.shade700;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _historyDetail(IconData icon, String text) => Container(
    constraints: const BoxConstraints(maxWidth: 270),
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    ),
  );
}
