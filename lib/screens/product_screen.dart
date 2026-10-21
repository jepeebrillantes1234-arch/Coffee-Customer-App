import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../core/util.dart';
import '../core/widgets.dart';
import '../state/cart.dart';
import '../state/promo_state.dart';

class ProductScreen extends StatefulWidget {
  final int id;
  final int? cartIndex;
  const ProductScreen({super.key, required this.id, this.cartIndex});

  @override
  State<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends State<ProductScreen> {
  Map<String, dynamic>? _p;
  bool _loading = true;
  String? _error;
  final Map<int, Set<int>> _sel = {}; // group_id -> option_ids
  int _qty = 1;
  Map<String, dynamic>? _reviews;
  final _notes = TextEditingController();

  List<Map<String, dynamic>> get _groups =>
      _p == null ? [] : mapList(_p!['option_groups'] ?? []);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await Api.I.product(widget.id);
      if (!mounted) return;
      Api.I
          .productReviews(widget.id)
          .then((r) {
            if (mounted) setState(() => _reviews = r);
          })
          .catchError((_) {});
      final existing =
          widget.cartIndex != null && widget.cartIndex! < Cart.I.lines.length
          ? Cart.I.lines[widget.cartIndex!]
          : null;
      setState(() {
        _p = p;
        _loading = false;
        if (existing != null) {
          _qty = existing.qty;
          _notes.text = existing.notes ?? '';
        } else if (SelectedPromo.I.isBogo &&
            SelectedPromo.I.productId == (p['id'] as num).toInt()) {
          _qty = SelectedPromo.I.bogoNeed;
        }
        for (final g in _groups) {
          final opts = mapList(g['options'] ?? []);
          final selected = _sel[g['id'] as int] = <int>{};
          if (existing != null) {
            selected.addAll(
              opts
                  .where(
                    (o) =>
                        existing.optionIds.contains((o['id'] as num).toInt()),
                  )
                  .map((o) => (o['id'] as num).toInt()),
            );
          } else if (g['is_required'] == true &&
              g['is_multiple'] != true &&
              opts.isNotEmpty) {
            selected.add((opts.first['id'] as num).toInt());
          }
        }
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _chosen {
    final out = <Map<String, dynamic>>[];
    for (final g in _groups) {
      for (final o in mapList(g['options'] ?? [])) {
        if (_sel[g['id'] as int]?.contains(o['id'] as int) == true) out.add(o);
      }
    }
    return out;
  }

  double get _unit =>
      dbl(_p?['sale_price'] ?? _p?['base_price']) +
      _chosen.fold(0.0, (s, o) => s + dbl(o['extra_price']));

  void _toggle(Map<String, dynamic> g, Map<String, dynamic> o) {
    final gid = g['id'] as int;
    final oid = o['id'] as int;
    final set = _sel[gid] ?? <int>{};
    setState(() {
      if (g['is_multiple'] == true) {
        if (set.contains(oid)) {
          set.remove(oid);
        } else if (set.length < (g['max_select'] as int)) {
          set.add(oid);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'You can select up to ${g['max_select']} for ${g['name']}.',
              ),
            ),
          );
        }
      } else {
        set
          ..clear()
          ..add(oid);
      }
      _sel[gid] = set;
    });
  }

