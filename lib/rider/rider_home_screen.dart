import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/util.dart';
import '../screens/auth_screen.dart';
import 'rider_profile_screen.dart';
import 'rider_delivery_screen.dart';
import 'rider_location_service.dart';
import 'rider_theme.dart';
import '../screens/notifications_screen.dart';

List<Map<String, dynamic>> _asList(dynamic value) => value is List
    ? value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList()
    : <Map<String, dynamic>>[];

class RiderHomeScreen extends StatefulWidget {
  const RiderHomeScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

class _RiderHomeScreenState extends State<RiderHomeScreen> {
  List<Map<String, dynamic>> _active = [];
  List<Map<String, dynamic>> _history = [];
  Map<String, dynamic> _summary = {};
  bool _available = false;
  bool _loading = true;
  bool _refreshing = false;
  bool _availabilityBusy = false;
  int? _acceptingDeliveryId;
  bool _hasLoadedOnce = false;
  String? _error;
  late int _tab;
  bool _profileOpening = false;
  Timer? _poll;

  int get _activeDeliveryCount {
    const activeStatuses = {'assigned', 'accepted', 'picked_up', 'on_the_way'};
    return _active
        .where((item) => activeStatuses.contains(item['status']?.toString()))
        .map((item) => item['id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .length;
  }

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab.clamp(0, 2).toInt();
    _load();
    _poll = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _load(silent: true),
    );
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
          if (item['id'] != null)
            item['id'].toString(): item['status']?.toString() ?? '',
      };
      final newAssignment = _hasLoadedOnce
          ? active.cast<Map<String, dynamic>?>().firstWhere(
              (item) =>
                  item != null &&
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

      final enRouteIds = active
          .where((delivery) => delivery['status'] == 'on_the_way')
          .map((delivery) => delivery['id'])
          .whereType<num>()
          .map((id) => id.toInt())
          .toSet();
      await LocationService.I.syncActiveDeliveries(enRouteIds);
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
          _error =
              'Could not load your rider dashboard. Pull down to try again.';
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

  Future<void> _openDelivery(Map<String, dynamic> delivery) async {
    final rawId = delivery['id'];
    if (rawId is! num) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RiderDeliveryScreen(id: rawId.toInt())),
    );
    _load(silent: true);
  }

