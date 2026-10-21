import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/realtime.dart';
import '../core/animated_add_button.dart';
import '../core/util.dart';
import '../core/widgets.dart';
import '../state/cart.dart';
import '../state/favorites.dart';
import '../state/app_state.dart';
import '../state/nav.dart';
import 'notifications_screen.dart';
import 'product_screen.dart';
import 'promo_carousel.dart';
import 'promos_screen.dart';

const _serif = 'serif';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _cats = [];
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _bundles = [];
  List<Map<String, dynamic>> _promos = [];
  bool _loading = true;
  String? _error;
  int _unread = 0;
  StreamSubscription<Map<String, dynamic>>? _liveSubscription;

  @override
  void initState() {
    super.initState();
    _load();
    Favorites.I.load();
    _loadUnread();
    Realtime.I.connect();
    _liveSubscription = Realtime.I.updates.listen((event) {
      if (event['kind'] == 'notification') _loadUnread();
      if (['product', 'category', 'promo'].contains(event['kind'])) _load();
    });
    rootTab.addListener(_onTab);
  }

  @override
  void dispose() {
    rootTab.removeListener(_onTab);
    _liveSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadUnread() async {
    try {
      final n = await Api.I.notifications();
      if (mounted) {
        setState(() => _unread = (n['unread'] as num?)?.toInt() ?? 0);
      }
    } catch (_) {}
  }

  Future<void> _load() async {
    try {
      final cats = await Api.I.categories();
      final prods = await Api.I.products();
      Map<String, dynamic>? cfg;
      Map<String, dynamic>? homeData;
      try {
        homeData = await Api.I.appConfig();
        cfg = homeData;
      } catch (error) {
        debugPrint('Home merchandising request failed: $error');
      }
      List<Map<String, dynamic>> promos = [];
      try {
        promos = await Api.I.promos();
      } catch (_) {}
      prods.sort(
        (a, b) => dbl(b['avg_rating']).compareTo(dbl(a['avg_rating'])),
      );
      if (!mounted) return;
      setState(() {
        _cats = cats;
        _products = prods;
        _bundles = mapList(homeData?['home_promos'] ?? []);
        _promos = promos;
        AppState.online =
            cfg?['payment_mode'] == 'online' ||
            (cfg?['settings'] as Map?)?['payment_method'] == 'online';
        _error = null;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  // I-refresh ang home data kapag bumalik sa Home
  void _onTab() {
    if (rootTab.value == 0) _load();
  }

  // ---------- AKSYON ----------
  void _goMenu({int? category, String? search}) {
    menuRequest.value = {'category': category, 'search': search ?? ''};
    rootTab.value = 1;
  }

  void _openProduct(Map<String, dynamic> p) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProductScreen(id: p['id'] as int)),
    );
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _header(),
            _promoSection(),
            if (_bundles.isNotEmpty) _bundleSection(),
            _categories(),
            _recommended(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _promoSection() {
    final hasPromos = _promos.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 14, bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Promos',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PromosScreen()),
                  ),
                  child: const Text('See All'),
                ),
              ],
            ),
          ),
          if (_loading)
            SizedBox(
              height: 170,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < 2; i++)
                    Container(
                      width: 290,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                ],
              ),
            )
          else if (hasPromos)
            SizedBox(
              height: 170,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final promo in _promos)
                    SizedBox(
                      width: 290,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: PromoBannerCard(
                          promo: promo,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const PromosScreen(),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 14, bottom: 4),
              child: Text(
                'No active promos right now.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Open menu',
                    onPressed: () => rootScaffoldKey.currentState?.openDrawer(),
                    icon: Icon(
                      Icons.menu_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Notifications',
                    icon: Badge(
                      isLabelVisible: _unread > 0,
                      label: Text('$_unread'),
                      child: Icon(
                        Icons.notifications_none,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const NotificationsScreen(),
                        ),
                      );
                      _loadUnread();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 4),
              _homeBanner(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _homeBanner() {
    return AspectRatio(
      aspectRatio: 1.5,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset('assets/images/home.png', fit: BoxFit.cover),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Color(0x99000000), Color(0x00000000)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Good Coffee,\nBetter Days',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      height: 1.08,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Freshly brewed for every moment.',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: () => _goMenu(),
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 9,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Order Now ',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _categories() {
    String emoji(String n) {
      final s = n.toLowerCase();
      if (s.contains('non')) {
        return 'ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â°ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¸ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¥ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Âº';
      }
      if (s.contains('iced')) {
        return 'ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â°ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¸ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â§ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¹';
      }
      if (s.contains('hot')) {
        return 'ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¹ÃƒÆ’Ã¢â‚¬Â¦ÃƒÂ¢Ã¢â€šÂ¬Ã…â€œÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢';
      }
      if (s.contains('pastr') || s.contains('bread')) {
        return 'ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â°ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¸ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¥ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â';
      }
      return 'ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â°ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¸ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚ÂÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â½ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¯ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¸ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â';
    }

    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(width: 16),
              Expanded(
                child: Container(
                  height: 1.5,
                  color: Theme.of(context).colorScheme.primary
                      .withValues(alpha: 0.5),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'Categories',
                  style: TextStyle(
                    fontFamily: _serif,
                    fontStyle: FontStyle.italic,
                    fontSize: 21,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  height: 1.5,
                  color: Theme.of(context).colorScheme.primary
                      .withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(width: 16),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            )
          else
            SizedBox(
              // Leave enough room for two-line category names on phones.
              height: 116,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  InkWell(
                    onTap: () => _goMenu(),
                    child: SizedBox(
                      width: 78,
                      child: Column(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.12),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.apps_rounded,
                              color: Theme.of(context).colorScheme.primary,
                              size: 27,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'All',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  for (final c in _cats)
                    InkWell(
                      onTap: () => _goMenu(category: c['id'] as int),
                      child: SizedBox(
                        width: 78,
                        child: Column(
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.12),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child:
                                    (c['image_url'] ?? '').toString().isNotEmpty
                                    ? NetImage(
                                        c['image_url']?.toString(),
                                        width: 56,
                                        height: 56,
                                      )
                                    : Center(
                                        child: Text(
                                          emoji('${c['name']}'),
                                          style: const TextStyle(fontSize: 30),
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${c['name']}'.toUpperCase(),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                letterSpacing: 0.6,
                                height: 1.05,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _recommended() {
    final items = _products.take(8).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Padding(
                padding: EdgeInsets.only(left: 4),
                child: Text(
                  'Explore the Menu',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _goMenu(),
                child: Text(
                  'See All',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          if (!_loading && items.isEmpty && _error == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('No products available yet.')),
            ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.78,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: items.length,
            itemBuilder: (_, i) => _miniCard(items[i]),
          ),
        ],
      ),
    );
  }

  Widget _bundleSection() => _horizontalSection(
    'Bundle Deals',
    _bundles.map((bundle) {
      final name = bundle['name']?.toString() ?? 'Bundle';
      final products = mapList(bundle['products'])
          .map((item) => "${item['name']} x ${item['quantity']}")
          .join(' · ');
      final price = peso(dbl(bundle['price']));
      final savings = peso(dbl(bundle['savings']));

      return SizedBox(
        width: 270,
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 120,
                width: double.infinity,
                child: NetImage(bundle['image_url']?.toString()),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      products,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$price · Save $savings',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            Cart.I.addBundle(bundle);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Bundle added to cart'),
                              ),
                            );
                          },
                          icon: const Icon(Icons.add_shopping_cart),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }).toList(),
  );
  Widget _productSection(
    String title,
    List<Map<String, dynamic>> products, {
    bool bestSeller = false,
  }) => _horizontalSection(
    title,
    products
        .map(
          (product) => SizedBox(
            width: 170,
            child: _miniCard(product, bestSeller: bestSeller),
          ),
        )
        .toList(),
  );

  Widget _horizontalSection(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 14, 0, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 14, bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        SizedBox(
          height: 245,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final child in children)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: child,
                ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _miniCard(Map<String, dynamic> p, {bool bestSeller = false}) {
    final rating = dbl(p['avg_rating']);
    return InkWell(
      onTap: () => _openProduct(p),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 7,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: NetImage(p['image_url']?.toString()),
                  ),
                  if (bestSeller || p['discount_active'] == true)
                    Positioned(
                      top: 5,
                      left: 5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          bestSeller ? 'Best Seller' : 'SALE',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  if (rating > 0 && !bestSeller && p['discount_active'] != true)
                    Positioned(
                      top: 5,
                      left: 5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface
                              .withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.star,
                              size: 11,
                              color: Colors.amber,
                            ),
                            Text(
                              rating.toStringAsFixed(1),
                              style: const TextStyle(fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: ListenableBuilder(
                      listenable: Favorites.I,
                      builder: (_, _) {
                        final fav = Favorites.I.has(p['id'] as int);
                        return GestureDetector(
                          onTap: () => Favorites.I.toggle(p),
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              fav ? Icons.favorite : Icons.favorite_border,
                              size: 16,
                              color: fav
                                  ? Colors.red
                                  : Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 7),
            Text(
              '${p['name']}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        peso(dbl(p['sale_price'] ?? p['base_price'])),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      if (p['discount_active'] == true)
                        Text(
                          peso(dbl(p['base_price'])),
                          style: TextStyle(
                            fontSize: 10,
                            decoration: TextDecoration.lineThrough,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                AnimatedAddButton(onPressed: () => _openProduct(p), size: 29),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
