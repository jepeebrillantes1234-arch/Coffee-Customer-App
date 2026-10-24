import 'package:flutter/material.dart';

import '../state/favorites.dart';
import 'menu_screen.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  @override
  void initState() {
    super.initState();
    Favorites.I.load();
  }

  @override
  Widget build(BuildContext context) {
    final page = Theme.of(context).scaffoldBackgroundColor;
    return Scaffold(
      backgroundColor: page,
      appBar: AppBar(
        backgroundColor: page,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: Icon(Icons.arrow_back_rounded, color: Theme.of(context).colorScheme.primary, size: 28),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            Icon(Icons.favorite_rounded, color: Color(0xFFE76565), size: 27),
            SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Favorites',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Your cravings, saved',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: Favorites.I,
        builder: (_, _) {
          final items = Favorites.I.items;
          if (items.isEmpty) {
            return const Center(
              child: Text(
                'You have no favorite items yet.\nTap the heart on an item to save it.',
                textAlign: TextAlign.center,
              ),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.67,
              crossAxisSpacing: 12,
              mainAxisSpacing: 14,
            ),
            itemCount: items.length,
            itemBuilder: (_, index) => productCard(context, items[index]),
          );
        },
      ),
    );
  }
}
