import 'package:flutter/material.dart';

import '../core/api.dart';
import '../state/nav.dart';
import '../state/promo_state.dart';
import 'product_screen.dart';
import 'promo_carousel.dart';

class PromosScreen extends StatefulWidget {
  const PromosScreen({super.key});

  @override
  State<PromosScreen> createState() => _PromosScreenState();
}

class _PromosScreenState extends State<PromosScreen> {
  List<Map<String, dynamic>> _promos = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final promos = await Api.I.promos();
      if (!mounted) return;
      setState(() {
        _promos = promos;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load promos. Please try again.';
        _loading = false;
      });
    }
  }

  Future<void> _choosePromo(Map<String, dynamic> promo) async {
    if (promo['used'] == true) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'You have already used this promo. Each customer may use it once.',
          ),
        ),
      );
      return;
    }

    final product = promo['product'];
    final productId = product is Map && product['id'] is num
        ? (product['id'] as num).toInt()
        : null;

    // Check that the linked product still exists and is available before
    // selecting the promo or opening its product page.
    if (productId != null) {
      try {
        await Api.I.product(productId);
      } on ApiException {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'The product linked to this promo is currently unavailable. Please choose another promo.',
              ),
            ),
          );
        return;
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'Unable to open this promo item. Please try again or choose another promo.',
              ),
            ),
          );
        return;
      }
    }
    if (!mounted) return;

    final alreadySelected = SelectedPromo.I.code == promo['code'];
    SelectedPromo.I.select(promo);
    final needed = promo['type'] == 'bogo'
        ? ((promo['buy_qty'] as num?)?.toInt() ?? 1) +
              ((promo['free_qty'] as num?)?.toInt() ?? 1)
        : 0;

    // Isang alert lang, at sa unang pindot lang
    if (!alreadySelected) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Promo selected!'),
          content: Text(
            '${promo['headline'] ?? promo['title'] ?? promo['code']}\n'
            'Code: ${promo['code'] ?? ''} (it will be added at checkout)\n'
            '${product is Map ? 'For: ${product['name']}${needed > 0 ? ' • $needed items required' : ' • 1 item only'}\n' : ''}'
            'This promo can be used once.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
    }
    if (!mounted) return;

    final navigator = Navigator.of(context);
    navigator.pop();
    if (productId != null) {
      navigator.push(
        MaterialPageRoute<void>(builder: (_) => ProductScreen(id: productId)),
      );
    } else {
      rootTab.value = 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Promos'),
        actions: [
          IconButton(
            tooltip: 'Refresh promos',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(onRefresh: _load, child: _body()),
    );
  }

  Widget _body() {
    const scroll = AlwaysScrollableScrollPhysics();

    if (_loading) {
      return ListView(
        physics: scroll,
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        children: [
          const Center(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: CircularProgressIndicator(),
            ),
          ),
          for (var i = 0; i < 3; i++)
            Container(
              height: 170,
              margin: const EdgeInsets.only(top: 14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(18),
              ),
            ),
        ],
      );
    }

    if (_error != null) {
      return ListView(
        physics: scroll,
        children: [
          const SizedBox(height: 120),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_error!, textAlign: TextAlign.center),
            ),
          ),
          Center(
            child: TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ),
        ],
      );
    }

    if (_promos.isEmpty) {
      return ListView(
        physics: scroll,
        children: [
          SizedBox(height: 130),
          Icon(
            Icons.local_offer_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          SizedBox(height: 14),
          Center(child: Text('No promos available right now.')),
        ],
      );
    }

    return ListView.separated(
      physics: scroll,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      itemCount: _promos.length,
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (_, index) {
        final promo = _promos[index];
        return PromoBannerCard(
          promo: promo,
          aspectRatio: 2,
          onTap: () => _choosePromo(promo),
        );
      },
    );
  }
}