  Future<void> _openProfile() async {
    if (_profileOpening) return;
    _profileOpening = true;
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const RiderProfileScreen()));
    _profileOpening = false;
    if (mounted) {
      setState(() => _tab = 0);
      _load(silent: true);
    }
  }

  void _selectBottomTab(int value) {
    if (value == 3) {
      _openProfile();
    } else {
      setState(() => _tab = value);
    }
  }

  Future<void> _toggleAvailable(bool value) async {
    if (_availabilityBusy) return;
    setState(() => _availabilityBusy = true);
    try {
      final result = await Api.I.setAvailability(value);
      if (mounted) setState(() => _available = result);
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _availabilityBusy = false);
    }
  }

  Future<void> _acceptDelivery(Map<String, dynamic> delivery) async {
    final id = delivery['id'];
    if (id is! num || _acceptingDeliveryId != null) return;
    setState(() => _acceptingDeliveryId = id.toInt());
    try {
      await Api.I.action(id.toInt(), 'accept');
      if (!mounted) return;
      await _load(silent: true);
      if (!mounted) return;
      await _openDelivery({...delivery, 'status': 'accepted'});
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not accept this delivery. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _acceptingDeliveryId = null);
    }
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
        icon: Icon(
          Icons.notifications_active_outlined,
          color: riderAccent(context),
        ),
        title: const Text('New Delivery Request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              order['order_number']?.toString() ?? 'New order',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(customer['name']?.toString() ?? 'Customer'),
            Text(
              order['address']?.toString() ?? 'Address unavailable',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              peso(dbl(order['total'])),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: riderAccent(context),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Review Request'),
          ),
        ],
      ),
    );
    if (review == true && mounted) await _openDelivery(delivery);
  }

  @override
  Widget build(BuildContext context) {
    return RiderVisualTheme(
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: riderDeepCoffee,
          foregroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.white),
          automaticallyImplyLeading: false,
          title: const SizedBox.shrink(),
          actions: [
            IconButton(
              tooltip: 'Notifications',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              ),
              icon: const Icon(Icons.notifications_none_rounded),
            ),
          ],
        ),
        body: RiderImageBackground(
          image: _tab == 0
              ? 'assets/images/rider.png'
              : 'assets/images/all.png',
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(onRefresh: _load, child: _buildPage()),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: _selectBottomTab,
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: _deliveriesNavIcon(Icons.delivery_dining_outlined),
              selectedIcon: _deliveriesNavIcon(Icons.delivery_dining),
              label: 'Deliveries',
            ),
            NavigationDestination(
              icon: Icon(Icons.history_rounded),
              label: 'History',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }

  Widget _deliveriesNavIcon(IconData icon) => Badge(
    isLabelVisible: _activeDeliveryCount > 0,
    label: Text('$_activeDeliveryCount'),
    child: Icon(icon),
  );

  Widget _buildPage() {
    if (_tab == 0) return _dashboardPage();
    if (_tab == 2) {
      return _deliveryList(
        _history,
        'Completed and declined deliveries will appear here.',
      );
    }
    return _deliveryList(
      _active,
      _available
          ? 'Deliveries assigned to you will appear here.'
          : 'Go online when you are ready to receive delivery assignments.',
    );
  }

  Widget _dashboardPage() {
    final name = (Api.I.user?['name'] ?? 'Rider').toString();
    final assigned = _active
        .where((item) => item['status'] == 'assigned')
        .toList();
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        if (_error != null) _errorBanner(_error!),
        _welcomeCard(name),
        const SizedBox(height: 14),
        _availabilityCard(),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _metric(
                'Completed today',
                '${_summary['today'] ?? 0}',
                Icons.task_alt_rounded,
                const Color(0xFF228A60),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _metric(
                'Active deliveries',
                '$_activeDeliveryCount',
                Icons.local_shipping_outlined,
                riderAccent(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _metric(
                'Distance traveled',
                '${_summary['total_km'] ?? 0} km',
                Icons.route_rounded,
                riderAccent(context),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _metric(
                'Cash to remit',
                peso(dbl(_summary['cash_on_hand'])),
                Icons.payments_outlined,
                riderAccent(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _sectionHeader(
          'Assigned deliveries',
          action: 'View all',
          onAction: () => setState(() => _tab = 1),
        ),
        const SizedBox(height: 8),
        if (assigned.isEmpty)
          _emptyCard(
            'No deliveries assigned yet',
            _available
                ? 'Deliveries assigned to you will appear here.'
                : 'Go online when you are ready to receive delivery requests.',
            Icons.delivery_dining_rounded,
          )
        else
          ...assigned.take(3).map(_deliveryCard),
        const SizedBox(height: 12),
        _sectionHeader(
          'Recent activity',
          action: 'History',
          onAction: () => setState(() => _tab = 2),
        ),
        const SizedBox(height: 8),
        if (_history.isEmpty)
          _emptyCard(
            'No delivery history',
            'Completed and declined deliveries will appear here.',
            Icons.history_rounded,
          )
        else
          ..._history.take(3).map(_deliveryCard),
      ],
    );
  }

  Widget _welcomeCard(String name) {
    final avatar = Api.I.user?['avatar_url']?.toString();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: riderGold.withValues(alpha: .85), width: 1.3),
        image: const DecorationImage(
          image: AssetImage('assets/images/rider.png'),
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          colorFilter: ColorFilter.mode(Color(0x882A1005), BlendMode.darken),
        ),
      ),
      child: Row(
        children: [
          Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _openProfile,
              child: CircleAvatar(
                radius: 28,
                backgroundColor: Colors.white.withValues(alpha: .18),
                backgroundImage: avatar == null || avatar.isEmpty
                    ? null
                    : NetworkImage(avatar),
                child: avatar == null || avatar.isEmpty
                    ? const Icon(
                        Icons.delivery_dining_rounded,
                        color: Colors.white,
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Good day, $name',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Delivery Rider',
                  style: TextStyle(color: Colors.white.withValues(alpha: .85)),
                ),
              ],
            ),
          ),
          _OnlineBadge(
            online: _available,
            label: _available ? 'ONLINE' : 'OFFLINE',
          ),
        ],
      ),
    );
  }

  Widget _availabilityCard() => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(
            _available
                ? Icons.wifi_tethering_rounded
                : Icons.wifi_tethering_off_rounded,
            color: _available
                ? const Color(0xFF228A60)
                : riderSecondaryText(context),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _available ? 'You are online' : 'You are offline',
                  style: TextStyle(
                    color: riderPrimaryText(context),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  _available
                      ? 'Ready to receive delivery assignments'
                      : 'Turn on availability when ready',
                  style: TextStyle(
                    color: riderSecondaryText(context),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (_availabilityBusy)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Switch(value: _available, onChanged: _toggleAvailable),
        ],
      ),
    ),
  );

  Widget _metric(String label, String value, IconData icon, Color color) =>
      Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon, color: color, size: 25),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: riderPrimaryText(context),
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: riderSecondaryText(context),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _sectionHeader(
    String title, {
    String? action,
    VoidCallback? onAction,
  }) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: TextStyle(
            color: riderPrimaryText(context),
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      if (action != null) TextButton(onPressed: onAction, child: Text(action)),
    ],
  );

  Widget _deliveryList(List<Map<String, dynamic>> items, String empty) =>
      ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null) _errorBanner(_error!),
          Text(
            _tab == 1 ? 'My Deliveries' : 'Delivery History',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            _tab == 1
                ? 'Manage your assigned orders and delivery steps.'
                : 'Review your recent delivery activity.',
            style: TextStyle(color: riderSecondaryText(context)),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            _emptyCard('Nothing here yet', empty, Icons.inbox_outlined)
          else
            ...items.map(_deliveryCard),
        ],
      );

  Widget _deliveryCard(Map<String, dynamic> delivery) {
    final order = delivery['order'] is Map
        ? Map<String, dynamic>.from(delivery['order'] as Map)
        : <String, dynamic>{};
    final customer = delivery['customer'] is Map
        ? Map<String, dynamic>.from(delivery['customer'] as Map)
        : <String, dynamic>{};
    final status = delivery['status']?.toString() ?? 'assigned';
    final rawItems = order['items'];
    final items = rawItems is List
        ? rawItems
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
        : <Map<String, dynamic>>[];
    final isAvailableRequest = (_tab == 0 || _tab == 1) && status == 'assigned';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openDelivery(delivery),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      order['order_number']?.toString() ?? 'Delivery',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  _OnlineBadge(
                    online: status == 'on_the_way',
                    label: deliveryStatusLabel(status),
                  ),
                ],
              ),
              if (items.isNotEmpty) ...[
                const SizedBox(height: 9),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.receipt_long_outlined, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        items
                            .map(
                              (item) =>
                                  '${item['qty'] ?? 1} × ${item['name'] ?? 'Item'}',
                            )
                            .join(', '),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.person_outline, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(customer['name']?.toString() ?? 'Customer'),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.location_on_outlined, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      order['address']?.toString() ?? 'Address unavailable',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    peso(dbl(order['total'])),
                    style: TextStyle(
                      color: riderAccent(context),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    (order['payment_method']?.toString() ?? 'payment')
                        .toUpperCase(),
                    style: TextStyle(
                      color: riderSecondaryText(context),
                      fontSize: 11,
                    ),
                  ),
                  if (!isAvailableRequest) ...[
                    const Spacer(),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ],
              ),
              if (isAvailableRequest) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _acceptingDeliveryId == null
                        ? () => _acceptDelivery(delivery)
                        : null,
                    icon: _acceptingDeliveryId == delivery['id']
                        ? const SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(
                      _acceptingDeliveryId == delivery['id']
                          ? 'Accepting…'
                          : 'Accept Delivery',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyCard(String title, String subtitle, IconData icon) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        children: [
          Icon(icon, size: 38, color: riderSecondaryText(context)),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: riderSecondaryText(context)),
          ),
        ],
      ),
    ),
  );

  Widget _errorBanner(String text) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(
          Icons.error_outline,
          color: Theme.of(context).colorScheme.onErrorContainer,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
        ),
      ],
    ),
  );
}

class _OnlineBadge extends StatelessWidget {
  const _OnlineBadge({required this.online, this.label});
  final bool online;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final color = online
        ? const Color(0xFF228A60)
        : riderSecondaryText(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label ?? (online ? 'Online' : 'Offline'),
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
