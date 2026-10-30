import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/realtime.dart';
import '../core/theme.dart';
import '../core/util.dart';
import '../core/widgets.dart';
import '../state/nav.dart';
import 'order_contents_screen.dart';
import 'payment_screen.dart';
import 'rider_chat_screen.dart';
import 'customer_service_sheet.dart';

String _timeTextInManila(dynamic value) {
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) return '';
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return '';
  // Laravel's status log query can return a naive UTC string. Treat naive
  // values as UTC, then display Asia/Manila time regardless of device zone.
  final hasZone = RegExp(
    r'(Z|[+-]\d{2}:?\d{2})$',
    caseSensitive: false,
  ).hasMatch(raw);
  final utc = hasZone
      ? parsed.toUtc()
      : DateTime.utc(
          parsed.year,
          parsed.month,
          parsed.day,
          parsed.hour,
          parsed.minute,
          parsed.second,
          parsed.millisecond,
          parsed.microsecond,
        );
  final manila = utc.add(const Duration(hours: 8));
  final hour = manila.hour % 12 == 0 ? 12 : manila.hour % 12;
  final minute = manila.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${manila.hour >= 12 ? 'PM' : 'AM'}';
}

class OrderDetailScreen extends StatefulWidget {
  final int id;
  const OrderDetailScreen({super.key, required this.id});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  Map<String, dynamic>? _o;
  Map<String, dynamic>? _t;
  bool _loading = true;
  String? _error;
  StreamSubscription<Map<String, dynamic>>? _liveSubscription;
  Timer? _trackingTimer;
  bool _refreshing = false;
  final MapController _mapController = MapController();
  int _rating = 5;
  final _comment = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
    _startTrackingPolling();
    Realtime.I.connect();
    _liveSubscription = Realtime.I.updates.listen((event) {
      if (const {
        'order',
        'delivery',
        'payment',
        'rider',
      }.contains(event['kind'])) {
        _load(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _liveSubscription?.cancel();
    _trackingTimer?.cancel();
    _comment.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final t = await Api.I.tracking(widget.id);
      final trackingOrder = t['order'];
      final o = trackingOrder is Map
          ? Map<String, dynamic>.from(trackingOrder)
          : await Api.I.order(widget.id);
      if (!mounted) return;
      final finished =
          _isFinalStatus('${o['status']}') ||
          _isFinalStatus(t['delivery_status']?.toString() ?? '');
      setState(() {
        _o = o;
        _t = finished ? _withoutLiveTracking(t) : t;
        _loading = false;
        _error = null;
      });
      if (finished) {
        _trackingTimer?.cancel();
        _trackingTimer = null;
        await _liveSubscription?.cancel();
        _liveSubscription = null;
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (!silent) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } finally {
      _refreshing = false;
    }
  }

  bool _isFinalStatus(String status) => const {
    'delivered',
    'completed',
    'cancelled',
    'rejected',
  }.contains(status);

  bool _isTrackingFinished() =>
      _isFinalStatus(_o?['status']?.toString() ?? '') ||
      _isFinalStatus(_t?['delivery_status']?.toString() ?? '');

  bool _isActiveDeliveryStatus(String status) =>
      const {'picked_up', 'on_the_way', 'out_for_delivery'}.contains(status);

  Map<String, dynamic> _withoutLiveTracking(Map<String, dynamic> tracking) => {
    ...tracking,
    'rider': null,
    'route': {'status': 'finished', 'points': <dynamic>[]},
  };

  void _startTrackingPolling() {
    _trackingTimer?.cancel();
    _trackingTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted && !_isTrackingFinished()) {
        _load(silent: true);
      }
    });
  }

