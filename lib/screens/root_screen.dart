import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../state/cart.dart';
import '../state/favorites.dart';
import '../state/nav.dart';
import 'addresses_screen.dart';
import 'auth_screen.dart';
import 'cart_screen.dart';
import 'favorites_screen.dart';
import 'home_screen.dart';
import 'menu_screen.dart';
import 'notifications_screen.dart';
import 'orders_screen.dart';
import 'promos_screen.dart';
import 'profile_screen.dart';

// Para makita pa rin ang rootTab / menuRequest ng mga file na nag-import ng root_screen.dart
export '../state/nav.dart';

class RootScreen extends StatelessWidget {
  const RootScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: rootTab,
      builder: (_, tab, _) => PopScope<Object?>(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && rootTab.value != 0) rootTab.value = 0;
        },
        child: Scaffold(
          key: rootScaffoldKey,
          drawer: const _CustomerDrawer(),
          body: IndexedStack(
            index: tab,
            children: const [
              HomeScreen(),
              MenuScreen(),
              CartScreen(),
              OrdersScreen(),
              ProfileScreen(),
            ],
          ),
          bottomNavigationBar: _BottomBar(
            index: tab,
            onTap: (i) => rootTab.value = i,
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const _BottomBar({required this.index, required this.onTap});

  static const _items = [
    (0, Icons.home_outlined, 'Home'),
    (1, Icons.grid_view_rounded, 'Menu'),
    (2, Icons.shopping_cart_outlined, 'Cart'),
    (3, Icons.assignment_outlined, 'Orders'),
    (4, Icons.person_outline, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              for (final item in _items)
                Expanded(
                  child: InkWell(
                    onTap: () => onTap(item.$1),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (item.$1 == 2)
                          AnimatedBuilder(
                            animation: Cart.I,
                            builder: (context, _) => Badge(
                              isLabelVisible: Cart.I.count > 0,
                              label: Text('${Cart.I.count}'),
                              backgroundColor: const Color(0xFFE53935),
                              textColor: Colors.white,
                              child: Icon(
                                item.$2,
                                size: 23,
                                color: item.$1 == index
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        else
                          Icon(
                            item.$2,
                            size: 23,
                            color: item.$1 == index
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        const SizedBox(height: 3),
                        Text(
                          item.$3,
                          style: TextStyle(
                            fontSize: 10,
                            color: item.$1 == index
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomerDrawer extends StatefulWidget {
  const _CustomerDrawer();

  @override
  State<_CustomerDrawer> createState() => _CustomerDrawerState();
}

class _CustomerDrawerState extends State<_CustomerDrawer> {
  int _orderCount = 0;
  int _cartCount = 0;
  Timer? _orderCountTimer;

  @override
  void initState() {
    super.initState();
    _cartCount = Cart.I.count;
    Cart.I.addListener(_onCartChanged);
    _loadOrderCount();
    _orderCountTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _loadOrderCount(),
    );
  }

  void _onCartChanged() {
    if (mounted && _cartCount != Cart.I.count) {
      setState(() => _cartCount = Cart.I.count);
    }
  }

  @override
  void dispose() {
    Cart.I.removeListener(_onCartChanged);
    _orderCountTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadOrderCount() async {
    try {
      final orders = await Api.I.orders();
      if (mounted && _orderCount != orders.length) {
        setState(() => _orderCount = orders.length);
      }
    } catch (_) {
      // Keep the last count when the API is temporarily unavailable.
    }
  }

  void _tab(BuildContext context, int tab) {
    Navigator.pop(context);
    rootTab.value = tab;
  }

  void _page(BuildContext context, Widget page) {
    Navigator.pop(context);
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  Future<void> _logout(BuildContext context) async {
    final navigator = Navigator.of(context);
    Navigator.pop(context);
    Cart.I.clear();
    Favorites.I.clear();
    await Api.I.logout();
    rootTab.value = 0;
    if (navigator.mounted) {
      navigator.pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const AuthScreen()),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Api.I.user ?? {};
    return Drawer(
      backgroundColor: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 24, 16, 22),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _tab(context, 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 58,
                      height: 58,
                      child: ClipOval(
                        child: (user['avatar_url'] ?? '').toString().isEmpty
                            ? ColoredBox(
                                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                child: Icon(
                                  Icons.person_rounded,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 34,
                                ),
                              )
                            : Image.network(
                                fixUrl(user['avatar_url'].toString()),
                                fit: BoxFit.cover,
                                headers: const {
                                  'ngrok-skip-browser-warning': 'true',
                                },
                                errorBuilder: (_, __, ___) => ColoredBox(
                                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                  child: Icon(
                                    Icons.person_rounded,
                                    color: Theme.of(context).colorScheme.primary,
                                    size: 34,
                                  ),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Customer Profile',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${user['name'] ?? 'Customer'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _item(
                    context,
                    Icons.home_outlined,
                    'Home',
                    () => _tab(context, 0),
                  ),
                  _item(
                    context,
                    Icons.grid_view_rounded,
                    'Menu',
                    () => _tab(context, 1),
                  ),
                  _item(
                    context,
                    Icons.shopping_cart_outlined,
                    'Cart',
                    () => _tab(context, 2),
                    badgeCount: _cartCount,
                  ),
                  _item(
                    context,
                    Icons.assignment_outlined,
                    'My Orders',
                    () => _tab(context, 3),
                    badgeCount: _orderCount,
                  ),
                  _item(
                    context,
                    Icons.local_offer_outlined,
                    'Promos',
                    () => _page(context, const PromosScreen()),
                  ),
                  const Divider(indent: 18, endIndent: 18),
                  _item(
                    context,
                    Icons.place_outlined,
                    'Saved Addresses',
                    () => _page(context, const AddressesScreen()),
                  ),
                  _item(
                    context,
                    Icons.favorite_border,
                    'Favorites',
                    () => _page(context, const FavoritesScreen()),
                  ),
                  _item(
                    context,
                    Icons.notifications_none,
                    'Notifications',
                    () => _page(context, const NotificationsScreen()),
                  ),
                  _item(
                    context,
                    Icons.person_outline,
                    'Profile',
                    () => _tab(context, 4),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            _item(
              context,
              Icons.logout,
              'Log out',
              () => _logout(context),
              color: const Color(0xFF8D3C32),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap, {
    Color? color,
    int? badgeCount,
  }) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 56,
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Icon(icon, color: color ?? Theme.of(context).colorScheme.onSurface),
              const SizedBox(width: 32),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color ?? Theme.of(context).colorScheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (badgeCount != null && badgeCount > 0) ...[
                const SizedBox(width: 12),
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE86B68),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    badgeCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
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
}
