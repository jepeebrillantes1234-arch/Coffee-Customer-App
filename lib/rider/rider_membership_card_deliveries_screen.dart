import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import 'rider_map_utils.dart';

class RiderMembershipCardDeliveriesScreen extends StatefulWidget {
  const RiderMembershipCardDeliveriesScreen({super.key});

  @override
  State<RiderMembershipCardDeliveriesScreen> createState() =>
      _RiderMembershipCardDeliveriesScreenState();
}

class _RiderMembershipCardDeliveriesScreenState
    extends State<RiderMembershipCardDeliveriesScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  String _label(String value) => switch (value) {
    'pending' => 'Pending',
    'preparing_card' => 'Preparing Card',
    'ready_for_delivery' => 'Ready for Delivery',
    'out_for_delivery' => 'Out for Delivery',
    'delivered' => 'Delivered',
    _ => value,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final response = await Api.I.riderMembershipCardDeliveries();
      if (!mounted) return;
      final items = response['items'];
      setState(() {
        _items = items is List
            ? items
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .toList()
            : [];
        _loading = false;
        _error = null;
      });
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not load membership card deliveries.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Membership Card Deliveries')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _load,
            child: _items.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 130),
                      Center(
                        child: Text(
                          _error ?? 'No membership card deliveries are assigned to you.',
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      final customer = item['customer'] is Map
                          ? Map<String, dynamic>.from(item['customer'])
                          : <String, dynamic>{};
                      final address = item['address'] is Map
                          ? Map<String, dynamic>.from(item['address'])
                          : <String, dynamic>{};
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.credit_card_rounded),
                          ),
                          title: Text(
                            customer['name']?.toString() ?? 'Customer',
                          ),
                          subtitle: Text(
                            '${_label(item['status']?.toString() ?? 'pending')}\n${address['full_address'] ?? 'Address unavailable'}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          isThreeLine: true,
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () async {
                            final id = (item['id'] as num?)?.toInt();
                            if (id == null) return;
                            await Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    _MembershipCardDeliveryDetailScreen(
                                      deliveryId: id,
                                    ),
                              ),
                            );
                            if (mounted) _load();
                          },
                        ),
                      );
                    },
                  ),
          ),
  );
}

class _MembershipCardDeliveryDetailScreen extends StatefulWidget {
  const _MembershipCardDeliveryDetailScreen({required this.deliveryId});
  final int deliveryId;

  @override
  State<_MembershipCardDeliveryDetailScreen> createState() =>
      _MembershipCardDeliveryDetailScreenState();
}

