import 'dart:async';
import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/shop_map_marker.dart';
import '../core/util.dart';
import '../core/widgets.dart' show fixUrl;
import '../screens/rider_chat_screen.dart';
import 'rider_location_service.dart';
import 'rider_map_utils.dart';
import 'rider_proof_screen.dart';
import 'rider_theme.dart';

double? _number(dynamic value) =>
    value == null ? null : double.tryParse(value.toString());

class RiderDeliveryScreen extends StatefulWidget {
  final int id;
  const RiderDeliveryScreen({super.key, required this.id});

  @override
  State<RiderDeliveryScreen> createState() => _RiderDeliveryScreenState();
}

class _RiderDeliveryScreenState extends State<RiderDeliveryScreen> {
  Map<String, dynamic>? _delivery;
  bool _loading = true;
  bool _busy = false;
  bool _refreshing = false;
  String? _error;
  Timer? _routeTimer;
  bool _centeredOnRider = false;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final result = await Api.I.delivery(widget.id);
      if (!mounted) return;
      setState(() {
        _delivery = result;
        _loading = false;
        if (!silent) _error = null;
      });
      if (result['status'] == 'on_the_way') {
        await LocationService.I.start(deliveryId: widget.id);
        _routeTimer ??= Timer.periodic(
          const Duration(seconds: 8),
          (_) => _load(silent: true),
        );
      } else {
        await LocationService.I.removeDelivery(widget.id);
        _routeTimer?.cancel();
        _routeTimer = null;
      }
    } on ApiException catch (e) {
      if (mounted && !silent) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted && !silent) {
        setState(() {
          _error = 'Could not load this delivery. Pull down to retry.';
          _loading = false;
        });
      }
    } finally {
      _refreshing = false;
    }
  }

  @override
  void dispose() {
    _routeTimer?.cancel();
    super.dispose();
  }

  Future<void> _action(String action) async {
    if (_busy) return;
    if (action == 'start' && !await LocationService.I.ensureReady()) {
      if (mounted) {
        setState(
          () => _error =
              LocationService.I.error.value ??
              'Enable location access before starting the delivery.',
        );
      }
      return;
    }
    if (action == 'decline') {
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Decline this delivery?'),
          content: const Text(
            'The shop will be notified and can assign this order to another rider.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep delivery'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Decline'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      if (!mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.I.action(widget.id, action);
      if (action == 'start') {
        await LocationService.I.start(deliveryId: widget.id);
      }
      if (action == 'decline') {
        await LocationService.I.removeDelivery(widget.id);
      }
      if (!mounted) return;
      if (action == 'decline') {
        Navigator.of(context).pop();
      } else {
        await _load();
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'The delivery update failed. Check your connection and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _complete(Map<String, dynamic> order) async {
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RiderProofScreen(deliveryId: widget.id, order: order),
      ),
    );
    if (done == true && mounted) {
      await LocationService.I.removeDelivery(widget.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    }
  }

  Future<void> _openUrl(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the requested app.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _delivery?['order'];
    final orderNumber = order is Map ? order['order_number']?.toString() : null;
    return RiderVisualTheme(
      child: Scaffold(
        appBar: RiderAppBar(title: orderNumber ?? 'Delivery details'),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _delivery == null
            ? RiderImageBackground(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error ?? 'Delivery not found.'),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : RefreshIndicator(onRefresh: _load, child: _content(_delivery!)),
      ),
    );
  }

  Widget _content(Map<String, dynamic> delivery) {
    final order = delivery['order'] is Map
        ? Map<String, dynamic>.from(delivery['order'] as Map)
        : <String, dynamic>{};
    final customer = delivery['customer'] is Map
        ? Map<String, dynamic>.from(delivery['customer'] as Map)
        : <String, dynamic>{};
    final shop = delivery['shop'] is Map
        ? Map<String, dynamic>.from(delivery['shop'] as Map)
        : <String, dynamic>{};
    final rawItems = order['items'];
    final items = rawItems is List
        ? rawItems
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
        : <Map<String, dynamic>>[];
    final status = delivery['status']?.toString() ?? 'assigned';
    final lat = _number(order['lat']);
    final lng = _number(order['lng']);
    final destination = lat == null || lng == null ? null : LatLng(lat, lng);
    final shopLat = _number(shop['lat']);
    final shopLng = _number(shop['lng']);
    final shopPoint =
        shopLat == null || shopLng == null || (shopLat == 0 && shopLng == 0)
        ? null
        : LatLng(shopLat, shopLng);
    final cod =
        order['payment_method'] == 'cod' && order['payment_status'] != 'paid';
    final details = <Widget>[
      if (_error != null) _errorCard(_error!),
      _progress(status),
      if (status == 'on_the_way') _gpsStatus(),
      _customerCard(customer, order),
      _orderCard(items, order, cod),
      OutlinedButton.icon(
        onPressed: () => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => RiderChatScreen(targetId: widget.id, isRider: true),
          ),
        ),
        icon: const Icon(Icons.chat_bubble_outline_rounded),
        label: const Text('Chat with customer'),
      ),
      if (_busy)
        const Center(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: CircularProgressIndicator(),
          ),
        )
      else
        ..._actionButtons(status, order),
    ];

    if (!['accepted', 'picked_up', 'on_the_way'].contains(status)) {
      return RiderImageBackground(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: details,
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        if (destination != null)
          _mapCard(destination, shopPoint, delivery)
        else
          Center(
            child: _infoCard(
              'Map unavailable',
              'This order does not have a usable delivery location.',
              Icons.map_outlined,
            ),
          ),
        DraggableScrollableSheet(
          initialChildSize: .31,
          minChildSize: .22,
          maxChildSize: .88,
          snap: true,
          snapSizes: const [.31, .58, .88],
          builder: (context, scrollController) => Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              image: const DecorationImage(
                image: AssetImage('assets/images/all.png'),
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                colorFilter: ColorFilter.mode(
                  Color(0xCCFFF3E0),
                  BlendMode.srcOver,
                ),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 18,
                  offset: Offset(0, -4),
                ),
              ],
            ),
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                ...details,
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _customerCard(
    Map<String, dynamic> customer,
    Map<String, dynamic> order,
  ) {
    final phone = (customer['phone'] ?? '').toString().trim();
    final avatarUrl = fixUrl(customer['avatar_url']?.toString());
    final address = (order['address'] ?? '').toString().trim();
    final latitude = _number(order['lat']);
    final longitude = _number(order['lng']);
    final hasCoordinates =
        latitude != null &&
        longitude != null &&
        latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180 &&
        !(latitude == 0 && longitude == 0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Customer information',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _customerAvatar(avatarUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    customer['name']?.toString().trim().isNotEmpty == true
                        ? customer['name'].toString()
                        : 'Customer name unavailable',
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _callCustomer(phone),
                    icon: const Icon(Icons.call_rounded),
                    label: const Text('Call Customer'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _navigateToCustomer(
                      order,
                      hasCoordinates: hasCoordinates,
                      address: address,
                    ),
                    icon: const Icon(Icons.navigation_rounded),
                    label: const Text('Navigate'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _infoRow(
              Icons.location_on_outlined,
              'Delivery address',
              address.isNotEmpty ? address : 'Address unavailable',
            ),
            if (hasCoordinates) ...[
              const SizedBox(height: 8),
              _infoRow(
                Icons.gps_fixed_rounded,
                'Saved GPS coordinates',
                '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
              ),
            ],
            if ((order['notes'] ?? '').toString().trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              _infoRow(
                Icons.sticky_note_2_outlined,
                'Delivery instructions',
                order['notes'].toString(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _customerAvatar(String url) => ClipOval(
    child: SizedBox(
      width: 58,
      height: 58,
      child: url.isEmpty
          ? _avatarFallback()
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _avatarFallback(),
            ),
    ),
  );

  Widget _avatarFallback() => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Icon(
      Icons.person_rounded,
      color: Theme.of(context).colorScheme.primary,
      size: 32,
    ),
  );

  Widget _infoRow(IconData icon, String label, String value) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 9),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            SelectableText(value),
          ],
        ),
      ),
    ],
  );

  Future<void> _callCustomer(String phone) async {
    if (phone.isEmpty) {
      _showMessage('The customer phone number is unavailable.');
      return;
    }
    await _openUrl(Uri(scheme: 'tel', path: phone).toString());
  }

  Future<void> _navigateToCustomer(
    Map<String, dynamic> order, {
    required bool hasCoordinates,
    required String address,
  }) async {
    final destination = hasCoordinates
        ? '${order['lat']},${order['lng']}'
        : address;
    if (destination.isEmpty) {
      _showMessage('No valid customer destination is available.');
      return;
    }
    final uri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': destination,
      'travelmode': 'driving',
    });
    await _openUrl(uri.toString());
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _orderCard(
    List<Map<String, dynamic>> items,
    Map<String, dynamic> order,
    bool cod,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Order details',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          if ((order['order_number'] ?? '').toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                order['order_number'].toString(),
                style: TextStyle(color: riderSecondaryText(context)),
              ),
            ),
          if ((order['created_at'] ?? '').toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Order date: ${dateTimeText(order['created_at'])}',
                style: TextStyle(color: riderSecondaryText(context)),
              ),
            ),
          const SizedBox(height: 8),
          if (items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Products • ${items.fold<int>(0, (sum, item) => sum + (int.tryParse(item['qty']?.toString() ?? '') ?? 0))} items',
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          if (items.isEmpty) const Text('No item details were provided.'),
          for (final item in items) _itemRow(item),
          const Divider(height: 24),
          _amountRow('Subtotal', order['subtotal']),
          const SizedBox(height: 7),
          _amountRow('Delivery fee', order['delivery_fee']),
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(child: Text(cod ? 'Cash to collect' : 'Payment method')),
              Text(
                cod
                    ? 'Cash on Delivery'
                    : (order['payment_method']?.toString() ?? 'Paid')
                          .toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Order total',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                peso(dbl(order['total'])),
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: riderAccent(context),
                ),
              ),
            ],
          ),
          if (!cod)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Payment status: ${(order['payment_status'] ?? 'unknown').toString().toUpperCase()}',
                style: TextStyle(
                  color: riderSecondaryText(context),
                  fontSize: 12,
                ),
              ),
            ),
          if (cod)
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Text(
                'Payment status: ${(order['payment_status'] ?? 'unknown').toString().toUpperCase()}',
                style: TextStyle(
                  color: riderSecondaryText(context),
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _amountRow(String label, dynamic amount) => Row(
    children: [
      Expanded(child: Text(label)),
      Text(peso(dbl(amount))),
    ],
  );

  Widget _progress(String status) {
    final stages = [
      'assigned',
      'accepted',
      'picked_up',
      'on_the_way',
      'delivered',
    ];
    final current = stages.indexOf(status).clamp(0, stages.length - 1);
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
                    deliveryStatusLabel(status),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                ),
                _StatusChip(status: status),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: List.generate(
                stages.length,
                (i) => Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: i <= current
                                ? riderGreen
                                : Theme.of(context).colorScheme.outlineVariant,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      if (i < stages.length - 1) const SizedBox(width: 4),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Assigned', style: TextStyle(fontSize: 10)),
                Text('Accepted', style: TextStyle(fontSize: 10)),
                Text('Picked up', style: TextStyle(fontSize: 10)),
                Text('En route', style: TextStyle(fontSize: 10)),
                Text('Delivered', style: TextStyle(fontSize: 10)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _mapCard(
    LatLng destination,
    LatLng? shop,
    Map<String, dynamic> delivery,
  ) => ValueListenableBuilder<Position?>(
    valueListenable: LocationService.I.position,
    builder: (context, position, _) {
      final route = routePointsFrom(delivery['route']);
      final gpsPoint = position == null
          ? latLngFrom(delivery['rider_location'])
          : LatLng(position.latitude, position.longitude);
      final onRoad = nearestRoadPoint(gpsPoint, route);
      final riderPoint = onRoad ?? gpsPoint;
      if (riderPoint != null && !_centeredOnRider) {
        _centeredOnRider = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _mapController.move(riderPoint, 15);
        });
      }
      final duration = _number(
        (delivery['route'] as Map?)?['duration_seconds'],
      );
      final distance = _number((delivery['route'] as Map?)?['distance_meters']);
      final routeStatus = (delivery['route'] as Map?)?['status']?.toString();
      final live = delivery['status'] == 'on_the_way' && gpsPoint != null;
      final customer = delivery['customer'] is Map
          ? Map<String, dynamic>.from(delivery['customer'] as Map)
          : <String, dynamic>{};
      final riderImage = Api.I.user?['avatar_url']?.toString();
      final customerImage = customer['avatar_url']?.toString();
      return Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: riderPoint ?? destination,
                initialZoom: 14,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.kjmcoffeebrew.app',
                ),
                if (route.length > 1 && routeStatus != 'finished')
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: route,
                        color: const Color(0xFF168A83),
                        strokeWidth: 5,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    if (shop != null) kjmShopMarker(point: shop),
                    Marker(
                      point: destination,
                      width: 58,
                      height: 62,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFFD34A4A),
                                width: 2,
                              ),
                              boxShadow: const [
                                BoxShadow(color: Colors.black26, blurRadius: 5),
                              ],
                            ),
                            child: CircleAvatar(
                              radius: 17,
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              backgroundImage:
                                  customerImage == null || customerImage.isEmpty
                                  ? null
                                  : NetworkImage(customerImage),
                              child:
                                  customerImage == null || customerImage.isEmpty
                                  ? const Icon(
                                      Icons.person_rounded,
                                      color: Color(0xFFD34A4A),
                                      size: 21,
                                    )
                                  : null,
                            ),
                          ),
                          const Icon(
                            Icons.arrow_drop_down_rounded,
                            color: Color(0xFFD34A4A),
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                    if (riderPoint != null)
                      Marker(
                        point: riderPoint,
                        width: 54,
                        height: 54,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF176B67),
                              width: 2.5,
                            ),
                            boxShadow: const [
                              BoxShadow(color: Colors.black26, blurRadius: 6),
                            ],
                          ),
                          child: CircleAvatar(
                            backgroundColor: const Color(0xFF176B67),
                            backgroundImage:
                                riderImage == null || riderImage.isEmpty
                                ? null
                                : NetworkImage(riderImage),
                            child: riderImage == null || riderImage.isEmpty
                                ? const Icon(
                                    Icons.delivery_dining_rounded,
                                    color: Colors.white,
                                    size: 27,
                                  )
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            left: 12,
            top: 12,
            child: _MapInfoChip(
              icon: live ? Icons.circle : Icons.route_rounded,
              label: live
                  ? 'LIVE'
                  : route.length > 1
                  ? 'ROAD ROUTE'
                  : 'WAITING FOR ROUTE',
              color: live ? const Color(0xFF176B67) : const Color(0xFF455A64),
            ),
          ),
          if (duration != null || distance != null)
            Positioned(
              left: 12,
              right: 58,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface
                      .withValues(alpha: .96),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '${duration == null ? '' : 'Road ETA ${max(1, (duration / 60).ceil())} min'}${duration != null && distance != null ? '  •  ' : ''}${distance == null ? '' : '${(distance / 1000).toStringAsFixed(1)} km to customer'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          if (riderPoint != null)
            Positioned(
              right: 10,
              bottom: 10,
              child: Material(
                elevation: 2,
                color: Theme.of(context).colorScheme.surface,
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: 'Center on rider',
                  onPressed: () => _mapController.move(riderPoint, 15),
                  icon: const Icon(
                    Icons.my_location_rounded,
                    color: Color(0xFF176B67),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );

  Widget _gpsStatus() => ValueListenableBuilder<bool>(
    valueListenable: LocationService.I.tracking,
    builder: (context, tracking, _) => ValueListenableBuilder<String?>(
      valueListenable: LocationService.I.error,
      builder: (context, error, _) => ValueListenableBuilder<String?>(
        valueListenable: LocationService.I.settingsAction,
        builder: (context, settingsAction, _) => Card(
          color: error != null
              ? Theme.of(context).colorScheme.errorContainer
              : null,
          child: ListTile(
            leading: Icon(
              error != null
                  ? Icons.location_disabled_outlined
                  : Icons.my_location_rounded,
              color: error != null
                  ? Theme.of(context).colorScheme.error
                  : riderAccent(context),
            ),
            title: Text(
              error != null
                  ? 'GPS needs attention'
                  : tracking
                  ? 'Sharing live location'
                  : 'Waiting for a fresh GPS fix',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              error ?? 'Your current phone location is shared for active deliveries.',
            ),
            trailing: settingsAction == null
                ? null
                : TextButton(
                    onPressed: settingsAction == 'app'
                        ? Geolocator.openAppSettings
                        : Geolocator.openLocationSettings,
                    child: const Text('Open Settings'),
                  ),
          ),
        ),
      ),
    ),
  );

  Widget _itemRow(Map<String, dynamic> item) {
    final options = item['options'] is List
        ? (item['options'] as List).join(', ')
        : '';
    final imageUrl = fixUrl(item['image_url']?.toString());
    final notes = (item['notes'] ?? '').toString().trim();
    final quantity = int.tryParse(item['qty']?.toString() ?? '') ?? 1;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 58,
              height: 58,
              child: imageUrl.isEmpty
                  ? _productImageFallback()
                  : Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _productImageFallback(),
                    ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['name']?.toString() ?? 'Item',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text('Quantity: $quantity'),
                if (options.isNotEmpty)
                  Text(
                    options,
                    style: TextStyle(
                      color: riderSecondaryText(context),
                      fontSize: 12,
                    ),
                  ),
                if (notes.isNotEmpty)
                  Text(
                    'Note: $notes',
                    style: TextStyle(
                      color: riderSecondaryText(context),
                      fontSize: 12,
                    ),
                  ),
                if (item['unit_price'] != null)
                  Text('Unit price: ${peso(dbl(item['unit_price']))}'),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            peso(dbl(item['total_price'])),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _productImageFallback() => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Icon(
      Icons.local_cafe_outlined,
      color: Theme.of(context).colorScheme.primary,
    ),
  );

  List<Widget> _actionButtons(String status, Map<String, dynamic> order) => [
    if (status == 'assigned') ...[
      FilledButton.icon(
        onPressed: () => _action('accept'),
        icon: const Icon(Icons.check_rounded),
        label: const Text('Accept Delivery'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () => _action('decline'),
        icon: const Icon(Icons.close_rounded),
        label: const Text('Decline'),
      ),
    ],
    if (status == 'accepted')
      FilledButton.icon(
        onPressed: () => _action('pickup'),
        icon: const Icon(Icons.store_mall_directory_outlined),
        label: const Text('Confirm Pickup'),
      ),
    if (status == 'picked_up')
      FilledButton.icon(
        onPressed: () => _action('start'),
        icon: const Icon(Icons.navigation_rounded),
        label: const Text('Start Delivery and GPS'),
      ),
    if (status == 'on_the_way')
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF228A60)),
        onPressed: () => _complete(order),
        icon: const Icon(Icons.check_circle_outline),
        label: const Text('Mark as Delivered'),
      ),
    if (status == 'delivered' || status == 'declined')
      _infoCard(
        'Delivery closed',
        status == 'delivered'
            ? 'This delivery has been completed.'
            : 'This delivery was declined.',
        Icons.task_alt_rounded,
      ),
  ];

  Widget _infoCard(String title, String body, IconData icon) => Card(
    child: ListTile(
      leading: Icon(icon, color: riderAccent(context)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(body),
    ),
  );

  Widget _errorCard(String text) => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        text,
        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
      ),
    ),
  );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: deliveryStatusColor(status).withValues(alpha: .13),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      deliveryStatusLabel(status),
      style: TextStyle(
        color: deliveryStatusColor(status),
        fontWeight: FontWeight.w700,
        fontSize: 11,
      ),
    ),
  );
}

class _MapInfoChip extends StatelessWidget {
  const _MapInfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: .96),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 10,
            letterSpacing: .6,
          ),
        ),
      ],
    ),
  );
}
