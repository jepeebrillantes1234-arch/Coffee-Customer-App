import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/api.dart';
import '../core/util.dart';
import '../screens/auth_screen.dart';
import 'rider_delivery_screen.dart';
import 'rider_location_service.dart';
import 'rider_profile_screen.dart';
import 'rider_theme.dart';

List<Map<String, dynamic>> _asList(dynamic value) => value is List
    ? value.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
    : <Map<String, dynamic>>[];

class RiderHomeScreen extends StatefulWidget {
  const RiderHomeScreen({super.key});

  @override
  State<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

class _RiderHomeScreenState extends State<RiderHomeScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  List<Map<String, dynamic>> _active = [];
  List<Map<String, dynamic>> _history = [];
  Map<String, dynamic> _summary = {};
  bool _available = false;
  bool _loading = true;
  bool _refreshing = false;
  bool _availabilityBusy = false;
  bool _profileOpening = false;
  bool _hasLoadedOnce = false;
  String? _error;
  int _tab = 0;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final results = await Future.wait([Api.I.deliveries(), Api.I.history()]);
      if (!mounted) return;
      final activeResponse = results[0];
      final historyResponse = results[1];
      final active = _asList(activeResponse['items']);
      final previousStatus = <String, String>{
        for (final item in _active)
          if (item['id'] != null) item['id'].toString(): item['status']?.toString() ?? '',
      };
      final newAssignment = _hasLoadedOnce
          ? active.cast<Map<String, dynamic>?>().firstWhere(
              (item) => item != null &&
                  item['status'] == 'assigned' &&
                  previousStatus[item['id']?.toString()] != 'assigned',
              orElse: () => null,
            )
          : null;
      _hasLoadedOnce = true;
      setState(() {
        _active = active;
        _history = _asList(historyResponse['items']);
        _summary = historyResponse['summary'] is Map
            ? Map<String, dynamic>.from(historyResponse['summary'] as Map)
            : {};
        _available = activeResponse['is_available'] == true;
        _error = null;
        _loading = false;
      });