  Future<void> _cancel() async {
    if (_busy || _o?['status'] != 'pending' || _o?['can_cancel'] != true) {
      return;
    }
    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    const cancellationReasons = [
      'Change Address',
      'Change Payment Method',
      'Wrong Order',
      'Others',
    ];
    String? selectedReason;
    String? reason;
    try {
      reason = await showDialog<String>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 24,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.errorContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.free_cancellation_rounded,
                            color: Theme.of(context).colorScheme.error,
                            size: 29,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Cancel this order?',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Are you sure you want to cancel this order?',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 20),
                      DropdownButtonFormField<String>(
                        initialValue: selectedReason,
                        decoration: const InputDecoration(
                          labelText: 'Reason for cancellation',
                          prefixIcon: Icon(Icons.chat_bubble_outline_rounded),
                        ),
                        items: cancellationReasons
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setDialogState(() => selectedReason = value),
                        validator: (value) => value == null
                            ? 'Please choose a cancellation reason.'
                            : null,
                      ),
                      if (selectedReason == 'Others') ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: reasonController,
                          minLines: 2,
                          maxLines: 4,
                          maxLength: 240,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Please explain',
                            alignLabelWithHint: true,
                          ),
                          validator: (value) =>
                              selectedReason == 'Others' &&
                                  (value == null || value.trim().isEmpty)
                              ? 'Please explain your reason.'
                              : null,
                        ),
                      ],
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () {
                          if (formKey.currentState?.validate() ?? false) {
                            final submittedReason = selectedReason == 'Others'
                                ? 'Others: ${reasonController.text.trim()}'
                                : selectedReason!;
                            Navigator.pop(ctx, submittedReason);
                          }
                        },
                        icon: const Icon(Icons.cancel_outlined),
                        label: const Text('Yes, Cancel Order'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.error,
                          foregroundColor: Theme.of(context)
                              .colorScheme
                              .onError,
                          minimumSize: const Size.fromHeight(50),
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        child: const Text('Keep My Order'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    } finally {
      reasonController.dispose();
    }
    if (reason == null || reason.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      await Api.I.cancel(widget.id, reason: reason);
      await _load();
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Your order has been cancelled successfully.'),
          ),
        );
        // Return to the root tab even when tracking was opened from a
        // notification or post-checkout route.
        final navigator = Navigator.of(context);
        navigator.popUntil((route) => route.isFirst);
        rootTab.value = 3;
      }
    } on ApiException catch (e) {
      final noLongerCancellable = e.message.toLowerCase().contains(
        'can no longer be cancelled',
      );
      if (noLongerCancellable) await _load();
      if (!mounted) return;
      final message = noLongerCancellable
          ? 'This order can no longer be cancelled because it has already progressed.'
          : e.message;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pay() async {
    setState(() => _busy = true);
    try {
      final fresh = await Api.I.payOrder(widget.id);
      if (!mounted) return;
      if (fresh['status'] != 'awaiting_payment') {
        await _load();
        return;
      }
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => PaymentScreen(order: fresh)));
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review() async {
    setState(() => _busy = true);
    try {
      await Api.I.review(widget.id, _rating, _comment.text.trim());
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thank you for your review!')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = _o;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface
            .withValues(alpha: .94),
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () {
            final navigator = Navigator.of(context);
            if (navigator.canPop()) {
              navigator.pop();
            } else {
              rootTab.value = 3;
            }
          },
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Order Tracking'),
        actions: [
          IconButton(
            tooltip: 'Customer support',
            onPressed: () => showCustomerServiceSheet(context),
            icon: const Icon(Icons.support_agent_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : o == null
          ? Center(child: Text(_error ?? 'An error occurred.'))
          : _body(o, _t ?? {}),
    );
  }

  Future<void> _openRiderChat() async {
    final rider = _t?['rider'];
    if (rider is! Map || rider['name'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Rider chat will be available when a rider is assigned.',
          ),
        ),
      );
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => RiderChatScreen(targetId: widget.id, isRider: false),
      ),
    );
  }

  Future<void> _contactRider(String phone) async {
    await _launchContact(Uri(scheme: 'tel', path: phone));
  }

  Future<void> _launchContact(Uri uri) async {
    try {
      if (!await launchUrl(uri) && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the requested app.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the requested app.')),
        );
      }
    }
  }

  Widget _body(Map<String, dynamic> o, Map<String, dynamic> t) {
    final status = '${o['status']}';
    final type = '${o['order_type']}';
    final isDelivery = type == 'delivery';
    final rider = t['rider'] is Map
        ? Map<String, dynamic>.from(t['rider'] as Map)
        : null;
    final riderPhone = rider?['phone']?.toString().trim() ?? '';
    final dest = t['destination'] is Map
        ? Map<String, dynamic>.from(t['destination'] as Map)
        : <String, dynamic>{};
    final shop = t['shop'] is Map
        ? Map<String, dynamic>.from(t['shop'] as Map)
        : <String, dynamic>{};
    final timeline = t['timeline'] is List
        ? mapList(t['timeline'])
        : <Map<String, dynamic>>[];
    LatLng? point(Map<String, dynamic> value) {
      if (value['lat'] == null || value['lng'] == null) return null;
      return LatLng(dbl(value['lat']), dbl(value['lng']));
    }

    final destinationPoint = point(dest);
    final rawShopPoint = point(shop);
    final shopPoint =
        rawShopPoint != null &&
            rawShopPoint.latitude == 0 &&
            rawShopPoint.longitude == 0
        ? null
        : rawShopPoint;
    final riderPoint = rider == null ? null : point(rider);
    final routeData = t['route'] is Map
        ? Map<String, dynamic>.from(t['route'] as Map)
        : <String, dynamic>{};
    final routePoints = routeData['points'] is List
        ? mapList(routeData['points'])
              .where((p) => p['lat'] != null && p['lng'] != null)
              .map((p) => LatLng(dbl(p['lat']), dbl(p['lng'])))
              .toList()
        : <LatLng>[];
    final routeMinutes = routeData['duration_seconds'] is num
        ? math
              .max(1, ((routeData['duration_seconds'] as num) / 60).ceil())
              .toInt()
        : null;
    final routeKm = routeData['distance_meters'] is num
        ? ((routeData['distance_meters'] as num) / 1000).toStringAsFixed(1)
        : null;
    final lastLocationAt = DateTime.tryParse(
      '${rider?['last_updated_at'] ?? ''}',
    )?.toLocal();
    final isLive =
        riderPoint != null &&
        lastLocationAt != null &&
        DateTime.now().difference(lastLocationAt).inSeconds <= 30;
    final points = <LatLng>[...routePoints, ?destinationPoint, ?riderPoint];
    final isCancelled = status == 'cancelled' || status == 'rejected';
    final isDelivered = status == 'delivered' || status == 'completed';
    final isTerminal = _isFinalStatus(status);
    final isOnRoute = _isActiveDeliveryStatus(status);
    final currentStep = isCancelled
        ? -1
        : isDelivered
        ? 3
        : isOnRoute || status == 'ready' || status == 'rider_assigned'
        ? 2
        : status == 'preparing'
        ? 1
        : status == 'confirmed'
        ? 0
        : -1;
    final address = (o['delivery_address'] ?? dest['address'] ?? '').toString();

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: _trackingMapBackground(
            isDelivery: isDelivery,
            isTerminal: isTerminal,
            destinationPoint: destinationPoint,
            shopPoint: shopPoint,
            riderPoint: riderPoint,
            routePoints: routePoints,
            mapPoints: points,
            address: address,
          ),
        ),
        if (isDelivery && !isTerminal && destinationPoint != null)
          Positioned(
            top: MediaQuery.paddingOf(context).top + kToolbarHeight + 8,
            right: 14,
            child: _routeMapBadge(
              context,
              live: isLive,
              updatedAt: lastLocationAt,
              eta: routeMinutes,
              distance: routeKm,
              error: routeData['error']?.toString(),
            ),
          ),
        if (isDelivery &&
            !isTerminal &&
            riderPoint != null &&
            destinationPoint != null)
          Positioned(
            top: MediaQuery.paddingOf(context).top + kToolbarHeight + 62,
            left: 14,
            child: _riderDistanceBadge(context, riderPoint, destinationPoint),
          ),
        if (isDelivery && destinationPoint != null)
          Positioned(
            right: 14,
            top: MediaQuery.sizeOf(context).height * .28,
            child: _trackingMapControls(
              riderPoint ?? destinationPoint,
              riderPoint != null,
            ),
          ),
        DraggableScrollableSheet(
          initialChildSize: .48,
          minChildSize: .28,
          maxChildSize: .94,
          snap: true,
          snapSizes: const [.48, .94],
          builder: (context, scrollController) => Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface
                  .withValues(alpha: .98),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(26),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .16),
                  blurRadius: 18,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 9, 16, 28),
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${o['order_number'] ?? 'Order'}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Text(
                      isDelivery && _isActiveDeliveryStatus(status)
                          ? 'Live delivery tracking'
                          : _statusText(status, type),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (isDelivery && !isTerminal)
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 26,
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                                foregroundImage:
                                    rider?['avatar_url'] != null &&
                                        '${rider?['avatar_url']}'.isNotEmpty
                                    ? NetworkImage(
                                        fixUrl('${rider?['avatar_url']}'),
                                      )
                                    : null,
                                child:
                                    rider?['avatar_url'] == null ||
                                        '${rider?['avatar_url']}'.isEmpty
                                    ? Icon(
                                        Icons.delivery_dining_rounded,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        size: 28,
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${rider?['name'] ?? 'Waiting for rider'}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      rider == null
                                          ? 'A rider will be assigned when your order is ready.'
                                          : rider['role']?.toString() ??
                                                'Delivery rider',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                    ),
                                    if (riderPhone.isNotEmpty)
                                      Text(
                                        riderPhone,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                      ),
                                    if (riderPoint != null)
                                      Text(
                                        isLive
                                            ? 'Live location · updated ${_timeTextInManila(rider?['last_updated_at'])}'
                                            : 'Last location · ${lastLocationAt == null ? 'waiting for update' : _timeTextInManila(lastLocationAt.toUtc().toIso8601String())}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isLive
                                              ? Colors.green.shade700
                                              : Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: riderPhone.isEmpty
                                      ? null
                                      : () => _contactRider(riderPhone),
                                  icon: const Icon(
                                    Icons.call_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('Call'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton.tonalIcon(
                                  onPressed: _openRiderChat,
                                  icon: const Icon(
                                    Icons.chat_bubble_outline_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('Rider Chat'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                Card(
                  elevation: 1,
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (isDelivery)
                              Image.asset(
                                'assets/images/delivery.png',
                                width: 48,
                                height: 48,
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) => Icon(
                                  Icons.delivery_dining_rounded,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 34,
                                ),
                              )
                            else
                              Icon(
                                Icons.storefront_rounded,
                                color: Theme.of(context).colorScheme.primary,
                                size: 34,
                              ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    status == 'cancelled'
                                        ? 'Your order has been cancelled'
                                        : status == 'rejected'
                                        ? 'Your order was rejected'
                                        : isDelivered
                                        ? 'Your order has been delivered!'
                                        : isOnRoute
                                        ? 'Your order is on the way!'
                                        : status == 'pending'
                                        ? 'Waiting for shop confirmation'
                                        : 'Your order is being prepared',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(_statusText(status, type)),
                                ],
                              ),
                            ),
                            if (routeMinutes != null && isOnRoute)
                              Text(
                                '~$routeMinutes min',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            for (var step = 0; step < 4; step++) ...[
                              Expanded(
                                child: _trackingStep(
                                  const [
                                    'Confirmed',
                                    'Preparing',
                                    'Ready',
                                    'Delivered',
                                  ][step],
                                  step,
                                  currentStep,
                                  isCurrent:
                                      (isOnRoute && step == 2) ||
                                      step == currentStep,
                                ),
                              ),
                              if (step < 3)
                                _progressLine(
                                  step < currentStep
                                      ? 1
                                      : isOnRoute && step == 2
                                      ? .45
                                      : 0,
                                ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Delivery Updates',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (timeline.isEmpty)
                          Text(
                            'Order updates will appear here as the shop changes its status.',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          )
                        else
                          for (final entry in timeline)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.check_circle_rounded,
                                    size: 18,
                                    color: statusColor('${entry['status']}'),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _statusText('${entry['status']}', type),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    _timeTextInManila(entry['at']),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 46,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => OrderContentsScreen(
                          orderId: widget.id,
                          initialOrder: o,
                        ),
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.primary,
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    icon: const Icon(Icons.receipt_long_outlined, size: 18),
                    label: const Text('View Order Details'),
                  ),
                ),
                const SizedBox(height: 12),
                if (o['can_pay'] == true)
                  FilledButton(
                    onPressed: _busy ? null : _pay,
                    child: Text('Pay via GCash  |  ${peso(dbl(o['total']))}'),
                  ),
                if (status == 'pending' && o['can_cancel'] == true)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      foregroundColor: Colors.red,
                    ),
                    onPressed: _busy ? null : _cancel,
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cancel_outlined),
                    label: Text(_busy ? 'Cancelling…' : 'Cancel order'),
                  ),
                if ((status == 'delivered' || status == 'completed') &&
                    o['has_review'] != true)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          const Text(
                            'How was your order?',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (var i = 1; i <= 5; i++)
                                IconButton(
                                  onPressed: () => setState(() => _rating = i),
                                  icon: Icon(
                                    i <= _rating
                                        ? Icons.star
                                        : Icons.star_border,
                                    color: Colors.amber,
                                    size: 32,
                                  ),
                                ),
                            ],
                          ),
                          TextField(
                            controller: _comment,
                            decoration: const InputDecoration(
                              hintText: 'Comment (optional)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          FilledButton(
                            onPressed: _busy ? null : _review,
                            child: const Text('Submit review'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _trackingMapBackground({
    required bool isDelivery,
    required bool isTerminal,
    required LatLng? destinationPoint,
    required LatLng? shopPoint,
    required LatLng? riderPoint,
    required List<LatLng> routePoints,
    required List<LatLng> mapPoints,
    required String address,
  }) {
    if (!isDelivery || destinationPoint == null) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: isDelivery
            ? _mapPlaceholder(address)
            : Center(
                child: Icon(
                  Icons.storefront_rounded,
                  size: 58,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
      );
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: riderPoint ?? destinationPoint,
        initialZoom: 15,
        initialCameraFit: mapPoints.length > 1
            ? CameraFit.bounds(
                bounds: LatLngBounds.fromPoints(mapPoints),
                padding: const EdgeInsets.fromLTRB(36, 130, 36, 300),
                maxZoom: 16,
              )
            : null,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.kjmcoffeebrew.app',
        ),
        if (!isTerminal && routePoints.length > 1)
          PolylineLayer(
            polylines: [
              Polyline(
                points: routePoints,
                color: Theme.of(context).colorScheme.primary,
                strokeWidth: 6,
                borderColor: Colors.white,
                borderStrokeWidth: 2,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            if (shopPoint != null)
              Marker(
                point: shopPoint,
                width: 42,
                height: 48,
                child: _mapPin(
                  Icons.storefront_rounded,
                  Theme.of(context).colorScheme.primary,
                ),
              ),
            Marker(
              point: destinationPoint,
              width: 42,
              height: 48,
              child: _mapPin(
                Icons.home_rounded,
                Theme.of(context).colorScheme.primary,
              ),
            ),
            if (!isTerminal && riderPoint != null)
              Marker(
                point: riderPoint,
                width: 76,
                height: 60,
                child: _deliveryMapMarker(context),
              ),
          ],
        ),
        RichAttributionWidget(
          attributions: [
            TextSourceAttribution('OpenStreetMap contributors'),
            TextSourceAttribution('Route via OSRM'),
          ],
        ),
      ],
    );
  }

  Widget _trackingMapControls(LatLng center, bool hasRider) => Material(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(18),
    elevation: 3,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Recenter map',
          onPressed: () => _mapController.move(center, 15),
          icon: Icon(hasRider ? Icons.my_location_rounded : Icons.home_rounded),
        ),
        const Divider(height: 1),
        IconButton(
          tooltip: 'Zoom in',
          onPressed: () => _mapController.move(
            _mapController.camera.center,
            (_mapController.camera.zoom + 1).clamp(3, 18),
          ),
          icon: const Icon(Icons.add_rounded),
        ),
        IconButton(
          tooltip: 'Zoom out',
          onPressed: () => _mapController.move(
            _mapController.camera.center,
            (_mapController.camera.zoom - 1).clamp(3, 18),
          ),
          icon: const Icon(Icons.remove_rounded),
        ),
      ],
    ),
  );

  String _statusText(String status, [String type = 'delivery']) {
    switch (status) {
      case 'awaiting_payment':
        return 'Waiting for payment';
      case 'pending':
        return 'Waiting for shop confirmation';
      case 'confirmed':
        return 'Order confirmed';
      case 'preparing':
        return 'Preparing your order';
      case 'ready':
        return type == 'pickup'
            ? 'Ready for pickup'
            : 'Ready, waiting for a rider';
      case 'rider_assigned':
        return 'Rider assigned';
      case 'picked_up':
        return 'Picked up by rider';
      case 'on_the_way':
      case 'out_for_delivery':
        return 'Out for delivery';
      case 'delivered':
        return 'Delivered';
      case 'completed':
        return 'Completed';
      case 'rejected':
        return 'Rejected by shop';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }

  Widget _trackingStep(
    String label,
    int step,
    int currentStep, {
    required bool isCurrent,
  }) {
    final done = step <= currentStep;
    final stageColors = [
      Theme.of(context).colorScheme.primary,
      Theme.of(context).colorScheme.primary,
      Theme.of(context).colorScheme.primary,
      Colors.green,
    ];
    final activeColor =
        stageColors[step.clamp(0, stageColors.length - 1).toInt()];
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done
                ? activeColor
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            border: isCurrent
                ? Border.all(
                    color: activeColor.withValues(alpha: .35),
                    width: 4,
                  )
                : null,
          ),
          child: Icon(
            step < currentStep || (step == 0 && done)
                ? Icons.check_rounded
                : step == 1
                ? Icons.coffee_rounded
                : step == 2
                ? Icons.inventory_2_rounded
                : Icons.home_rounded,
            size: 14,
            color: done
                ? (step == 3
                      ? Colors.white
                      : Theme.of(context).colorScheme.onPrimary)
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10,
            color: done
                ? activeColor
                : Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: isCurrent
                ? FontWeight.w800
                : done
                ? FontWeight.w600
                : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _progressLine(double progress) => Container(
    width: 18,
    height: 3,
    margin: const EdgeInsets.only(bottom: 18),
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(99),
    ),
    alignment: Alignment.centerLeft,
    child: FractionallySizedBox(
      widthFactor: progress.clamp(0, 1),
      child: ColoredBox(color: Theme.of(context).colorScheme.primary),
    ),
  );

  Widget _mapPin(IconData icon, Color color) => Container(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: BoxShape.circle,
      border: Border.all(color: color, width: 2),
      boxShadow: [
        BoxShadow(color: Theme.of(context).colorScheme.shadow, blurRadius: 5),
      ],
    ),
    child: Icon(icon, color: color, size: 25),
  );

  Widget _mapPlaceholder(String address) => Container(
    color: Theme.of(context).dividerColor,
    alignment: Alignment.center,
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.location_searching_rounded,
          size: 44,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 10),
        const Text(
          'No map location available for this address.',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        if (address.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            address,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    ),
  );
}

