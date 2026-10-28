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
import 'customer_service_sheet.dart';
import 'payment_screen.dart';

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
  int _rating = 5;
  final _comment = TextEditingController();
  bool _busy = false;
  bool _showDetails = true;

  @override
  void initState() {
    super.initState();
    _load();
    _startTrackingPolling();
    Realtime.I.connect();
    _liveSubscription = Realtime.I.updates.listen((event) {
      if (event['kind'] == 'order' ||
          event['kind'] == 'delivery' ||
          event['kind'] == 'payment' ||
          event['kind'] == 'rider') {
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
      final o = await Api.I.order(widget.id);
      final t = await Api.I.tracking(widget.id);
      if (!mounted) return;
      setState(() {
        _o = o;
        _t = t;
        _loading = false;
        _error = null;
      });
      if (_isFinalStatus('${o['status']}')) _trackingTimer?.cancel();
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

  bool _isFinalStatus(String status) =>
      const {'delivered', 'completed', 'cancelled', 'rejected'}.contains(status);

  void _startTrackingPolling() {
    _trackingTimer?.cancel();
    _trackingTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      final status = _o?['status']?.toString();
      if (mounted && (status == null || !_isFinalStatus(status))) {
        _load(silent: true);
      }
    });
  }

  Future<void> _cancel() async {
    if (_busy || _o?['can_cancel'] != true) return;
    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String? reason;
    try {
      reason = await showDialog<String>(
        context: context,
        builder: (ctx) => Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
                        child: Icon(Icons.free_cancellation_rounded, color: Theme.of(context).colorScheme.error, size: 29),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Cancel this order?', textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text('Are you sure you want to cancel this order?', textAlign: TextAlign.center,
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: reasonController,
                      minLines: 3,
                      maxLines: 5,
                      maxLength: 255,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        labelText: 'Cancellation reason',
                        hintText: 'Tell us why you need to cancel',
                        alignLabelWithHint: true,
                        prefixIcon: Padding(
                          padding: EdgeInsets.only(bottom: 42),
                          child: Icon(Icons.chat_bubble_outline_rounded),
                        ),
                      ),
                      validator: (value) => value == null || value.trim().isEmpty
                          ? 'Please enter a reason for cancellation.' : null,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () {
                        if (formKey.currentState?.validate() ?? false) {
                          Navigator.pop(ctx, reasonController.text.trim());
                        }
                      },
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Yes, Cancel Order'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                        foregroundColor: Theme.of(context).colorScheme.onError,
                        minimumSize: const Size.fromHeight(50),
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      child: const Text('Keep My Order'),
                    ),
                  ],
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Your order has been cancelled successfully.')),
        );
      }
    } on ApiException catch (e) {
      final noLongerCancellable = e.message.toLowerCase().contains('can no longer be cancelled');
      if (noLongerCancellable) await _load();
      if (!mounted) return;
      final message = noLongerCancellable
          ? 'This order can no longer be cancelled because it has already progressed.'
          : e.message;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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

  Future<void> _openRiderMap(
    Map<String, dynamic> order,
    Map<String, dynamic> tracking,
    String address,
  ) async {
    _trackingTimer?.cancel();
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog.fullscreen(
        child: _LiveRiderMap(
          orderId: widget.id,
          orderNumber: '${order['order_number'] ?? 'Order'}',
          address: address,
          initialTracking: tracking,
        ),
      ),
    );
    if (mounted && !_isFinalStatus(_o?['status']?.toString() ?? '')) {
      _startTrackingPolling();
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = _o;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
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
            tooltip: 'Contact support',
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

  Widget _body(Map<String, dynamic> o, Map<String, dynamic> t) {
    final status = '${o['status']}';
    final type = '${o['order_type']}';
    final isDelivery = type == 'delivery';
    final rider = t['rider'] is Map
        ? Map<String, dynamic>.from(t['rider'] as Map)
        : null;
    final dest = t['destination'] is Map
        ? Map<String, dynamic>.from(t['destination'] as Map)
        : <String, dynamic>{};
    final shop = t['shop'] is Map
        ? Map<String, dynamic>.from(t['shop'] as Map)
        : <String, dynamic>{};
    final timeline = t['timeline'] is List
        ? mapList(t['timeline'])
        : <Map<String, dynamic>>[];
    final items = o['items'] is List
        ? mapList(o['items'])
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
    final points = <LatLng>[
      ?destinationPoint,
      ?riderPoint,
      ?shopPoint,
    ];
    final isDelivered = status == 'delivered' || status == 'completed';
    final isOnRoute = status == 'on_the_way' || status == 'picked_up';
    final currentStep = isDelivered
        ? 4
        : isOnRoute
        ? 3
        : (status == 'ready' || status == 'rider_assigned')
        ? 2
        : status == 'preparing'
        ? 1
        : status == 'confirmed'
        ? 0
        : -1;
    final eta = rider?['eta_min'];
    final etaMin = eta is num
        ? eta.toInt()
        : riderPoint != null
        ? math.max(1, (Distance().as(LengthUnit.Kilometer, riderPoint, destinationPoint ?? riderPoint) * 4.5).ceil())
        : null;
    final address = (o['delivery_address'] ?? dest['address'] ?? '').toString();


    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${o['order_number'] ?? 'Order'}',
                style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
            Text(
              isDelivery ? 'Live delivery tracking' : _statusText(status, type),
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (isDelivery) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: SizedBox(
              height: (MediaQuery.sizeOf(context).height * 0.36).clamp(300.0, 420.0).toDouble(),
              child: destinationPoint == null
                  ? _mapPlaceholder(address)
                  : Stack(
                      children: [
                        FlutterMap(
                          options: MapOptions(
                            initialCenter: riderPoint ?? destinationPoint,
                            initialZoom: 15,
                            initialCameraFit: points.length > 1
                                ? CameraFit.bounds(
                                    bounds: LatLngBounds.fromPoints(points),
                                    padding: const EdgeInsets.all(52),
                                    maxZoom: 16,
                                  )
                                : null,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.kjmcoffeebrew.app',
                            ),
                            if (riderPoint != null || shopPoint != null)
                              PolylineLayer(
                                polylines: [
                                  Polyline(
                                    points: [riderPoint ?? shopPoint!, destinationPoint],
                                    color: caramel,
                                    strokeWidth: 5,
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
                                      caramel,
                                    ),
                                  ),
                                Marker(
                                  point: destinationPoint,
                                  width: 42,
                                  height: 48,
                                  child: _mapPin(Icons.home_rounded, espresso),
                                ),
                                if (riderPoint != null)
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
                                TextSourceAttribution(
                                  'OpenStreetMap contributors',
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (riderPoint != null)
                          Positioned(
                            top: 12,
                            left: 12,
                            child: _riderDistanceBadge(
                              riderPoint,
                              destinationPoint,
                            ),
                          ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: destinationPoint == null
                  ? null
                  : () => _openRiderMap(o, t, address),
              icon: const Icon(Icons.map_outlined),
              label: const Text('View Map'),
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Icon(
                Icons.location_on_outlined,
                size: 17,
                color: riderPoint == null
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : Colors.red.shade700,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  riderPoint == null
                      ? 'Location will appear here once the rider starts sharing their location.'
                      : 'Rider location updates every few seconds.',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 25,
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  foregroundImage:
                      rider?['avatar_url'] != null &&
                          '${rider?['avatar_url']}'.isNotEmpty
                      ? NetworkImage(fixUrl('${rider?['avatar_url']}'))
                      : null,
                  child:
                      rider?['avatar_url'] == null ||
                          '${rider?['avatar_url']}'.isEmpty
                      ? Icon(
                          Icons.delivery_dining_rounded,
                          color: Theme.of(context).colorScheme.primary,
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
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          rider == null
                              ? 'Rider will be assigned once the order is ready.'
                              : 'Delivery rider',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (rider?['plate_number'] != null)
                          Text(
                            '${rider!['plate_number']}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (rider?['phone'] != null) ...[
                    _contactButton(
                      Icons.call_rounded,
                      () => launchUrl(Uri.parse('tel:${rider!['phone']}')),
                    ),
                    const SizedBox(width: 8),
                    _contactButton(
                      Icons.chat_bubble_outline_rounded,
                      () => launchUrl(Uri.parse('sms:${rider!['phone']}')),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
        Card(
          elevation: 1,
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isDelivery
                            ? Icons.delivery_dining_rounded
                            : Icons.storefront_rounded,
                        color: Theme.of(context).colorScheme.primary,
                        size: 29,
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isDelivered
                                ? 'Your order has been delivered!'
                                : isOnRoute
                                ? 'Your order is on the way!'
                                : 'Your order is being prepared',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _statusText(status, type),
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    if (etaMin != null && !isDelivered && isOnRoute)
                      Text(
                        'Approx. $etaMin min',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _trackingStep('Confirmed', 0, currentStep),
                      _progressLine(currentStep >= 1),
                      _trackingStep('Preparing', 1, currentStep),
                      _progressLine(currentStep >= 2),
                      _trackingStep('Ready', 2, currentStep),
                      _progressLine(currentStep >= 3),
                      _trackingStep('Out for Delivery', 3, currentStep),
                      _progressLine(currentStep >= 4),
                      _trackingStep('Delivered', 4, currentStep),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Delivery Updates', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                if (timeline.isEmpty)
                  Text('Order updates will appear here as the shop changes its status.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
                else
                  for (final entry in timeline)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_rounded, size: 18, color: statusColor('${entry['status']}')),
                          const SizedBox(width: 10),
                          Expanded(child: Text(_statusText('${entry['status']}', type), style: const TextStyle(fontWeight: FontWeight.w600))),
                          Text(timeText(entry['at']), style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
            onPressed: () => setState(() => _showDetails = !_showDetails),
            style: OutlinedButton.styleFrom(
              foregroundColor: espresso,
              side: BorderSide(color: Theme.of(context).colorScheme.primary),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            icon: Icon(
              _showDetails
                  ? Icons.expand_less_rounded
                  : Icons.receipt_long_outlined,
              size: 18,
            ),
            label: Text(
              _showDetails ? 'Hide Order Details' : 'View Order Details',
            ),
          ),
        ),
        if (_showDetails)
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 16),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              leading: Icon(Icons.receipt_long_rounded, color: Theme.of(context).colorScheme.primary),
              title: const Text(
                'Order details',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${items.length} item${items.length == 1 ? '' : 's'}  |  ${peso(dbl(o['total']))}',
              ),
              initiallyExpanded: true,
              children: [
                if (isDelivery && address.isNotEmpty) ...[
                  _infoRow(
                    Icons.location_on_outlined,
                    'Delivery address',
                    address,
                  ),
                  const Divider(height: 20),
                ],
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${item['qty']} × ${item['name']}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (item['options'] is List &&
                                  (item['options'] as List).isNotEmpty)
                                Text(
                                  (item['options'] as List).join(', '),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Text(peso(dbl(item['line_total']))),
                      ],
                    ),
                  ),
                const Divider(height: 20),
                _row('Subtotal', peso(dbl(o['subtotal']))),
                if (dbl(o['discount']) > 0)
                  _row('Discount', '-${peso(dbl(o['discount']))}'),
                if (isDelivery)
                  _row('Delivery fee', peso(dbl(o['delivery_fee']))),
                _row('Total', peso(dbl(o['total'])), bold: true),
                const SizedBox(height: 8),
                _infoRow(
                  Icons.payments_outlined,
                  'Payment',
                  '${payLabel(o['payment_method'])}  |  ${'${o['payment_status']}'.toUpperCase()}',
                ),
                if (o['reject_reason'] != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Reason: ${o['reject_reason']}',
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 12),
        if (o['can_pay'] == true)
          FilledButton(
            onPressed: _busy ? null : _pay,
            child: Text('Pay via GCash  |  ${peso(dbl(o['total']))}'),
          ),
        if (o['can_cancel'] == true)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              foregroundColor: Colors.red,
            ),
            onPressed: _busy ? null : _cancel,
            icon: _busy
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
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
                            i <= _rating ? Icons.star : Icons.star_border,
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
    );
  }

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

  Widget _trackingStep(String label, int step, int current) {
    final done = step <= current;
    final stageColors = [espresso, caramel, caramel, Colors.deepOrange, Colors.green];
    final activeColor = stageColors[step.clamp(0, stageColors.length - 1).toInt()];
    return SizedBox(
      width: 72,
      child: Column(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: done ? activeColor : Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Icon(
              step < current
                  ? Icons.check
                  : step == 0
                  ? Icons.check_rounded
                  : step == 1
                  ? Icons.coffee_rounded
                  : step == 2
                  ? Icons.inventory_2_rounded
                  : step == 3
                  ? Icons.delivery_dining_rounded
                  : Icons.home_rounded,
              size: 14,
              color: done ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 9,
              color: done ? activeColor : Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: done ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _progressLine(bool active) => Container(
    width: 18,
    height: 2,
    color: active ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surfaceContainerHighest,
    margin: const EdgeInsets.only(bottom: 18),
  );

  Widget _mapPin(IconData icon, Color color) => Container(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: BoxShape.circle,
      border: Border.all(color: color, width: 2),
      boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.shadow, blurRadius: 5)],
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
        Icon(Icons.location_searching_rounded, size: 44, color: Theme.of(context).colorScheme.primary),
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
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    ),
  );

  Widget _contactButton(IconData icon, VoidCallback onPressed) =>
      IconButton.filledTonal(
        onPressed: onPressed,
        icon: Icon(icon, size: 19),
        style: IconButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          foregroundColor: espresso,
        ),
      );

  Widget _infoRow(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 2),
              Text(value),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _row(String l, String v, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(l, style: TextStyle(fontWeight: bold ? FontWeight.w700 : null)),
        Text(
          v,
          style: TextStyle(
            fontWeight: bold ? FontWeight.w700 : null,
            color: bold ? caramel : null,
          ),
        ),
      ],
    ),
  );
}

class _LiveRiderMap extends StatefulWidget {
  final int orderId;
  final String orderNumber;
  final String address;
  final Map<String, dynamic> initialTracking;

  const _LiveRiderMap({
    required this.orderId,
    required this.orderNumber,
    required this.address,
    required this.initialTracking,
  });

  @override
  State<_LiveRiderMap> createState() => _LiveRiderMapState();
}

class _LiveRiderMapState extends State<_LiveRiderMap> {
  late Map<String, dynamic> _tracking;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  bool _refreshing = false;
  Timer? _locationTimer;

  @override
  void initState() {
    super.initState();
    _tracking = widget.initialTracking;
    _locationTimer = Timer.periodic(const Duration(seconds: 8), (_) => _refreshLocation());
    _subscription = Realtime.I.updates.listen((event) {
      if (event['kind'] == 'order' || event['kind'] == 'delivery' || event['kind'] == 'rider') {
        _refreshLocation();
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _locationTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshLocation() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final latest = await Api.I.tracking(widget.orderId);
      if (mounted) setState(() => _tracking = latest);
    } on ApiException {
      // Preserve the last known location if a live refresh briefly fails.
    } finally {
      _refreshing = false;
    }
  }

  LatLng? _point(dynamic value) {
    if (value is! Map || value['lat'] == null || value['lng'] == null) {
      return null;
    }
    return LatLng(dbl(value['lat']), dbl(value['lng']));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final rider = _tracking['rider'] is Map
        ? Map<String, dynamic>.from(_tracking['rider'] as Map)
        : null;
    final riderPoint = _point(rider);
    final destinationPoint = _point(_tracking['destination']);
    final shopPoint = _point(_tracking['shop']);
    final mapPoints = <LatLng>[
      ?riderPoint,
      ?destinationPoint,
      if (shopPoint != null && shopPoint.latitude != 0 && shopPoint.longitude != 0)
        shopPoint,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('Rider location · ${widget.orderNumber}',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Refresh location',
            onPressed: _refreshing ? null : _refreshLocation,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: destinationPoint == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.location_off_outlined,
                        size: 48, color: colors.primary),
                    const SizedBox(height: 10),
                    const Text('Map location is not available yet.',
                        textAlign: TextAlign.center),
                    if (widget.address.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(widget.address,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
            )
          : FlutterMap(
              options: MapOptions(
                initialCenter: riderPoint ?? destinationPoint,
                initialZoom: 14,
                initialCameraFit: mapPoints.length > 1
                    ? CameraFit.bounds(
                        bounds: LatLngBounds.fromPoints(mapPoints),
                        padding: const EdgeInsets.all(48),
                        maxZoom: 15,
                      )
                    : null,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.kjmcoffeebrew.app',
                ),
                if (riderPoint != null)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: [riderPoint, destinationPoint],
                        color: colors.primary,
                        strokeWidth: 5,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    if (shopPoint != null &&
                        shopPoint.latitude != 0 &&
                        shopPoint.longitude != 0)
                      Marker(
                        point: shopPoint,
                        width: 48,
                        height: 50,
                        child: const Icon(Icons.storefront_rounded,
                            color: caramel, size: 38),
                      ),
                    Marker(
                      point: destinationPoint,
                      width: 48,
                      height: 50,
                      child: const Icon(Icons.location_on_rounded,
                          color: Colors.red, size: 42),
                    ),
                    if (riderPoint != null)
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
                  ],
                ),
              ],
            ),
    );
  }
}

Widget _riderDistanceBadge(LatLng rider, LatLng customer) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
  decoration: BoxDecoration(
    color: Colors.white.withValues(alpha: .96),
    borderRadius: BorderRadius.circular(18),
    boxShadow: const [
      BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 2)),
    ],
  ),
  child: Text(
    'Rider is ${Distance().as(LengthUnit.Kilometer, rider, customer).toStringAsFixed(1)} km away',
    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
  ),
);

Widget _deliveryMapMarker(BuildContext context) => Container(
  padding: const EdgeInsets.all(3),
  decoration: BoxDecoration(
    color: Theme.of(context).colorScheme.surface.withValues(alpha: .94),
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: caramel, width: 2),
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
    errorBuilder: (context, error, stackTrace) => const Icon(
      Icons.delivery_dining_rounded,
      color: caramel,
    ),
  ),
);
