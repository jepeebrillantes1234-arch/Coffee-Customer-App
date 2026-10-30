import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/util.dart';
import '../core/widgets.dart';
import '../state/cart.dart';
import '../state/promo_state.dart';
import 'checkout_screen.dart';
import 'product_screen.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Cart')),
      body: ListenableBuilder(
        listenable: Cart.I,
        builder: (_, _) {
          final lines = Cart.I.lines;
          final bundles = Cart.I.bundles;
          if (lines.isEmpty && bundles.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.shopping_bag_outlined,
                    size: 54,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Your cart is empty.',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Browse the menu and add your favorites.',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              const _PromoNote(),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  itemCount: lines.length + bundles.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 20, indent: 58),
                  itemBuilder: (context, index) {
                    if (index >= lines.length) {
                      final bundleIndex = index - lines.length;
                      final bundle = bundles[bundleIndex];
                      return Row(children: [
                        ClipRRect(borderRadius: BorderRadius.circular(10), child: NetImage(bundle.imageUrl, width: 58, height: 64)),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${bundle.name} · Bundle', style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text(bundle.products.join(', '), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          const SizedBox(height: 4), Text(peso(bundle.price), style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            _qtyButton(context, Icons.remove, () => Cart.I.setBundleQty(bundleIndex, bundle.qty - 1)),
                            Text('${bundle.qty}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                            _qtyButton(context, Icons.add, () => Cart.I.setBundleQty(bundleIndex, bundle.qty + 1)),
                          ]),
                        ])),
                        IconButton(tooltip: 'Remove bundle', onPressed: () => Cart.I.setBundleQty(bundleIndex, 0), icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error)),
                      ]);
                    }
                    final line = lines[index];
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: NetImage(line.imageUrl, width: 58, height: 64),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                line.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                peso(line.unitPrice),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              if (line.optionNames.isNotEmpty)
                                Text(
                                  line.optionNames.join(', '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              if (line.notes != null &&
                                  line.notes!.trim().isNotEmpty)
                                Text(
                                  'Note: ${line.notes}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              const SizedBox(height: 7),
                              Container(
                                height: 32,
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Theme.of(context).dividerColor,
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _qtyButton(
                                      context,
                                      Icons.remove,
                                      () => Cart.I.setQty(index, line.qty - 1),
                                    ),
                                    SizedBox(
                                      width: 24,
                                      child: Text(
                                        '${line.qty}',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    _qtyButton(
                                      context,
                                      Icons.add,
                                      () => Cart.I.setQty(index, line.qty + 1),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              tooltip: 'Customize item',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ProductScreen(
                                    id: line.productId,
                                    cartIndex: index,
                                  ),
                                ),
                              ),
                              icon: Icon(
                                Icons.tune_rounded,
                                size: 17,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Remove item',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => Cart.I.setQty(index, 0),
                              icon: Icon(
                                Icons.delete_outline_rounded,
                                size: 19,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 13, 18, 14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _summaryRow(context, 'Subtotal', peso(Cart.I.subtotal)),
                      const SizedBox(height: 7),
                      _summaryRow(
                        context,
                        'Delivery Fee',
                        'Calculated at checkout',
                        muted: true,
                      ),
                      const Divider(height: 20),
                      _summaryRow(context, 'Total', peso(Cart.I.subtotal), bold: true),
                      const SizedBox(height: 13),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const CheckoutScreen(),
                            ),
                          ),
                          child: const Text(
                            'Proceed to Checkout',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static Widget _qtyButton(BuildContext context, IconData icon, VoidCallback onPressed) => SizedBox(
    width: 32,
    height: 30,
    child: IconButton(
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
      icon: Icon(icon, size: 15, color: Theme.of(context).colorScheme.primary),
    ),
  );

  static Widget _summaryRow(
    BuildContext context,
    String label,
    String value, {
    bool bold = false,
    bool muted = false,
  }) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: bold ? 18 : 14,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
          color: muted ? Theme.of(context).colorScheme.onSurfaceVariant : Theme.of(context).colorScheme.onSurface,
        ),
      ),
      Text(
        value,
        style: TextStyle(
          fontSize: bold ? 18 : 14,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
          color: muted ? Theme.of(context).colorScheme.onSurfaceVariant : Theme.of(context).colorScheme.onSurface,
        ),
      ),
    ],
  );
}

class _PromoNote extends StatelessWidget {
  const _PromoNote();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SelectedPromo.I,
      builder: (_, _) {
        final promo = SelectedPromo.I.promo;
        if (promo == null) return const SizedBox.shrink();
        final product = promo['product'] is Map
            ? (promo['product'] as Map)['name']
            : null;
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          decoration: BoxDecoration(
            color: success.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: success.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              const Icon(Icons.local_offer_outlined, color: success, size: 19),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Promo ${promo['code']} will be applied at checkout${product != null ? ' for $product' : ''}.',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 18),
                onPressed: SelectedPromo.I.clear,
              ),
            ],
          ),
        );
      },
    );
  }
}
