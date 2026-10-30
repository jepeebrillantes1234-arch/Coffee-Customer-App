import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/realtime.dart';
import '../core/animated_add_button.dart';
import '../core/util.dart';
import '../core/widgets.dart';
import '../state/favorites.dart';
import '../state/app_state.dart';
import '../state/nav.dart';
import 'notifications_screen.dart';
import 'product_screen.dart';
import 'promos_screen.dart';
import 'profile_screen.dart';

const _serif = 'serif';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _cats = [];
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _banners = [];
  bool _loading = true;
  bool _bannerLoading = true;
  String? _error;
  String? _bannerError;
  int _unread = 0;
  int _bannerIndex = 0;
  final PageController _bannerController = PageController();
  Timer? _bannerTimer;
  StreamSubscription<Map<String, dynamic>>? _liveSubscription;

  @override
  void initState() {
    super.initState();
    _load();
    _scheduleBannerAdvance();
    Favorites.I.load();
    _loadUnread();
    Realtime.I.connect();
    _liveSubscription = Realtime.I.updates.listen((event) {
      if (event['kind'] == 'notification') _loadUnread();
      if (['product', 'category', 'promo', 'banner'].contains(event['kind'])) {
        _load();
      }
    });
    rootTab.addListener(_onTab);
  }

  @override
  void dispose() {
    rootTab.removeListener(_onTab);
    _bannerTimer?.cancel();
    _bannerController.dispose();
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
      String? bannerError;
      var banners = <Map<String, dynamic>>[];
      var bannersLoaded = false;
      try {
        banners = await Api.I.homeBanners();
        bannersLoaded = true;
      } catch (error) {
        debugPrint('Public home banner request failed: $error');
        bannerError = 'Could not load home banners: $error';
      }

      // Signed-in customers keep the existing audience filtering and payment config.
      // Guests still receive the public banners without calling the protected endpoint.
      if (Api.I.loggedIn) {
        try {
          cfg = await Api.I.appConfig();
          banners = _readBanners(cfg);
          bannersLoaded = true;
        } catch (error) {
          debugPrint('Personalized home config request failed: $error');
        }
      }

      if (banners.isNotEmpty) {
        banners.sort((a, b) {
          final order = (a['sort_order'] as num?)?.toInt() ?? 0;
          final otherOrder = (b['sort_order'] as num?)?.toInt() ?? 0;
          if (order != otherOrder) return order.compareTo(otherOrder);
          return ((b['id'] as num?)?.toInt() ?? 0).compareTo(
            (a['id'] as num?)?.toInt() ?? 0,
          );
        });
        bannerError = null;
        debugPrint('Loaded ${banners.length} home banner(s).');
      } else {
        bannerError = null;
      }
      prods.sort(
        (a, b) => dbl(b['avg_rating']).compareTo(dbl(a['avg_rating'])),
      );
      if (!mounted) return;
      setState(() {
        _cats = cats;
        _products = prods;
        if (bannersLoaded) {
          _banners = banners.take(5).toList(growable: false);
          _bannerIndex = 0;
        }
        _bannerError = bannerError;
        _bannerLoading = false;
        if (cfg != null) {
          AppState.online =
              cfg['payment_mode'] == 'online' ||
              (cfg['settings'] as Map?)?['payment_method'] == 'online';
        }
        _error = null;
        _loading = false;
      });
      if (bannersLoaded && banners.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _bannerController.hasClients) {
            _bannerController.jumpToPage(0);
          }
        });
        _scheduleBannerAdvance();
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
        _bannerLoading = false;
        _bannerError = 'Could not load home banners: ${e.message}';
      });
    } catch (error) {
      debugPrint('Unexpected home loading error: $error');
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load the Home screen. Pull down to retry.';
        _loading = false;
        _bannerLoading = false;
        _bannerError = 'Unexpected error while loading banners: $error';
      });
    }
  }

  List<Map<String, dynamic>> _readBanners(Map<String, dynamic> config) {
    dynamic value = config['banners'] ?? config['home_banners'];
    if (value == null && config['settings'] is Map) {
      final settings = Map<String, dynamic>.from(config['settings'] as Map);
      value = settings['banners'] ?? settings['home_banners'];
    }
    if (value == null && config['data'] is Map) {
      final data = Map<String, dynamic>.from(config['data'] as Map);
      value = data['banners'] ?? data['home_banners'];
    }
    if (value is! List) return [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) {
          final active = item['is_active'];
          return active == null ||
              active == true ||
              active == 1 ||
              active == '1';
        })
        .toList();
  }

  // I-refresh ang home data kapag bumalik sa Home
  void _onTab() {
    if (rootTab.value == 0) {
      if (_bannerController.hasClients && _bannerIndex != 0) {
        _bannerController.jumpToPage(0);
      } else {
        _bannerIndex = 0;
      }
      _scheduleBannerAdvance();
      _load();
    } else {
      _bannerTimer?.cancel();
    }
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

  void _scheduleBannerAdvance() {
    _bannerTimer?.cancel();
    if (_activeBanners.length < 2) return;
    _bannerTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted || !_bannerController.hasClients) return;
      final next = (_bannerIndex + 1) % _activeBanners.length;
      _bannerController.animateToPage(
        next,
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  List<Map<String, dynamic>> get _activeBanners =>
      _banners.take(5).toList(growable: false);

  void _openBannerDestination(Map<String, dynamic> banner) {
    final type = (banner['banner_type'] ?? banner['type'] ?? 'custom')
        .toString()
        .toLowerCase();
    final destination = (banner['destination'] ?? '').toString().toLowerCase();
    final target = destination.isNotEmpty
        ? destination
        : switch (type) {
            'order_now' => 'menu',
            'new_product' => 'product',
            'promo' ||
            'redeem' ||
            'new_promo' ||
            'promo_code' ||
            'special_offer' => 'promos',
            'membership' || 'rewards' => 'profile',
            'announcement' => 'announcement',
            _ => 'menu',
          };

    switch (target) {
      case 'menu':
      case 'order_now':
        _goMenu();
        return;
      case 'promos':
      case 'promo':
      case 'redeem':
      case 'offer':
        Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const PromosScreen()));
        return;
      case 'promo_code':
        final promoId = int.tryParse(
          '${banner['promo_id'] ?? banner['destination_id'] ?? ''}',
        );
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PromosScreen(initialPromoId: promoId),
          ),
        );
        return;
      case 'product':
        final productId = int.tryParse(
          '${banner['destination_id'] ?? banner['product_id'] ?? ''}',
        );
        if (productId != null && productId > 0) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ProductScreen(id: productId),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This product destination is unavailable.'),
            ),
          );
        }
        return;
      case 'announcement':
        _showAnnouncement(banner);
        return;
      case 'profile':
      case 'membership':
      case 'rewards':
        Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const ProfileScreen()));
        return;
      case 'cart':
        rootTab.value = 2;
        return;
      case 'orders':
        rootTab.value = 3;
        return;
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This banner destination is unavailable.'),
          ),
        );
    }
  }

  void _showAnnouncement(Map<String, dynamic> banner) {
    final title = (banner['title'] ?? banner['headline'] ?? 'Announcement')
        .toString();
    final description = (banner['description'] ?? '').toString();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(description.isEmpty ? title : description),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
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
            _categories(),
            _recommended(),
            const SizedBox(height: 24),
          ],
        ),
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
    if (_activeBanners.isEmpty && !_bannerLoading) {
      return const SizedBox.shrink();
    }
    return AspectRatio(
      aspectRatio: 1.5,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_activeBanners.isEmpty)
              Positioned.fill(child: _emptyBannerState())
            else
              PageView.builder(
                controller: _bannerController,
                itemCount: _activeBanners.length,
                onPageChanged: (index) {
                  setState(() => _bannerIndex = index);
                  _scheduleBannerAdvance();
                },
                itemBuilder: (context, index) => _bannerSlide(index),
              ),
            if (_activeBanners.length > 1)
              Positioned(
                left: 0,
                right: 0,
                bottom: 10,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_activeBanners.length, (index) {
                    final selected = index == _bannerIndex;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: selected ? 17 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: selected ? Colors.white : Colors.white70,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    );
                  }),
                ),
              ),
            if (_activeBanners.isNotEmpty &&
                (_bannerLoading || _bannerError != null))
              Positioned(
                left: 12,
                right: 12,
                top: 12,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.62),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _bannerLoading ? null : _load,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_bannerLoading)
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            else
                              const Icon(
                                Icons.refresh_rounded,
                                size: 17,
                                color: Colors.white,
                              ),
                            const SizedBox(width: 8),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 250),
                              child: Text(
                                _bannerLoading
                                    ? 'Loading banners...'
                                    : 'Banners unavailable. Tap to retry.',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _emptyBannerState() {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_bannerLoading)
            const CircularProgressIndicator()
          else
            Icon(
              Icons.image_not_supported_outlined,
              size: 34,
              color: Theme.of(context).colorScheme.primary,
            ),
          const SizedBox(height: 12),
          Text(
            _bannerLoading
                ? 'Loading banners...'
                : _bannerError ?? 'No active banners are available.',
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (!_bannerLoading) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bannerSlide(int index) {
    final banner = _activeBanners[index];
    final type = (banner['banner_type'] ?? banner['type'] ?? 'custom')
        .toString()
        .toLowerCase();
    final title = (banner['title'] ?? '').toString().trim();
    final headline = (banner['headline'] ?? '').toString().trim();
    final description = (banner['description'] ?? banner['subtitle'] ?? '')
        .toString()
        .trim();
    final imageUrl = (banner['image_url'] ?? '').toString().trim();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openBannerDestination(banner),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl.isNotEmpty)
              NetImage(imageUrl, fit: BoxFit.cover)
            else
              ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Color(0xCC160C08),
                    Color(0x66000000),
                    Color(0x00000000),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Text(
                        title.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  Text(
                    headline.isEmpty ? title : headline,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      height: 1.08,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: () => _openBannerDestination(banner),
                    icon: Icon(_bannerIcon(type), size: 17),
                    label: Text(
                      (banner['button_text'] ?? '').toString().trim().isNotEmpty
                          ? banner['button_text'].toString().trim()
                          : title.isEmpty
                          ? 'Explore'
                          : title,
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 9,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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

  IconData _bannerIcon(String type) => switch (type) {
    'order_now' => Icons.coffee_rounded,
    'promo' ||
    'new_promo' ||
    'promo_code' ||
    'special_offer' => Icons.local_offer_rounded,
    'new_product' => Icons.new_releases_rounded,
    'membership' => Icons.card_membership_rounded,
    'redeem' => Icons.redeem_rounded,
    'rewards' => Icons.stars_rounded,
    'announcement' => Icons.campaign_rounded,
    _ => Icons.arrow_forward_rounded,
  };

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
