import 'package:flutter/foundation.dart';

class CartLine {
  final int productId;
  final String name;
  final String? imageUrl;
  final double unitPrice;
  final List<int> optionIds;
  final List<String> optionNames;
  final String? notes;
  int qty;

  CartLine({
    required this.productId,
    required this.name,
    required this.imageUrl,
    required this.unitPrice,
    required this.optionIds,
    required this.optionNames,
    this.notes,
    this.qty = 1,
  });

  double get total => unitPrice * qty;

  String get key =>
      '$productId|${([...optionIds]..sort()).join(',')}|${notes ?? ''}';

  Map<String, dynamic> toPayload() => {
    'product_id': productId,
    'quantity': qty,
    'option_ids': optionIds,
    if (notes != null && notes!.isNotEmpty) 'notes': notes,
  };
}

class CartBundleLine {
  final int promoId;
  final String name;
  final String? imageUrl;
  final double price;
  final double originalTotal;
  final List<String> products;
  int qty;
  CartBundleLine({required this.promoId, required this.name, required this.imageUrl, required this.price, required this.originalTotal, required this.products, this.qty=1});
  double get total => price * qty;
  Map<String, dynamic> toPayload() => {'home_promo_id': promoId, 'quantity': qty};
}

class Cart extends ChangeNotifier {
  Cart._();
  static final Cart I = Cart._();

  final List<CartLine> lines = [];
  final List<CartBundleLine> bundles = [];

  int get count => lines.fold(0, (s, l) => s + l.qty) + bundles.fold(0, (s, l) => s + l.qty);
  double get subtotal => lines.fold(0.0, (s, l) => s + l.total) + bundles.fold(0.0, (s, l) => s + l.total);

  void addBundle(Map<String, dynamic> promo) {
    final id = (promo['id'] as num).toInt();
    final index = bundles.indexWhere((line) => line.promoId == id);
    if (index >= 0) { bundles[index].qty++; } else {
      final products = promo['products'] is List ? (promo['products'] as List).map((p) => '${(p as Map)['name']} × ${(p)['quantity']}').toList() : <String>[];
      bundles.add(CartBundleLine(promoId:id,name:'${promo['name']}',imageUrl:promo['image_url']?.toString(),price:(promo['price'] as num).toDouble(),originalTotal:(promo['original_total'] as num?)?.toDouble() ?? 0,products:products));
    }
    notifyListeners();
  }
  void setBundleQty(int index, int qty) { if(qty<=0) bundles.removeAt(index); else bundles[index].qty=qty; notifyListeners(); }

  void add(CartLine line) {
    final i = lines.indexWhere((l) => l.key == line.key);
    if (i >= 0) {
      lines[i].qty += line.qty;
    } else {
      lines.add(line);
    }
    notifyListeners();
  }

  void update(int index, CartLine line) {
    if (index < 0 || index >= lines.length) return;
    final duplicate = lines.indexWhere(
      (item) => item != lines[index] && item.key == line.key,
    );
    if (duplicate >= 0) {
      lines[duplicate].qty += line.qty;
      lines.removeAt(index);
    } else {
      lines[index] = line;
    }
    notifyListeners();
  }

  void setQty(int index, int qty) {
    if (qty <= 0) {
      lines.removeAt(index);
    } else {
      lines[index].qty = qty;
    }
    notifyListeners();
  }

  void clear() {
    lines.clear(); bundles.clear();
    notifyListeners();
  }
}
