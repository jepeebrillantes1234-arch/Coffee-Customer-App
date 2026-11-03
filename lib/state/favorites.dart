import 'package:flutter/foundation.dart';

import '../core/api.dart';

class Favorites extends ChangeNotifier {
  Favorites._();
  static final Favorites I = Favorites._();

  final Set<int> ids = {};
  List<Map<String, dynamic>> items = [];
  final Set<int> _pendingIds = {};
  bool _loading = false;
  int _revision = 0;
  String? lastError;

  bool has(int id) => ids.contains(id);
  bool isPending(int id) => _pendingIds.contains(id);
  bool get isLoading => _loading;

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    final requestRevision = _revision;
    try {
      final loadedItems = await Api.I.favorites();
      if (requestRevision != _revision) return;
      final uniqueItems = <int, Map<String, dynamic>>{};
      for (final product in loadedItems) {
        final id = _idOf(product['id']);
        if (id != null) uniqueItems[id] = product;
      }
      // Do not let an older in-flight GET overwrite an optimistic toggle.
      for (final id in _pendingIds) {
        final currentItem = items.where((p) => _idOf(p['id']) == id);
        if (ids.contains(id)) {
          if (currentItem.isNotEmpty) uniqueItems[id] = currentItem.first;
        } else {
          uniqueItems.remove(id);
        }
      }
      items = uniqueItems.values.toList(growable: true);
      ids
        ..clear()
        ..addAll(uniqueItems.keys);
      lastError = null;
      notifyListeners();
    } catch (_) {
      lastError = 'Could not load your favorites. Please try again.';
      notifyListeners();
    } finally {
      _loading = false;
    }
  }

  Future<bool> toggle(Map<String, dynamic> product) async {
    final id = _idOf(product['id']);
    if (id == null || _pendingIds.contains(id)) return false;

    final had = ids.contains(id);
    final previousItemIndex = items.indexWhere((p) => _idOf(p['id']) == id);
    final previousItem = previousItemIndex >= 0
        ? items[previousItemIndex]
        : null;
    _pendingIds.add(id);
    _revision++;
    lastError = null;
    if (had) {
      ids.remove(id);
      items.removeWhere((p) => _idOf(p['id']) == id);
    } else {
      ids.add(id);
      if (previousItemIndex < 0) items.add(product);
    }
    notifyListeners();
    try {
      if (had) {
        await Api.I.removeFavorite(id);
      } else {
        await Api.I.addFavorite(id);
      }
      return true;
    } catch (_) {
      if (had) {
        ids.add(id);
        if (previousItem != null && !items.any((p) => _idOf(p['id']) == id)) {
          final insertAt = previousItemIndex.clamp(0, items.length).toInt();
          items.insert(insertAt, previousItem);
        }
      } else {
        ids.remove(id);
        items.removeWhere((p) => _idOf(p['id']) == id);
      }
      lastError = 'Could not update your favorites. Please try again.';
      notifyListeners();
      return false;
    } finally {
      _pendingIds.remove(id);
      notifyListeners();
    }
  }

  void clear() {
    _revision++;
    ids.clear();
    items = [];
    lastError = null;
    notifyListeners();
  }

  static int? _idOf(Object? value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
}