      Map<String, dynamic>? enRoute;
      for (final delivery in active) {
        if (delivery['status'] == 'on_the_way') {
          enRoute = delivery;
          break;
        }
      }
      final deliveryId = enRoute?['id'];
      if (deliveryId is num) {
        await LocationService.I.start(deliveryId: deliveryId.toInt());
      } else {
        await LocationService.I.stop();
      }
      if (newAssignment != null && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showNewAssignment(newAssignment);
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
      if (!Api.I.loggedIn) _goLogin();
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not load your rider dashboard. Pull down to try again.';
          _loading = false;
        });
      }
    } finally {
      _refreshing = false;
    }
  }

  void _goLogin() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (_) => false,
    );
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to sign in again to manage deliveries.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Log Out')),
        ],
      ),
    );
    if (confirmed != true) return;
    await LocationService.I.stop();
    await Api.I.logout();
    if (mounted) _goLogin();
  }

  Future<void> _toggleAvailable(bool value) async {
    if (_availabilityBusy) return;
    setState(() => _availabilityBusy = true);
    try {
      final result = await Api.I.setAvailability(value);
      if (mounted) setState(() => _available = result);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _availabilityBusy = false);
    }
  }

  Future<void> _openDelivery(Map<String, dynamic> delivery) async {
    final rawId = delivery['id'];
    if (rawId is! num) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RiderDeliveryScreen(id: rawId.toInt())),
    );
    _load(silent: true);
  }

  Future<void> _showNewAssignment(Map<String, dynamic> delivery) async {
    final order = delivery['order'] is Map
        ? Map<String, dynamic>.from(delivery['order'] as Map)
        : <String, dynamic>{};
    final customer = delivery['customer'] is Map
        ? Map<String, dynamic>.from(delivery['customer'] as Map)
        : <String, dynamic>{};
    final review = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(Icons.notifications_active_outlined, color: riderAccent(context)),
        title: const Text('New Delivery Request'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(order['order_number']?.toString() ?? 'New order', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(customer['name']?.toString() ?? 'Customer'),
          Text(order['address']?.toString() ?? 'Address unavailable', maxLines: 3, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          Text(peso(dbl(order['total'])), style: TextStyle(fontWeight: FontWeight.w800, color: riderAccent(context))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Later')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Review Request')),
        ],
      ),
    );
    if (review == true && mounted) await _openDelivery(delivery);
  }

  Future<void> _openProfile() async {
    if (_profileOpening) return;
    _profileOpening = true;
    _scaffoldKey.currentState?.closeDrawer();
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RiderProfileScreen()));
    _profileOpening = false;
    if (mounted) setState(() => _tab = 0);
  }

  void _selectDrawerTab(int value) {
    setState(() => _tab = value);
    _scaffoldKey.currentState?.closeDrawer();
  }

  void _selectBottomTab(int value) {
    if (value == 3) {
      _openProfile();
    } else {
      setState(() => _tab = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Api.I.user ?? {};
    final name = (user['name'] ?? 'Rider').toString();
    final theme = Theme.of(context);

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('Rider Dashboard', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(tooltip: 'Refresh', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded)),
          IconButton(tooltip: 'Profile settings', onPressed: _openProfile, icon: const Icon(Icons.account_circle_outlined)),
        ],
      ),
      drawer: _buildDrawer(name, user),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _buildPage(theme, name),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _selectBottomTab,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.delivery_dining_outlined), selectedIcon: Icon(Icons.delivery_dining), label: 'Deliveries'),
          NavigationDestination(icon: Icon(Icons.history_rounded), label: 'History'),
          NavigationDestination(icon: Icon(Icons.person_outline_rounded), label: 'Profile'),
        ],
      ),
    );
  }

  Widget _buildDrawer(String name, Map<String, dynamic> user) {
    final avatar = user['avatar_url']?.toString();
    return NavigationDrawer(
      selectedIndex: _tab < 3 ? _tab : 0,
      onDestinationSelected: _selectDrawerTab,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 16, 18),
          child: Row(children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: riderGreen.withValues(alpha: .12),
              backgroundImage: avatar == null || avatar.isEmpty ? null : NetworkImage(avatar),
              child: avatar == null || avatar.isEmpty ? const Icon(Icons.delivery_dining, color: riderGreen) : null,
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
              const Text('Delivery Rider'),
              const SizedBox(height: 5),
              _OnlineBadge(online: _available),
            ])),
          ]),
        ),
        const Divider(),
        const NavigationDrawerDestination(icon: Icon(Icons.home_outlined), label: Text('Home')),
        const NavigationDrawerDestination(icon: Icon(Icons.delivery_dining_outlined), label: Text('My Deliveries')),
        const NavigationDrawerDestination(icon: Icon(Icons.history_rounded), label: Text('Delivery History')),
        const Padding(padding: EdgeInsets.fromLTRB(28, 20, 16, 8), child: Text('ACCOUNT', style: TextStyle(fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w700))),
        ListTile(leading: const Icon(Icons.settings_outlined), title: const Text('Profile Settings'), onTap: _openProfile),
        ListTile(leading: const Icon(Icons.help_outline_rounded), title: const Text('Help & Support'), onTap: () => _showInfo('Help & Support', 'For delivery or account help, contact your coffee shop administrator.')),
        ListTile(leading: const Icon(Icons.info_outline_rounded), title: const Text('About'), onTap: () => _showInfo('About', 'KJM Coffee Brew Rider\nDelivery partner app')),
        const Divider(),
        ListTile(leading: const Icon(Icons.logout_rounded, color: Colors.red), title: const Text('Log Out'), onTap: _logout),
      ],
    );
  }

  Widget _buildPage(ThemeData theme, String name) {
    if (_tab == 1) return _deliveryList(_active, 'No assigned deliveries yet. Stay online to receive new assignments.');
    if (_tab == 2) return _deliveryList(_history, 'Completed and declined deliveries will appear here.');
    if (_tab == 3) {
      return Center(child: FilledButton.icon(onPressed: _openProfile, icon: const Icon(Icons.settings), label: const Text('Open Profile Settings')));
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        if (_error != null) _errorBanner(_error!),
        Text('Hello, $name', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: riderAccent(context))),
        const SizedBox(height: 4),
        Text('Here is your delivery overview.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        _availabilityCard(),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _metric('Completed today', '${_summary['today'] ?? 0}', Icons.task_alt_rounded, const Color(0xFF228A60))),
          const SizedBox(width: 10),
          Expanded(child: _metric('Total deliveries', '${_summary['total_deliveries'] ?? 0}', Icons.local_shipping_outlined, const Color(0xFF287CC1))),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _metric('Distance traveled', '${_summary['total_km'] ?? 0} km', Icons.route_rounded, const Color(0xFF8C57B7))),
          const SizedBox(width: 10),
          Expanded(child: _metric('Cash to remit', peso(dbl(_summary['cash_on_hand'])), Icons.payments_outlined, const Color(0xFFE49320))),
        ]),
        const SizedBox(height: 18),
        _sectionHeader('Current delivery', action: _active.isNotEmpty ? 'View all' : null, onAction: () => setState(() => _tab = 1)),
        if (_active.isNotEmpty) ...[
          const SizedBox(height: 10),
          _mapPreview(_active.first),
          const SizedBox(height: 10),
          _deliveryCard(_active.first),
        ] else
          _emptyCard('No active delivery', _available ? 'You are online and ready for an assignment.' : 'Go online when you are ready to receive delivery assignments.', Icons.delivery_dining_rounded),
        const SizedBox(height: 18),
        _sectionHeader('Recent activity', action: _history.isNotEmpty ? 'History' : null, onAction: () => setState(() => _tab = 2)),
        const SizedBox(height: 8),
        if (_history.isEmpty)
          _emptyCard('No delivery history', 'Your completed deliveries will show here.', Icons.history_rounded)
        else
          ..._history.take(3).map(_deliveryCard),
      ],
    );
  }

  Widget _availabilityCard() => Card(
    color: _available ? riderGreen : Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        Icon(_available ? Icons.wifi_tethering_rounded : Icons.wifi_tethering_off_rounded, color: _available ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_available ? 'You are online' : 'You are offline', style: TextStyle(color: _available ? Colors.white : null, fontWeight: FontWeight.w800, fontSize: 16)),
          Text(_available ? 'Ready to receive delivery assignments' : 'Turn on availability when you are ready', style: TextStyle(color: _available ? Colors.white70 : Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
        ])),
        if (_availabilityBusy) const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) else Switch(value: _available, onChanged: _toggleAvailable, activeThumbColor: Colors.white),
      ]),
    ),
  );

  Widget _metric(String label, String value, IconData icon, Color color) => Card(
    child: Padding(padding: const EdgeInsets.all(13), child: Row(children: [
      Container(width: 42, height: 42, decoration: BoxDecoration(color: color.withValues(alpha: .13), borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: color)),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)), Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant))])),
    ])),
  );

  Widget _sectionHeader(String title, {String? action, VoidCallback? onAction}) => Row(children: [
    Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
    if (action != null) TextButton(onPressed: onAction, child: Text(action)),
  ]);

  Widget _mapPreview(Map<String, dynamic> delivery) {
    final order = delivery['order'] is Map ? Map<String, dynamic>.from(delivery['order'] as Map) : <String, dynamic>{};
    final lat = double.tryParse('${order['lat'] ?? ''}');
    final lng = double.tryParse('${order['lng'] ?? ''}');
    if (lat == null || lng == null) {
      return _emptyCard('Delivery map unavailable', 'The customer address does not include map coordinates.', Icons.map_outlined);
    }
    final point = LatLng(lat, lng);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(height: 190, child: Stack(children: [
        FlutterMap(
          options: MapOptions(initialCenter: point, initialZoom: 14),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.kjmcoffeebrew.app'),
            MarkerLayer(markers: [Marker(point: point, width: 44, height: 44, child: const Icon(Icons.location_on, color: riderGreen, size: 40))]),
          ],
        ),
        Positioned(left: 12, right: 12, bottom: 12, child: FilledButton.icon(onPressed: () => _openDelivery(delivery), icon: const Icon(Icons.navigation_rounded), label: const Text('Open delivery'))),
      ])),
    );
  }

  Widget _deliveryList(List<Map<String, dynamic>> items, String empty) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.all(16),
    children: [
      if (_error != null) _errorBanner(_error!),
      Text(_tab == 1 ? 'My Deliveries' : 'Delivery History', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      Text(_tab == 1 ? 'Manage your assigned orders and delivery steps.' : 'Review your recent delivery activity.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(height: 12),
      if (items.isEmpty) _emptyCard('Nothing here yet', empty, Icons.inbox_outlined) else ...items.map(_deliveryCard),
    ],
  );

  Widget _deliveryCard(Map<String, dynamic> delivery) {
    final order = delivery['order'] is Map ? Map<String, dynamic>.from(delivery['order'] as Map) : <String, dynamic>{};
    final customer = delivery['customer'] is Map ? Map<String, dynamic>.from(delivery['customer'] as Map) : <String, dynamic>{};
    final status = delivery['status']?.toString() ?? 'assigned';
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openDelivery(delivery),
        child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text(order['order_number']?.toString() ?? 'Delivery', style: const TextStyle(fontWeight: FontWeight.w800))), _OnlineBadge(online: status == 'on_the_way', label: deliveryStatusLabel(status))]),
          const SizedBox(height: 10),
          Row(children: [const Icon(Icons.person_outline, size: 18), const SizedBox(width: 6), Expanded(child: Text(customer['name']?.toString() ?? 'Customer'))]),
          const SizedBox(height: 5),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.location_on_outlined, size: 18), const SizedBox(width: 6), Expanded(child: Text(order['address']?.toString() ?? 'Address unavailable', maxLines: 2, overflow: TextOverflow.ellipsis))]),
          const SizedBox(height: 10),
          Row(children: [Text(peso(dbl(order['total'])), style: TextStyle(color: riderAccent(context), fontWeight: FontWeight.w800)), const SizedBox(width: 8), Text((order['payment_method']?.toString() ?? 'payment').toUpperCase(), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11)), const Spacer(), const Icon(Icons.chevron_right_rounded)]),
        ])),
      ),
    );
  }

  Widget _emptyCard(String title, String subtitle, IconData icon) => Card(
    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24), child: Column(children: [
      Icon(icon, size: 38, color: Theme.of(context).colorScheme.onSurfaceVariant),
      const SizedBox(height: 8),
      Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
    ])),
  );

  Widget _errorBanner(String text) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.errorContainer, borderRadius: BorderRadius.circular(12)),
    child: Row(children: [Icon(Icons.error_outline, color: Theme.of(context).colorScheme.onErrorContainer), const SizedBox(width: 8), Expanded(child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)))]),
  );

  void _showInfo(String title, String body) {
    Navigator.pop(context);
    showDialog<void>(context: context, builder: (context) => AlertDialog(title: Text(title), content: Text(body), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))]));
  }
}

class _OnlineBadge extends StatelessWidget {
  const _OnlineBadge({required this.online, this.label});
  final bool online;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final color = online ? const Color(0xFF228A60) : Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)), const SizedBox(width: 5), Text(label ?? (online ? 'Online' : 'Offline'), style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700))]),
    );
  }
}