class _MembershipCardDeliveryDetailScreenState
    extends State<_MembershipCardDeliveryDetailScreen> {
  final MapController _mapController = MapController();
  Map<String, dynamic>? _delivery;
  Position? _position;
  StreamSubscription<Position>? _gpsSubscription;
  Timer? _pollTimer;
  Timer? _locationTimer;
  DateTime? _lastLocationSent;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _gpsError;

  @override
  void initState() {
    super.initState();
    _load();
    _startGps();
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  @override
  void dispose() {
    _gpsSubscription?.cancel();
    _pollTimer?.cancel();
    _locationTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final response = await Api.I.riderMembershipCardDelivery(
        widget.deliveryId,
      );
      if (!mounted) return;
      setState(() {
        _delivery = response;
        _loading = false;
        _error = null;
      });
      _syncLocationTimer();
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not load this delivery.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _startGps() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) {
          setState(
            () => _gpsError =
                'Turn on your phone location/GPS to show your live location.',
          );
        }
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.unableToDetermine) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever ||
          permission == LocationPermission.unableToDetermine) {
        if (mounted) {
          setState(
            () => _gpsError = permission == LocationPermission.deniedForever
                ? 'Location permission is blocked. Allow it in app Settings.'
                : 'Location permission was denied.',
          );
        }
        return;
      }
      final first = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _position = first;
        _gpsError = null;
      });
      _gpsSubscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 5,
            ),
          ).listen(
            (position) {
              if (!mounted) return;
              setState(() {
                _position = position;
                _gpsError = null;
              });
              _sendLocationIfDue();
            },
            onError: (_) {
              if (mounted) {
                setState(
                  () => _gpsError =
                      'GPS updates stopped. Check location access and GPS.',
                );
              }
            },
          );
      _sendLocationIfDue();
    } catch (_) {
      if (mounted) {
        setState(
          () => _gpsError = 'Could not get the current GPS location. Check GPS and try again.',
        );
      }
    }
  }

  void _syncLocationTimer() {
    final enRoute = _delivery?['status'] == 'out_for_delivery';
    if (enRoute && _locationTimer == null) {
      _locationTimer = Timer.periodic(
        const Duration(seconds: 8),
        (_) => _sendLocationIfDue(force: true),
      );
      _sendLocationIfDue(force: true);
    } else if (!enRoute) {
      _locationTimer?.cancel();
      _locationTimer = null;
    }
  }

  Future<void> _sendLocationIfDue({bool force = false}) async {
    final position = _position;
    if (_delivery?['status'] != 'out_for_delivery' || position == null) return;
    final now = DateTime.now();
    if (!force &&
        _lastLocationSent != null &&
        now.difference(_lastLocationSent!) < const Duration(seconds: 8)) {
      return;
    }
    if (now.difference(position.timestamp).abs() >
        const Duration(seconds: 30)) {
      if (mounted) {
        setState(() => _gpsError = 'Waiting for a fresh GPS location.');
      }
      return;
    }
    _lastLocationSent = now;
    try {
      await Api.I.sendMembershipCardDeliveryLocation(
        widget.deliveryId,
        position.latitude,
        position.longitude,
        position.accuracy,
      );
      if (mounted) setState(() => _gpsError = null);
    } on ApiException catch (error) {
      if (mounted) setState(() => _gpsError = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _gpsError = 'Unable to share membership delivery location.',
        );
      }
    }
  }

  Future<void> _action(String action) async {
    setState(() => _busy = true);
    try {
      await Api.I.riderMembershipCardDeliveryAction(widget.deliveryId, action);
      await _load();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _callCustomer(String? phone) async {
    final value = phone?.trim() ?? '';
    if (value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Customer phone number is unavailable.')),
      );
      return;
    }
    final uri = Uri(scheme: 'tel', path: value);
    if (!await launchUrl(uri)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the phone dialer.')),
        );
      }
    }
  }

  Future<void> _navigate(Map<String, dynamic> address) async {
    final lat = double.tryParse('${address['lat'] ?? ''}');
    final lng = double.tryParse('${address['lng'] ?? ''}');
    final full = (address['full_address'] ?? '').toString().trim();
    if (lat != null && lng != null) {
      final uri = Uri.parse('google.navigation:q=$lat,$lng');
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    }
    if (full.isNotEmpty) {
      final uri = Uri.https('www.google.com', '/maps/dir/', {
        'api': '1',
        'destination': full,
      });
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No valid customer destination is available.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _delivery;
    final customer = data?['customer'] is Map
        ? Map<String, dynamic>.from(data!['customer'] as Map)
        : <String, dynamic>{};
    final address = data?['address'] is Map
        ? Map<String, dynamic>.from(data!['address'] as Map)
        : <String, dynamic>{};
    final destination = latLngFrom({
      'lat': address['lat'],
      'lng': address['lng'],
    });
    final gpsPoint = _position == null
        ? null
        : LatLng(_position!.latitude, _position!.longitude);
    final route = routePointsFrom(data?['route']);
    final center = gpsPoint ?? destination;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Membership Card Delivery')),
      body: _loading && data == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && data == null
          ? Center(child: Text(_error!))
          : Column(
              children: [
                Expanded(
                  child: center == null
                      ? Center(
                          child: Text(
                            'Destination coordinates are unavailable. Use the address to navigate.',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        )
                      : FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter: center,
                            initialZoom: 15,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.kjmcoffeebrew.app',
                            ),
                            if (route.length > 1)
                              PolylineLayer(
                                polylines: [
                                  Polyline(
                                    points: route,
                                    color: scheme.primary,
                                    strokeWidth: 5,
                                  ),
                                ],
                              ),
                            MarkerLayer(
                              markers: [
                                if (destination != null)
                                  Marker(
                                    point: destination,
                                    width: 48,
                                    height: 52,
                                    child: Icon(
                                      Icons.location_pin,
                                      color: scheme.error,
                                      size: 46,
                                    ),
                                  ),
                                if (gpsPoint != null)
                                  Marker(
                                    point: gpsPoint,
                                    width: 46,
                                    height: 46,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: scheme.primary,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: scheme.surface,
                                          width: 3,
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.two_wheeler_rounded,
                                        color: scheme.onPrimary,
                                        size: 24,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                ),
                if (_gpsError != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    child: Text(
                      _gpsError!,
                      style: TextStyle(color: scheme.error),
                    ),
                  ),
                if (data?['route'] is Map &&
                    (data!['route'] as Map)['status'] != 'available' &&
                    data['status'] == 'out_for_delivery')
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    child: Text(
                      (data['route'] as Map)['error']?.toString() ??
                          'Waiting for fresh rider GPS and route.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                _detailPanel(customer, address, data ?? const {}),
              ],
            ),
    );
  }

  Widget _detailPanel(
    Map<String, dynamic> customer,
    Map<String, dynamic> address,
    Map<String, dynamic> data,
  ) {
    final status = data['status']?.toString() ?? 'pending';
    final phone = customer['phone']?.toString();
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: scheme.surface,
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 12,
              offset: Offset(0, -3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              customer['name']?.toString() ?? 'Customer',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (phone?.isNotEmpty == true)
              Text(phone!, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 5),
            Text(address['full_address']?.toString() ?? 'Address unavailable'),
            Text(
              [address['barangay'], address['city'], address['province']]
                  .where((value) => value != null && '$value'.trim().isNotEmpty)
                  .join(', '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if ((address['notes']?.toString() ?? '').isNotEmpty)
              Text('Landmark / notes: ${address['notes']}'),
            if (address['lat'] != null && address['lng'] != null)
              Text(
                'Destination: ${address['lat']}, ${address['lng']}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 8),
            Text(
              'Status: ${_label(status)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _callCustomer(phone),
                  icon: const Icon(Icons.call_outlined),
                  label: const Text('Call Customer'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _navigate(address),
                  icon: const Icon(Icons.navigation_outlined),
                  label: const Text('Navigate'),
                ),
                if (status == 'ready_for_delivery')
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _action('start'),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Start Delivery'),
                  ),
                if (status == 'out_for_delivery')
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _action('delivered'),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Mark Delivered'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _label(String value) => switch (value) {
    'pending' => 'Pending',
    'preparing_card' => 'Preparing Card',
    'ready_for_delivery' => 'Ready for Delivery',
    'out_for_delivery' => 'Out for Delivery',
    'delivered' => 'Delivered',
    _ => value,
  };
}