Widget _riderDistanceBadge(
  BuildContext context,
  LatLng rider,
  LatLng customer,
) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
  decoration: BoxDecoration(
    color: Theme.of(context).colorScheme.surface.withValues(alpha: .96),
    borderRadius: BorderRadius.circular(18),
    boxShadow: const [
      BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 2)),
    ],
  ),
  child: Text(
    'Rider is ${Distance().as(LengthUnit.Kilometer, rider, customer).toStringAsFixed(1)} km away',
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: Theme.of(context).colorScheme.onSurface,
    ),
  ),
);

Widget _routeMapBadge(
  BuildContext context, {
  required bool live,
  required DateTime? updatedAt,
  required int? eta,
  required String? distance,
  required String? error,
}) => Container(
  constraints: const BoxConstraints(maxWidth: 210),
  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
  decoration: BoxDecoration(
    color: Theme.of(context).colorScheme.surface.withValues(alpha: .96),
    borderRadius: BorderRadius.circular(16),
    boxShadow: [
      BoxShadow(
        color: Theme.of(context).colorScheme.shadow.withValues(alpha: .2),
        blurRadius: 8,
        offset: const Offset(0, 2),
      ),
    ],
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.circle,
            size: 9,
            color: live ? Colors.green.shade700 : Colors.orange.shade700,
          ),
          const SizedBox(width: 5),
          Text(
            live ? 'LIVE' : 'LAST SEEN',
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
          ),
          if (eta != null) ...[
            const SizedBox(width: 9),
            Text(
              '$eta min${distance == null ? '' : ' · $distance km'}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
      const SizedBox(height: 3),
      Text(
        updatedAt == null
            ? 'Waiting for rider location'
            : 'Updated ${_timeTextInManila(updatedAt.toUtc().toIso8601String())}',
        style: TextStyle(
          fontSize: 10,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      if (error != null && error.isNotEmpty) ...[
        const SizedBox(height: 5),
        Text(
          error,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.error,
          ),
        ),
      ],
    ],
  ),
);

Widget _deliveryMapMarker(BuildContext context) => Container(
  padding: const EdgeInsets.all(3),
  decoration: BoxDecoration(
    color: Theme.of(context).colorScheme.surface.withValues(alpha: .94),
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
    boxShadow: [
      BoxShadow(
        color: Theme.of(context).colorScheme.shadow.withValues(alpha: .24),
        blurRadius: 7,
        offset: const Offset(0, 2),
      ),
    ],
  ),
  child: Image.asset(
    'assets/images/delivery.png',
    fit: BoxFit.contain,
    errorBuilder: (context, error, stackTrace) => Icon(
      Icons.delivery_dining_rounded,
      color: Theme.of(context).colorScheme.primary,
    ),
  ),
);
