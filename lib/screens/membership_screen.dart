import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/api.dart';
import '../core/widgets.dart';
import 'redeem_points_screen.dart';
import 'qrph_payment_screen.dart';

class MembershipScreen extends StatefulWidget {
  const MembershipScreen({super.key});

  @override
  State<MembershipScreen> createState() => _MembershipScreenState();
}

class _MembershipScreenState extends State<MembershipScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  Map<String, dynamic>? _membership;
  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _rewards = [];
  List<Map<String, dynamic>> _redemptions = [];
  List<Map<String, dynamic>> _savedAddresses = [];
  Map<String, dynamic>? _cardDelivery;
  int _monthlyPointsValue = 0;
  double _membershipPrice = 100;
  double _memberDiscountPercent = 10;
  bool _memberDiscountEnabled = true;
  bool _loading = true;
  bool _busy = false;
  bool _verifying = false;
  String? _error;
  String? _cardDesignUrl;
  String? _cardBackDesignUrl;
  late final AnimationController _cardFlipController;

  bool get _active => _membership?['active'] == true;
  int get _points => (_membership?['points_balance'] as num?)?.toInt() ?? 0;

  @override
  void initState() {
    super.initState();
    _cardFlipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cardFlipController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_active) _verifyPayment();
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
      if (!mounted) return;
      final summary = values[0] as Map<String, dynamic>;
      setState(() {
        _membershipPrice =
            (summary['membership_card_price'] as num?)?.toDouble() ?? 100;
        _memberDiscountPercent =
            (summary['membership_discount_percent'] as num?)?.toDouble() ?? 10;
        _memberDiscountEnabled = summary['membership_discount_enabled'] == true;
        _membership = summary['membership'] is Map
            ? Map<String, dynamic>.from(summary['membership'] as Map)
            : null;
        _cardDesignUrl =
            (summary['card_design_front_url'] ?? summary['card_design_url'])
                ?.toString();
        _cardBackDesignUrl = summary['card_design_back_url']?.toString();
        _transactions = (summary['transactions'] as List? ?? [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        _monthlyPointsValue = (summary['monthly_points'] as num?)?.toInt() ?? 0;
        _rewards = values[1] as List<Map<String, dynamic>>;
        _redemptions = values[2] as List<Map<String, dynamic>>;
        _loading = false;
      });
      try {
        final deliveryData = await Future.wait([
          Api.I.addresses(),
          Api.I.membershipCardDeliveries(),
        ]);
        if (!mounted) return;
        final items = (deliveryData[1] as Map<String, dynamic>)['items'];
        setState(() {
          _savedAddresses = deliveryData[0] as List<Map<String, dynamic>>;
          _cardDelivery = items is List && items.whereType<Map>().isNotEmpty
              ? Map<String, dynamic>.from(items.whereType<Map>().first)
              : null;
        });
      } catch (_) {
        // Membership details remain available if address loading is offline.
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load membership details: $error';
        _loading = false;
      });
    }
  }

  Future<void> _startPayment() async {
    setState(() => _busy = true);
    try {
      final checkout = await Api.I.startMembershipCheckout();
      if (!mounted) return;
      final activated = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => QrphPaymentScreen.membership(checkout: checkout),
        ),
      );
      if (activated == true && mounted) {
        await _load();
      } else if (mounted) {
        await _refreshQuietly();
      }
    } on ApiException catch (error) {
      _message(error.message);
    } catch (error) {
      _message('Could not start membership payment: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyPayment() async {
    if (_verifying || _active) return;
    _verifying = true;
    try {
      final summary = await Api.I.verifyMembershipPayment();
      if (!mounted) return;
      setState(() {
        _membershipPrice =
            (summary['membership_card_price'] as num?)?.toDouble() ??
            _membershipPrice;
        _memberDiscountPercent =
            (summary['membership_discount_percent'] as num?)?.toDouble() ??
            _memberDiscountPercent;
        _memberDiscountEnabled = summary['membership_discount_enabled'] == true;
        _membership = summary['membership'] is Map
            ? Map<String, dynamic>.from(summary['membership'] as Map)
            : null;
        _cardDesignUrl =
            (summary['card_design_front_url'] ?? summary['card_design_url'])
                ?.toString();
        _cardBackDesignUrl = summary['card_design_back_url']?.toString();
        _transactions = (summary['transactions'] as List? ?? [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        _monthlyPointsValue = (summary['monthly_points'] as num?)?.toInt() ?? 0;
      });
      if (_active) _message('Membership activated successfully.');
    } on ApiException catch (error) {
      _message(error.message);
    } finally {
      _verifying = false;
    }
  }

  Future<void> _refreshQuietly() async {
    try {
      final summary = await Api.I.loyaltySummary();
      if (!mounted) return;
      setState(() {
        _membershipPrice =
            (summary['membership_card_price'] as num?)?.toDouble() ??
            _membershipPrice;
        _memberDiscountPercent =
            (summary['membership_discount_percent'] as num?)?.toDouble() ??
            _memberDiscountPercent;
        _memberDiscountEnabled = summary['membership_discount_enabled'] == true;
        _membership = summary['membership'] is Map
            ? Map<String, dynamic>.from(summary['membership'] as Map)
            : null;
        _cardDesignUrl =
            (summary['card_design_front_url'] ?? summary['card_design_url'])
                ?.toString();
        _cardBackDesignUrl = summary['card_design_back_url']?.toString();
        _transactions = (summary['transactions'] as List? ?? [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      });
    } catch (_) {}
  }

  Future<void> _showRedemption(Map<String, dynamic> redemption) async {
    final code = redemption['code']?.toString() ?? '';
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reward redeemed'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (code.isNotEmpty)
              QrImageView(
                data: code,
                version: QrVersions.auto,
                size: 190,
                backgroundColor: Colors.white,
              ),
            const SizedBox(height: 10),
            SelectableText(
              code,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text('Show this code to staff when claiming your reward.'),
          ],
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

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Membership & Rewards')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  if (_error != null)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.error_outline),
                        title: Text(_error!),
                        trailing: IconButton(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                        ),
                      ),
                    ),
                  _membershipCard(colors),
                  const SizedBox(height: 14),
                  _cardDeliverySection(colors),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _metricCard(
                          'Current points',
                          '$_points',
                          Icons.stars_rounded,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _metricCard(
                          'Earned this month',
                          '$_monthlyPointsValue',
                          Icons.calendar_month_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _sectionTitle('Redeem points'),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.redeem_rounded),
                      title: const Text('Browse redeemable products'),
                      subtitle: Text(
                        '${_rewards.where((reward) => reward['reward_type'] == 'free_product').length} products available · $_points points',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const RedeemPointsScreen(),
                        ),
                      ),
                    ),
                  ),
                  if (_rewards.any(
                    (reward) => reward['reward_type'] != 'free_product',
                  )) ...[
                    const SizedBox(height: 16),
                    _sectionTitle('Other rewards'),
                    for (final reward in _rewards.where(
                      (reward) => reward['reward_type'] != 'free_product',
                    ))
                      _rewardCard(reward),
                  ],
                  const SizedBox(height: 22),
                  _sectionTitle('Redemption history'),
                  if (_redemptions.isEmpty)
                    const _EmptyNotice(
                      'Your redeemed rewards will appear here.',
                    ),
                  for (final redemption in _redemptions)
                    _redemptionRow(redemption),
                  const SizedBox(height: 22),
                  _sectionTitle('Points history'),
                  if (_transactions.isEmpty)
                    const _EmptyNotice(
                      'Points earned and redeemed will appear here.',
                    ),
                  for (final transaction in _transactions)
                    _transactionRow(transaction),
                ],
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

  Widget _cardDeliverySection(ColorScheme colors) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_shipping_outlined, color: colors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Physical Membership Card',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_cardDelivery != null) ...[
            Text(
              'Delivery status: ${_statusLabel(_cardDelivery!['status'])}',
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (_cardDelivery!['address'] is Map)
              Text(
                '${(_cardDelivery!['address'] as Map)['full_address'] ?? ''}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
          ] else ...[
            Text(
              'Request delivery of your paid membership card to a saved address.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: !_active || _busy || _savedAddresses.isEmpty
                    ? null
                    : _requestCardDelivery,
                icon: const Icon(Icons.location_on_outlined),
                label: Text(
                  _savedAddresses.isEmpty
                      ? 'Add a saved address first'
                      : 'Request Card Delivery',
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );

  String _statusLabel(dynamic value) {
    switch (value?.toString()) {
      case 'pending':
        return 'Pending';
      case 'preparing_card':
        return 'Preparing Card';
      case 'ready_for_delivery':
        return 'Ready for Delivery';
      case 'out_for_delivery':
        return 'Out for Delivery';
      case 'delivered':
        return 'Delivered';
      default:
        return 'Pending';
    }
  }

  Future<void> _requestCardDelivery() async {
    final notes = TextEditingController();
    Map<String, dynamic>? selected = _savedAddresses.firstWhere(
      (address) => address['is_default'] == true,
      orElse: () => _savedAddresses.first,
    );
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final lat = double.tryParse('${selected?['latitude'] ?? ''}');
          final lng = double.tryParse('${selected?['longitude'] ?? ''}');
          final pin = lat != null && lng != null ? LatLng(lat, lng) : null;
          final colors = Theme.of(context).colorScheme;
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                0,
                16,
                16 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * .78,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Review Delivery Address',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<Map<String, dynamic>>(
                      initialValue: selected,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Saved address',
                      ),
                      items: _savedAddresses.map((address) {
                        final label = address['label']?.toString() ?? 'Address';
                        final full =
                            address['formatted_address'] ??
                            address['full_address'] ??
                            '';
                        return DropdownMenuItem(
                          value: address,
                          child: Text(
                            '$label · $full',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (address) =>
                          setSheetState(() => selected = address),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: pin == null
                          ? Center(
                              child: Text(
                                'This saved address has no map coordinates.',
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: FlutterMap(
                                options: MapOptions(
                                  initialCenter: pin,
                                  initialZoom: 16,
                                ),
                                children: [
                                  TileLayer(
                                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                    userAgentPackageName:
                                        'com.kjmcoffeebrew.app',
                                  ),
                                  MarkerLayer(
                                    markers: [
                                      Marker(
                                        point: pin,
                                        width: 48,
                                        height: 48,
                                        child: Icon(
                                          Icons.location_pin,
                                          color: colors.error,
                                          size: 44,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${selected?['formatted_address'] ?? selected?['full_address'] ?? ''}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (selected?['barangay'] != null ||
                        selected?['city'] != null)
                      Text(
                        [
                              selected?['barangay'],
                              selected?['city'],
                              selected?['province'],
                            ]
                            .where(
                              (part) =>
                                  part != null && '$part'.trim().isNotEmpty,
                            )
                            .join(', '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    if (pin != null)
                      Text(
                        'Map pin: ${pin.latitude.toStringAsFixed(6)}, ${pin.longitude.toStringAsFixed(6)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    TextField(
                      controller: notes,
                      decoration: const InputDecoration(
                        labelText: 'Delivery notes or landmark (optional)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: selected == null
                                ? null
                                : () => Navigator.pop(sheetContext, {
                                    'address': selected,
                                    'notes': notes.text.trim(),
                                  }),
                            child: const Text('Submit Request'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    final address = result?['address'];
    if (address is! Map) {
      notes.dispose();
      return;
    }
    setState(() => _busy = true);
    try {
      final response = await Api.I.requestMembershipCardDelivery(
        addressId: (address['id'] as num).toInt(),
        deliveryNotes: result?['notes']?.toString(),
      );
      if (!mounted) return;
      setState(() => _cardDelivery = response);
      _message('Membership card delivery request submitted.');
    } on ApiException catch (error) {
      _message(error.message);
    } finally {
      notes.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _membershipCard(ColorScheme colors) {
    final memberId =
        _membership?['member_id']?.toString() ?? 'Issued after payment';
    final latestPayment = _membership?['latest_payment'];
    final paymentPending =
        latestPayment is Map && latestPayment['status'] == 'pending';
    final paymentAmount = latestPayment is Map && latestPayment['amount'] is num
        ? (latestPayment['amount'] as num).toDouble()
        : _membershipPrice;
    final memberSince = _formatMemberSince(
      _active
          ? (_membership?['member_since'] ??
                _membership?['activated_at'] ??
                _membership?['created_at'])
          : null,
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          children: [
            AnimatedBuilder(
              animation: _cardFlipController,
              builder: (context, _) {
                final angle = _cardFlipController.value * pi;
                final showBack = angle >= pi / 2;
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    // Match the bundled front artwork so neither side is stretched.
                    final height = width / (1832 / 858);
                    return SizedBox(
                      width: width,
                      height: height,
                      child: Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.0012)
                          ..rotateY(angle),
                        child: Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.rotationY(showBack ? pi : 0),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: showBack
                                ? _membershipCardBack()
                                : _membershipCardFront(
                                    width: width,
                                    height: height,
                                    memberId: memberId,
                                    memberSince: memberSince,
                                  ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: () {
                if (_cardFlipController.value < 0.5) {
                  _cardFlipController.forward();
                } else {
                  _cardFlipController.reverse();
                }
              },
              icon: AnimatedBuilder(
                animation: _cardFlipController,
                builder: (_, _) => Icon(
                  _cardFlipController.value < 0.5
                      ? Icons.flip_rounded
                      : Icons.flip_camera_android_rounded,
                ),
              ),
              label: AnimatedBuilder(
                animation: _cardFlipController,
                builder: (_, _) => Text(
                  _cardFlipController.value < 0.5
                      ? 'View card back'
                      : 'View card front',
                ),
              ),
            ),
            if (!_active) ...[
              const SizedBox(height: 4),
              Text(
                _membership == null
                    ? 'Pay PHP ${paymentAmount.toStringAsFixed(2)} to activate your membership card.'
                    : 'Membership is ${'${_membership!['status'] ?? 'inactive'}'.toLowerCase()}.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _busy ? null : _startPayment,
                icon: Icon(
                  paymentPending
                      ? Icons.qr_code_2_rounded
                      : Icons.credit_card_rounded,
                ),
                label: Text(
                  paymentPending
                      ? 'View QR / Check Payment'
                      : 'Get membership - PHP ${paymentAmount.toStringAsFixed(2)}',
                ),
              ),
              if (_memberDiscountEnabled && _memberDiscountPercent > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Active members receive ${_memberDiscountPercent.toStringAsFixed(_memberDiscountPercent % 1 == 0 ? 0 : 2)}% off eligible products.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ),
              if (paymentPending && latestPayment['checkout_url'] != null)
                TextButton(
                  onPressed: _startPayment,
                  child: const Text('Open payment page again'),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _membershipCardFront({
    required double width,
    required double height,
    required String memberId,
    required String memberSince,
  }) {
    final status = _active
        ? 'ACTIVE MEMBER'
        : (_membership == null
              ? 'NOT ACTIVE'
              : '${_membership!['status'] ?? 'PENDING'}'.toUpperCase());
    final scale = (width / 420).clamp(0.72, 1.5).toDouble();
    final userName = '${Api.I.user?['name'] ?? 'Customer'}';

    return Stack(
      fit: StackFit.expand,
      children: [
        _cardBackground(),
        // Cover the artwork's decorative tier text with the real membership state.
        Positioned(
          left: width * .65,
          top: height * .275,
          width: width * .30,
          height: height * .13,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: width * .012,
                vertical: height * .008,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                border: Border.all(color: Colors.white, width: 1.2),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                status,
                maxLines: 1,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .8,
                  fontSize: 11 * scale,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: width * .055,
          top: height * .51,
          width: width * .47,
          height: height * .45,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width * .47,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    userName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 17 * scale,
                      shadows: const [
                        Shadow(color: Colors.black54, blurRadius: 4),
                      ],
                    ),
                  ),
                  SizedBox(height: height * .008),
                  Text(
                    'MEMBER ID  $memberId',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10 * scale,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: height * .008),
                  Text(
                    '${_active ? _points : 0} POINTS',
                    maxLines: 1,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13 * scale,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    'MEMBER SINCE  $memberSince',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9 * scale,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Replace the artwork's sample QR with the customer's real member QR.
        Positioned(
          left: width * .55,
          top: height * .485,
          width: width * .185,
          height: height * .425,
          child: Container(
            padding: EdgeInsets.all(width * .009),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: _active
                ? QrImageView(
                    data: memberId,
                    version: QrVersions.auto,
                    backgroundColor: Colors.white,
                    padding: EdgeInsets.zero,
                  )
                : Icon(
                    Icons.lock_outline_rounded,
                    color: Colors.black,
                    size: width * .07,
                  ),
          ),
        ),
      ],
    );
  }

  Widget _cardBackground() {
    return _cardDesignImage(_cardDesignUrl, 'assets/images/card.png');
  }

  Widget _membershipCardBack() =>
      _cardDesignImage(_cardBackDesignUrl, 'assets/images/card1.png');

  Widget _cardDesignImage(String? imageUrl, String fallbackAsset) {
    final fallback = Image.asset(
      fallbackAsset,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const ColoredBox(
        color: Color(0xFFF5F5F5),
        child: Center(child: Icon(Icons.credit_card_rounded, size: 48)),
      ),
    );
    final url = imageUrl?.trim();
    if (url == null || url.isEmpty) return fallback;

    return Image.network(
      fixUrl(url),
      fit: BoxFit.cover,
      headers: const {'ngrok-skip-browser-warning': 'true'},
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Stack(
          fit: StackFit.expand,
          children: [
            fallback,
            const Center(child: CircularProgressIndicator()),
          ],
        );
      },
      errorBuilder: (_, _, _) => fallback,
    );
  }

  String _formatMemberSince(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return 'Pending activation';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  Widget _metricCard(String title, String value, IconData icon) => Card(
    child: Padding(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
          ),
          Text(
            title,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Text(
      title,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
    ),
  );

  Future<void> _redeem(Map<String, dynamic> reward) async {
    final cost = (reward['points_cost'] as num?)?.toInt() ?? 0;
    if (!_active || _points < cost) {
      _message('An active membership with at least $cost points is required.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Redeem reward?'),
        content: Text(
          'Use $cost points for ${reward['name'] ?? 'this reward'}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Redeem'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final key =
          '${DateTime.now().microsecondsSinceEpoch}-${DateTime.now().millisecondsSinceEpoch}';
      final result = await Api.I.redeemReward(
        (reward['id'] as num).toInt(),
        key,
      );
      await _load();
      if (mounted) {
        await _showRedemption(
          result['redemption'] is Map
              ? Map<String, dynamic>.from(result['redemption'] as Map)
              : result,
        );
      }
    } on ApiException catch (error) {
      _message(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _rewardCard(Map<String, dynamic> reward) {
    final cost = (reward['points_cost'] as num?)?.toInt() ?? 0;
    final available = _active && _points >= cost && !_busy;
    final product = reward['product'];
    final image = reward['image_url']?.toString();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          SizedBox(
            width: 88,
            height: 96,
            child: image == null || image.isEmpty
                ? const Icon(Icons.card_giftcard_rounded, size: 40)
                : NetImage(fixUrl(image)),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${reward['name'] ?? 'Reward'}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  if ((reward['description'] ?? '').toString().isNotEmpty)
                    Text(
                      '${reward['description']}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  Text(
                    '$cost points',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (product is Map && product['name'] != null)
                    Text(
                      'For ${product['name']}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: FilledButton(
              onPressed: available ? () => _redeem(reward) : null,
              child: const Text('Redeem'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _redemptionRow(Map<String, dynamic> row) => Card(
    child: ListTile(
      leading: const Icon(Icons.redeem_rounded),
      title: Text('${row['reward_name'] ?? 'Reward'}'),
      subtitle: Text(
        '${row['code'] ?? ''} Â· ${row['points_spent'] ?? 0} points',
      ),
      trailing: Text(
        '${row['status'] ?? 'pending'}'.toUpperCase(),
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
      ),
      onTap: () => _showRedemption(row),
    ),
  );

  Widget _transactionRow(Map<String, dynamic> row) {
    final points = (row['points'] as num?)?.toInt() ?? 0;
    final date = DateTime.tryParse('${row['created_at']}')?.toLocal();
    return Card(
      child: ListTile(
        dense: true,
        leading: Icon(
          points >= 0 ? Icons.add_circle_outline : Icons.remove_circle_outline,
          color: points >= 0 ? Colors.green : Colors.deepOrange,
        ),
        title: Text(
          '${row['description'] ?? row['type'] ?? 'Points activity'}',
        ),
        subtitle: Text(
          '${row['order_number'] ?? ''}${date == null ? '' : ' Â· ${date.month}/${date.day}/${date.year}'}',
        ),
        trailing: Text(
          '${points > 0 ? '+' : ''}$points',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _EmptyNotice extends StatelessWidget {
  final String text;
  const _EmptyNotice(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      text,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}
