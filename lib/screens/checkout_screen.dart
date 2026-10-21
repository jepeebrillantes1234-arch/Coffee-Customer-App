import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../core/util.dart';
import '../state/cart.dart';
import '../state/promo_state.dart';
import '../state/app_state.dart';
import 'order_detail_screen.dart';
import 'addresses_screen.dart';
import 'payment_screen.dart';
import 'root_screen.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  String _type = 'delivery';
  String _paymentMethod = 'cod';
  LatLng? _pin;
  final _address = TextEditingController();
  final _locationName = TextEditingController();
  final _notes = TextEditingController();
  final _promo = TextEditingController();

  Map<String, dynamic>? _quote;
  String? _error;
  bool _quoting = false;
  bool _placing = false;
  int _quoteSeq = 0;


  @override
  void initState() {
    super.initState();
    if (AppState.online) _paymentMethod = 'qrph';
    _promo.text = SelectedPromo.I.code ?? ''; // Automatic code from Home
    _refresh();
  }

  @override
  void dispose() {
    _address.dispose();
    _locationName.dispose();
    _notes.dispose();
    _promo.dispose();
    super.dispose();
  }

  Map<String, dynamic> _payload({bool forOrder = false}) => {
    'order_type': _type,
    if (forOrder) 'payment_method': _paymentMethod,
    'items': Cart.I.lines.map((l) => l.toPayload()).toList(),
    'home_promos': Cart.I.bundles.map((bundle) => bundle.toPayload()).toList(),
    if (_promo.text.trim().isNotEmpty) 'promo_code': _promo.text.trim(),
    if (_type == 'delivery' && _pin != null) 'delivery_lat': _pin!.latitude,
    if (_type == 'delivery' && _pin != null) 'delivery_lng': _pin!.longitude,
    if (_type == 'delivery' && _pin != null) ...{
      'delivery_address': _address.text.trim().isEmpty
          ? 'GPS ${_pin!.latitude.toStringAsFixed(6)}, ${_pin!.longitude.toStringAsFixed(6)}'
          : _address.text.trim(),
      'address': _address.text.trim().isEmpty
          ? 'GPS ${_pin!.latitude.toStringAsFixed(6)}, ${_pin!.longitude.toStringAsFixed(6)}'
          : _address.text.trim(),
    },
    if (forOrder && _notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
  };

  Future<void> _refresh() async {
    if (_type == 'delivery' && _pin == null) {
      setState(() {
        _quote = null;
        _error = null;
      });
      return;
    }
    final seq = ++_quoteSeq;
    setState(() => _quoting = true);
    try {
      final q = await Api.I.preview(_payload());
      if (!mounted || seq != _quoteSeq) return;
      setState(() {
        _quote = q;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted || seq != _quoteSeq) return;
      setState(() {
        _quote = null;
        _error = e.message;
      });
    } finally {
      if (mounted && seq == _quoteSeq) setState(() => _quoting = false);
    }
  }

  Future<void> _selectDeliveryAddress() async {
    final selected = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => const AddressesScreen(selectionMode: true),
      ),
    );
    if (!mounted || selected == null) return;
    final latitude = double.tryParse('${selected['latitude']}');
    final longitude = double.tryParse('${selected['longitude']}');
    if (latitude == null || longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This saved address has no valid map pin. Edit it and choose its location.')),
      );
      return;
    }
    setState(() {
      _pin = LatLng(latitude, longitude);
      _address.text = '${selected['full_address'] ?? ''}';
      _locationName.text = '${selected['label'] ?? ''}';
      _error = null;
    });
    await _refresh();
  }

  Future<void> _place() async {
    setState(() => _placing = true);
    final nav = Navigator.of(context);
    try {
      final payload = _payload(forOrder: true);
      final order = await Api.I.placeOrder(payload);

      Cart.I.clear();
      SelectedPromo.I.clear();
      rootTab.value = 3;
      nav.popUntil((r) => r.isFirst);
      nav.push(
        MaterialPageRoute(
          builder: (_) => order['status'] == 'awaiting_payment'
              ? PaymentScreen(order: order)
              : OrderDetailScreen(id: order['id'] as int),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  bool get _canPlace =>
      _quote != null &&
      !_quoting &&
      !_placing &&
      (_type == 'pickup' || (_pin != null && _address.text.trim().isNotEmpty));

  Widget _sectionCard({required Widget child}) => Container(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Theme.of(context).dividerColor),
    ),
    child: child,
  );

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Text(
      title,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final quote = _quote;
    final items = quote?['items'] is List
        ? (quote!['items'] as List)
        : const [];
    final address = _address.text.trim();
    final displayedSubtotal = quote == null
        ? Cart.I.subtotal
        : dbl(quote['subtotal']);
    final displayedTotal = quote == null ? null : dbl(quote['total']);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Checkout',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'delivery',
                      label: Text('Delivery'),
                      icon: Icon(Icons.delivery_dining_rounded),
                    ),
                    ButtonSegment(
                      value: 'pickup',
                      label: Text('Pickup'),
                      icon: Icon(Icons.storefront_rounded),
                    ),
                  ],
                  selected: {_type},
                  onSelectionChanged: (selection) {
                    setState(() {
                      _type = selection.first;
                      if (_type == 'pickup' && _paymentMethod == 'cod') {
                        _paymentMethod = 'cash';
                      } else if (_type == 'delivery' &&
                          _paymentMethod == 'cash') {
                        _paymentMethod = 'cod';
                      }
                    });
                    _refresh();
                  },
                ),
                const SizedBox(height: 20),
                if (_type == 'delivery') ...[
                  _sectionTitle('Delivery Address'),
                  _sectionCard(
                    child: ListTile(
                      onTap: _selectDeliveryAddress,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 4,
                      ),
                      leading: Icon(
                        Icons.location_on_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      title: Text(
                        address.isEmpty
                            ? 'Choose a delivery address'
                            : (_locationName.text.trim().isEmpty
                                  ? address
                                  : _locationName.text.trim()),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        _pin == null
                            ? 'Required for delivery'
                            : '${address.isEmpty ? '' : '$address\n'}${_pin!.latitude.toStringAsFixed(5)}, ${_pin!.longitude.toStringAsFixed(5)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                    ),
                  ),
                  const SizedBox(height: 17),
                ],
                _sectionTitle('Payment Method'),
                _sectionCard(
                  child: Column(
                    children: [
                      ListTile(
                        dense: true,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        selected: _paymentMethod != 'qrph',
                        selectedTileColor: Theme.of(context).colorScheme.primary
                            .withValues(alpha: .06),
                        onTap: () => setState(
                          () => _paymentMethod = _type == 'delivery'
                              ? 'cod'
                              : 'cash',
                        ),
                        leading: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primaryContainer,
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Icon(
                            _type == 'delivery'
                                ? Icons.local_shipping_rounded
                                : Icons.storefront_rounded,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                            size: 23,
                          ),
                        ),
                        title: Text(
                          _type == 'delivery'
                              ? 'Cash on Delivery'
                              : 'Cash at Pickup',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          _type == 'delivery'
                              ? 'Pay the rider when your order arrives.'
                              : 'Pay at the shop counter.',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: Icon(
                          _paymentMethod == 'qrph'
                              ? Icons.radio_button_unchecked
                              : Icons.radio_button_checked,
                          color: _paymentMethod == 'qrph'
                              ? Theme.of(context).colorScheme.onSurfaceVariant
                              : espresso,
                          size: 19,
                        ),
                      ),
                      const Divider(height: 1, indent: 54),
                      ListTile(
                        dense: true,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        selected: _paymentMethod == 'qrph',
                        selectedTileColor: Theme.of(context).colorScheme.primary
                            .withValues(alpha: .06),
                        enabled: AppState.online,
                        onTap: AppState.online
                            ? () => setState(() => _paymentMethod = 'qrph')
                            : null,
                        leading: Container(
                          width: 42,
                          height: 42,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Theme.of(context).dividerColor,
                            ),
                          ),
                          child: Image.asset(
                            'assets/images/qrph.png',
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) => Icon(
                              Icons.qr_code_2_rounded,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                        title: Text(
                          'QRPh',
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                        subtitle: Text(
                          AppState.online
                              ? 'Scan and pay with any QRPh-enabled wallet or banking app.'
                              : 'Unavailable until the shop configures online payment.',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: AppState.online && _paymentMethod == 'qrph'
                            ? Icon(
                                Icons.radio_button_checked,
                                color: Theme.of(context).colorScheme.primary,
                                size: 19,
                              )
                            : AppState.online
                            ? Icon(
                                Icons.radio_button_unchecked,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                size: 19,
                              )
                            : Icon(
                                Icons.lock_outline,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                size: 18,
                              ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 17),
                _sectionTitle('Order Summary'),
                _sectionCard(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        if (_quoting)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: LinearProgressIndicator(minHeight: 2),
                          ),
                        if (quote == null && !_quoting)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(
                              _error ??
                                  (_type == 'delivery'
                                      ? 'Select a delivery address to calculate the total.'
                                      : 'Unable to calculate the order total.'),
                              style: TextStyle(
                                fontSize: 12,
                                color: _error == null
                                    ? Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant
                                    : Colors.red,
                              ),
                            ),
                          ),
                        for (final item in items)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${item['qty']} × ${item['name']}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                Text(
                                  peso(dbl(item['line_total'])),
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        if (items.isNotEmpty) const Divider(height: 18),
                        _row('Subtotal', peso(displayedSubtotal)),
                        if (quote != null && dbl(quote['discount']) > 0)
                          _row(
                            'Discount${quote['discount_label'] == null ? '' : ' (${quote['discount_label']})'}',
                            '-${peso(dbl(quote['discount']))}',
                            color: success,
                          ),
                        if (_type == 'delivery')
                          _row(
                            'Delivery Fee',
                            quote == null
                                ? 'Calculated after address'
                                : peso(dbl(quote['delivery_fee'])),
                          ),
                        const Divider(height: 20),
                        _row(
                          'Total',
                          displayedTotal == null
                              ? 'Calculated at checkout'
                              : peso(displayedTotal),
                          bold: true,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 12),
                  title: const Text(
                    'Add a note or promo code',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  children: [
                    TextField(
                      controller: _notes,
                      decoration: const InputDecoration(
                        labelText: 'Order note (optional)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.edit_note_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _promo,
                            textCapitalization: TextCapitalization.characters,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: 'Promo code',
                              border: const OutlineInputBorder(),
                              suffixIcon: _promo.text.isEmpty
                                  ? null
                                  : IconButton(
                                      icon: const Icon(Icons.close),
                                      onPressed: () {
                                        _promo.clear();
                                        SelectedPromo.I.clear();
                                        setState(() {});
                                        _refresh();
                                      },
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 9),
                        OutlinedButton(
                          onPressed: _quoting ? null : _refresh,
                          child: const Text('Apply'),
                        ),
                      ],
                    ),
                  ],
                ),
                if (_error != null && quote != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: _canPlace ? _place : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _placing
                      ? const SizedBox(
                          width: 21,
                          height: 21,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          AppState.online
                              ? (quote == null
                                    ? 'Continue to Payment'
                                    : 'Continue to Payment · ${peso(dbl(quote['total']))}')
                              : (quote == null
                                    ? 'Place Order'
                                    : 'Place Order · ${peso(dbl(quote['total']))}'),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String l, String v, {bool bold = false, Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          l,
          style: TextStyle(
            fontWeight: bold ? FontWeight.w700 : null,
            fontSize: bold ? 17 : null,
            color: color,
          ),
        ),
        Text(
          v,
          style: TextStyle(
            fontWeight: bold ? FontWeight.w700 : null,
            fontSize: bold ? 17 : null,
            color: color ?? (bold ? caramel : null),
          ),
        ),
      ],
    ),
  );
}