  void _add() {
    for (final g in _groups) {
      if (g['is_required'] == true && (_sel[g['id'] as int] ?? {}).isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Please select ${g['name']}.')));
        return;
      }
    }
    final chosen = _chosen;
    final line = CartLine(
      productId: (_p!['id'] as num).toInt(),
      name: '${_p!['name']}',
      imageUrl: _p!['image_url']?.toString(),
      unitPrice: _unit,
      optionIds: chosen.map((o) => (o['id'] as num).toInt()).toList(),
      optionNames: chosen.map((o) => '${o['name']}').toList(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      qty: _qty,
    );
    if (widget.cartIndex != null && widget.cartIndex! < Cart.I.lines.length) {
      Cart.I.update(widget.cartIndex!, line);
    } else {
      Cart.I.add(line);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.cartIndex == null ? 'Added to cart' : 'Coffee updated',
        ),
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: Icon(Icons.arrow_back_rounded, color: Theme.of(context).colorScheme.primary, size: 28),
        ),
        titleSpacing: 0,
        title: Text(
          p == null ? 'Order' : '${p['name']}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontFamily: 'serif',
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Icon(Icons.coffee_outlined, color: caramel, size: 30),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : p == null
          ? Center(child: Text(_error ?? 'Something went wrong.'))
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: SizedBox(
                          height: 245,
                          width: double.infinity,
                          child: NetImage(p['image_url']?.toString()),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        '${p['name']}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontFamily: 'serif',
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${p['description'] ?? 'Choose your options and make it your own.'}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        peso(dbl(p['sale_price'] ?? p['base_price'])),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _promoTag(p),
                      for (final g in _groups) _group(g),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Theme.of(context).dividerColor),
                        ),
                        child: TextField(
                          controller: _notes,
                          minLines: 2,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: 'Note (optional)',
                            hintText:
                                'e.g. Less sugar, extra ice, no whipped cream',
                            border: InputBorder.none,
                            icon: Icon(
                              Icons.edit_note_rounded,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                      if (_reviews != null) _reviewsBox(),
                    ],
                  ),
                ),
                SafeArea(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x12000000),
                          blurRadius: 16,
                          offset: Offset(0, -4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(32),
                            border: Border.all(color: Theme.of(context).dividerColor),
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: _qty > 1
                                    ? () => setState(() => _qty--)
                                    : null,
                                icon: Icon(
                                  Icons.remove_rounded,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              Text(
                                '$_qty',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: () => setState(() => _qty++),
                                icon: Icon(
                                  Icons.add_rounded,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(56),
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(32),
                              ),
                            ),
                            onPressed: _add,
                            child: Text(
                              '${widget.cartIndex == null ? 'Add to cart' : 'Save changes'} · ${peso(_unit * _qty)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _promoTag(Map<String, dynamic> p) {
    return ListenableBuilder(
      listenable: SelectedPromo.I,
      builder: (_, _) {
        final sp = SelectedPromo.I.promo;
        if (sp == null) return const SizedBox.shrink();
        final pid = SelectedPromo.I.productId;
        if (pid != null && pid != (p['id'] as num).toInt()) {
          return const SizedBox.shrink();
        }

        final text = pid == null
            ? 'Promo ${sp['code']} will be applied automatically at checkout.'
            : SelectedPromo.I.isBogo
            ? '${sp['headline'] ?? sp['code']}: ${SelectedPromo.I.bogoNeed} items are selected. The discount will be applied at checkout.'
            : '${sp['headline'] ?? sp['code']} is available for this item (one item only). Applied automatically at checkout.';
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: success.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: success.withValues(alpha: 0.4)),
          ),
          child: Text(text, style: const TextStyle(fontSize: 12.5)),
        );
      },
    );
  }

  Widget _reviewsBox() {
    final r = _reviews!;
    final items = mapList(r['items'] ?? []);
    final count = (r['count'] as num?)?.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            count == 0
                ? 'Reviews'
                : 'Reviews · ★ ${dbl(r['avg']).toStringAsFixed(1)} ($count)',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 6),
          if (items.isEmpty)
            Text(
              'No reviews yet.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          for (final it in items)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${it['name']}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '★' * (it['rating'] as int),
                          style: const TextStyle(color: Colors.amber),
                        ),
                        const Spacer(),
                        Text(
                          '${it['date']}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    if ((it['comment'] ?? '').toString().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('${it['comment']}'),
                      ),
                    if ((it['reply'] ?? '').toString().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '☕ Shop: ${it['reply']}',
                          style: const TextStyle(fontSize: 12, color: caramel),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _group(Map<String, dynamic> g) {
    final opts = mapList(g['options'] ?? []);
    final name = '${g['name']}';
    final icon = name.toLowerCase().contains('sugar')
        ? Icons.grain_rounded
        : name.toLowerCase().contains('milk')
        ? Icons.local_drink_outlined
        : Icons.coffee_outlined;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).colorScheme.surfaceContainerLow
            : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 21),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  g['is_required'] == true ? 'Required' : 'Optional',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: g['is_required'] == true ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final option in opts) _optionChip(g, option)],
          ),
        ],
      ),
    );
  }

  Widget _optionChip(Map<String, dynamic> group, Map<String, dynamic> option) {
    final selected =
        _sel[group['id'] as int]?.contains(option['id'] as int) == true;
    final extra = dbl(option['extra_price']);
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => _toggle(group, option),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor,
          ),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x1F512D1C),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Icon(Icons.check_rounded, color: Theme.of(context).colorScheme.onPrimary, size: 17),
              const SizedBox(width: 5),
            ],
            Text(
              '${option['name']}',
              style: TextStyle(
                color: selected ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (extra > 0) ...[
              const SizedBox(width: 7),
              Text(
                '+${peso(extra)}',
                style: TextStyle(
                  color: selected ? Colors.white : caramel,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
