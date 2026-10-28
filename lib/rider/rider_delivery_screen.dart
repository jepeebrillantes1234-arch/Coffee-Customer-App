import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/util.dart';
import 'rider_location_service.dart';
import 'rider_proof_screen.dart';
import 'rider_theme.dart';

double? _number(dynamic value) => value == null ? null : double.tryParse(value.toString());

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
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await Api.I.delivery(widget.id);
      if (!mounted) return;
      setState(() { _delivery = result; _loading = false; _error = null; });
      if (result['status'] == 'on_the_way') {
        await LocationService.I.start(deliveryId: widget.id);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _error = 'Could not load this delivery. Pull down to retry.'; _loading = false; });
    }
  }

  Future<void> _action(String action) async {
    if (_busy) return;
    if (action == 'start' && !await LocationService.I.ensureReady()) {
      if (mounted) setState(() => _error = LocationService.I.error.value ?? 'Enable location access before starting the delivery.');
      return;
    }
    if (action == 'decline') {
      if (!mounted) return;
      final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: const Text('Decline this delivery?'),
        content: const Text('The shop will be notified and can assign this order to another rider.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep delivery')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Decline'))],
      ));
      if (confirmed != true) return;
      if (!mounted) return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await Api.I.action(widget.id, action);
      if (action == 'start') await LocationService.I.start(deliveryId: widget.id);
      if (action == 'decline') await LocationService.I.stop();
      if (!mounted) return;
      if (action == 'decline') {
        Navigator.of(context).pop();
      } else {
        await _load();
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'The delivery update failed. Check your connection and retry.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _complete(Map<String, dynamic> order) async {
    final done = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => RiderProofScreen(deliveryId: widget.id, order: order),
    ));
    if (done == true && mounted) {
      await LocationService.I.stop();
      if (!mounted) return;
      Navigator.of(context).pop();
    }
  }

  Future<void> _openUrl(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the requested app.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _delivery?['order'];
    final orderNumber = order is Map ? order['order_number']?.toString() : null;
    return Scaffold(
      appBar: AppBar(title: Text(orderNumber ?? 'Delivery details')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _delivery == null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_error ?? 'Delivery not found.'), const SizedBox(height: 12), OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Retry'))])))
              : RefreshIndicator(onRefresh: _load, child: _content(_delivery!)),
    );
  }

  Widget _content(Map<String, dynamic> delivery) {
    final order = delivery['order'] is Map ? Map<String, dynamic>.from(delivery['order'] as Map) : <String, dynamic>{};
    final customer = delivery['customer'] is Map ? Map<String, dynamic>.from(delivery['customer'] as Map) : <String, dynamic>{};
    final shop = delivery['shop'] is Map ? Map<String, dynamic>.from(delivery['shop'] as Map) : <String, dynamic>{};
    final rawItems = order['items'];
    final items = rawItems is List ? rawItems.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList() : <Map<String, dynamic>>[];
    final status = delivery['status']?.toString() ?? 'assigned';
    final lat = _number(order['lat']);
    final lng = _number(order['lng']);
    final destination = lat == null || lng == null ? null : LatLng(lat, lng);
    final shopLat = _number(shop['lat']);
    final shopLng = _number(shop['lng']);
    final shopPoint = shopLat == null || shopLng == null || (shopLat == 0 && shopLng == 0) ? null : LatLng(shopLat, shopLng);
    final cod = order['payment_method'] == 'cod' && order['payment_status'] != 'paid';
    final theme = Theme.of(context);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        if (_error != null) _errorCard(_error!),
        _progress(status),
        if (status == 'on_the_way') _gpsStatus(),
        const SizedBox(height: 12),
        if (destination != null) _mapCard(destination, shopPoint) else _infoCard('Map unavailable', 'This order does not have a usable delivery location.', Icons.map_outlined),
        const SizedBox(height: 12),
        if (destination != null && ['accepted', 'picked_up', 'on_the_way'].contains(status))
          OutlinedButton.icon(onPressed: () => _openUrl('https://www.google.com/maps/dir/?api=1&destination=${destination.latitude},${destination.longitude}&travelmode=driving'), icon: const Icon(Icons.navigation_rounded), label: const Text('Navigate with Google Maps')),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Customer', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Text(customer['name']?.toString() ?? 'Customer', style: const TextStyle(fontWeight: FontWeight.w700)),
          if ((customer['phone'] ?? '').toString().isNotEmpty)
            TextButton.icon(onPressed: () => _openUrl('tel:${customer['phone']}'), icon: const Icon(Icons.call_outlined), label: Text(customer['phone'].toString()), style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft)),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.location_on_outlined, size: 19), const SizedBox(width: 8), Expanded(child: Text(order['address']?.toString() ?? 'Address unavailable'))]),
          if ((order['notes'] ?? '').toString().trim().isNotEmpty) ...[const SizedBox(height: 8), Text('Delivery note: ${order['notes']}')],
        ]))),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Order items', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (items.isEmpty) const Text('No item details were provided.'),
          for (final item in items) _itemRow(item),
          const Divider(height: 24),
          Row(children: [Expanded(child: Text(cod ? 'Cash to collect' : 'Payment method')), Text(cod ? 'Cash on Delivery' : (order['payment_method']?.toString() ?? 'Paid').toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w700))]),
          const SizedBox(height: 8),
          Row(children: [const Expanded(child: Text('Order total', style: TextStyle(fontWeight: FontWeight.w700))), Text(peso(dbl(order['total'])), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: riderAccent(context)))]),
          if (!cod) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Payment status: ${(order['payment_status'] ?? 'unknown').toString().toUpperCase()}', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12))),
        ]))),
        const SizedBox(height: 12),
        if (_busy) const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())) else ..._actionButtons(status, order),
      ],
    );
  }

  Widget _progress(String status) {
    final stages = ['assigned', 'accepted', 'picked_up', 'on_the_way', 'delivered'];
    final current = stages.indexOf(status).clamp(0, stages.length - 1);
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Expanded(child: Text(deliveryStatusLabel(status), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))), _StatusChip(status: status)]),
      const SizedBox(height: 16),
      Row(children: List.generate(stages.length, (i) => Expanded(child: Row(children: [Expanded(child: Container(height: 4, decoration: BoxDecoration(color: i <= current ? riderGreen : Theme.of(context).colorScheme.outlineVariant, borderRadius: BorderRadius.circular(4)))), if (i < stages.length - 1) const SizedBox(width: 4)])))),
      const SizedBox(height: 8),
      const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Assigned', style: TextStyle(fontSize: 10)), Text('Accepted', style: TextStyle(fontSize: 10)), Text('Picked up', style: TextStyle(fontSize: 10)), Text('En route', style: TextStyle(fontSize: 10)), Text('Delivered', style: TextStyle(fontSize: 10))]),
    ])));
  }

  Widget _mapCard(LatLng destination, LatLng? shop) => Card(
    clipBehavior: Clip.antiAlias,
    child: SizedBox(
      height: 250,
      child: ValueListenableBuilder<Position?>(
        valueListenable: LocationService.I.position,
        builder: (context, position, _) => FlutterMap(
          options: MapOptions(initialCenter: destination, initialZoom: 14),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.kjmcoffeebrew.app'),
            if (shop != null) PolylineLayer(polylines: [Polyline(points: [shop, destination], color: riderGreen, strokeWidth: 4)]),
            MarkerLayer(markers: [
              if (shop != null) Marker(point: shop, width: 42, height: 46, child: const Icon(Icons.store_rounded, color: riderGreen, size: 34)),
              Marker(point: destination, width: 42, height: 46, child: const Icon(Icons.location_on_rounded, color: Color(0xFFD34A4A), size: 40)),
              if (position != null) Marker(point: LatLng(position.latitude, position.longitude), width: 42, height: 46, child: const Icon(Icons.delivery_dining_rounded, color: Color(0xFF287CC1), size: 38)),
            ]),
          ],
        ),
      ),
    ),
  );

  Widget _gpsStatus() => ValueListenableBuilder<bool>(
    valueListenable: LocationService.I.tracking,
    builder: (context, tracking, _) => ValueListenableBuilder<String?>(
      valueListenable: LocationService.I.error,
      builder: (context, error, _) => Card(
        color: error != null ? Theme.of(context).colorScheme.errorContainer : null,
        child: ListTile(
          leading: Icon(error != null ? Icons.location_disabled_outlined : Icons.my_location_rounded, color: error != null ? Theme.of(context).colorScheme.error : riderAccent(context)),
          title: Text(error != null ? 'GPS needs attention' : tracking ? 'Sharing live location' : 'Starting GPS…', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(error ?? 'Your location is shared with the shop while this delivery is in progress.'),
        ),
      ),
    ),
  );

  Widget _itemRow(Map<String, dynamic> item) {
    final options = item['options'] is List ? (item['options'] as List).join(', ') : '';
    return Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${item['qty'] ?? 1} × ', style: const TextStyle(fontWeight: FontWeight.w800)),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(item['name']?.toString() ?? 'Item'), if (options.isNotEmpty) Text(options, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12))])),
    ]));
  }

  List<Widget> _actionButtons(String status, Map<String, dynamic> order) => [
    if (status == 'assigned') ...[
      FilledButton.icon(onPressed: () => _action('accept'), icon: const Icon(Icons.check_rounded), label: const Text('Accept Delivery')),
      const SizedBox(height: 8),
      OutlinedButton.icon(onPressed: () => _action('decline'), icon: const Icon(Icons.close_rounded), label: const Text('Decline')),
    ],
    if (status == 'accepted') FilledButton.icon(onPressed: () => _action('pickup'), icon: const Icon(Icons.store_mall_directory_outlined), label: const Text('Confirm Pickup')),
    if (status == 'picked_up') FilledButton.icon(onPressed: () => _action('start'), icon: const Icon(Icons.navigation_rounded), label: const Text('Start Delivery and GPS')),
    if (status == 'on_the_way') FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: const Color(0xFF228A60)), onPressed: () => _complete(order), icon: const Icon(Icons.check_circle_outline), label: const Text('Mark as Delivered')),
    if (status == 'delivered' || status == 'declined') _infoCard('Delivery closed', status == 'delivered' ? 'This delivery has been completed.' : 'This delivery was declined.', Icons.task_alt_rounded),
  ];

  Widget _infoCard(String title, String body, IconData icon) => Card(child: ListTile(leading: Icon(icon, color: riderAccent(context)), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text(body)));

  Widget _errorCard(String text) => Card(color: Theme.of(context).colorScheme.errorContainer, child: Padding(padding: const EdgeInsets.all(12), child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer))));
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: deliveryStatusColor(status).withValues(alpha: .13), borderRadius: BorderRadius.circular(20)),
    child: Text(deliveryStatusLabel(status), style: TextStyle(color: deliveryStatusColor(status), fontWeight: FontWeight.w700, fontSize: 11)),
  );
}
