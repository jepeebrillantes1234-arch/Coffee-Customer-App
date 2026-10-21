import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/animated_add_button.dart';
import '../core/util.dart';
import '../core/widgets.dart';
import '../state/favorites.dart';
import '../state/nav.dart';
import 'product_screen.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  List<Map<String, dynamic>> _cats = [];
  List<Map<String, dynamic>> _products = [];
  int? _cat;
  final _search = TextEditingController();
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
    Favorites.I.load();
    menuRequest.addListener(_onRequest);
  }

  // Galing sa Home: pumili ng category o nag-search
  void _onRequest() {
    final r = menuRequest.value;
    if (r == null) return;
    menuRequest.value = null;
    setState(() => _cat = r['category'] as int?);
    _search.text = (r['search'] ?? '').toString();
    _loadProducts();
  }

  @override
  void dispose() {
    menuRequest.removeListener(_onRequest);
    _search.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final c = await Api.I.categories();
      if (mounted) {
        setState(() {
          _cats = c;
          if (_cat == null && c.isNotEmpty)
            _cat = (c.first['id'] as num).toInt();
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    await _loadProducts();
  }

  Future<void> _loadProducts() async {
    if (mounted) setState(() => _loading = true);
    try {
      final p = await Api.I.products(
        categoryId: _cat,
        search: _search.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _products = p;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: Text(
          'Menu',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        leading: IconButton(
          tooltip: 'Back to home',
          onPressed: () => rootTab.value = 0,
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 20,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              children: [
                for (final category in _cats)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('${category['name']}'),
                      selected: _cat == category['id'],
                      onSelected: (_) {
                        setState(() => _cat = (category['id'] as num).toInt());
                        _loadProducts();
                      },
                      showCheckmark: false,
                      labelStyle: TextStyle(
                        color: _cat == category['id']
                            ? Colors.white
                            : Theme.of(context).colorScheme.onSurface,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      selectedColor: Theme.of(context).colorScheme.primary,
                      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      shape: const StadiumBorder(),
                      side: BorderSide.none,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 4,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _loadProducts,
                    child: _products.isEmpty
                        ? ListView(
                            children: const [
                              SizedBox(height: 120),
                              Center(child: Text('No products found.')),
                            ],
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
                            itemCount: _products.length,
                            separatorBuilder: (_, _) => Divider(
                              height: 1,
                              indent: 84,
                              color: Theme.of(context).dividerColor,
                            ),
                            itemBuilder: (_, index) =>
                                _menuRow(_products[index]),
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _menuRow(Map<String, dynamic> product) {
    final description = (product['description'] ?? '').toString().trim();
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProductScreen(id: (product['id'] as num).toInt()),
        ),
      ),
      child: SizedBox(
        height: 92,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 68,
                height: 68,
                child: NetImage(product['image_url']?.toString()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${product['name']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  if (description.isNotEmpty)
                    Text(
                      description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(height: 5),
                  Text(
                    peso(dbl(product['base_price'])),
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AnimatedAddButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      ProductScreen(id: (product['id'] as num).toInt()),
                ),
              ),
              size: 29,
            ),
          ],
        ),
      ),
    );
  }
}

/// Ginagamit din sa Favorites screen
Widget productCard(BuildContext context, Map<String, dynamic> p) {
  return InkWell(
    borderRadius: BorderRadius.circular(24),
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProductScreen(id: p['id'] as int)),
    ),
    child: Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).dividerColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D392517),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                NetImage(p['image_url']?.toString()),
                Positioned(
                  top: 10,
                  right: 10,
                  child: ListenableBuilder(
                    listenable: Favorites.I,
                    builder: (_, _) {
                      final fav = Favorites.I.has(p['id'] as int);
                      return Material(
                        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.94),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => Favorites.I.toggle(p),
                          child: SizedBox(
                            width: 42,
                            height: 42,
                            child: Icon(
                              fav
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              size: 23,
                              color: fav ? const Color(0xFFE76565) : Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${p['name']}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontFamily: 'serif',
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    height: 1.08,
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Icon(
                      Icons.eco_rounded,
                      size: 14,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Container(
                        height: 1.5,
                        color: Theme.of(context).dividerColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  peso(dbl(p['base_price'])),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
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
