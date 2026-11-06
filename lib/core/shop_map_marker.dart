import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Builds the shared KJM Coffee Shop marker for maps that show shop settings.
Marker kjmShopMarker({required LatLng point, double size = 48}) => Marker(
  point: point,
  width: size + 10,
  height: size + 12,
  child: KjmShopMapMarkerIcon(size: size),
);

class KjmShopMapMarkerIcon extends StatelessWidget {
  const KjmShopMapMarkerIcon({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: size + 10,
      height: size + 12,
      child: Stack(
        alignment: Alignment.topCenter,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            bottom: -2,
            child: Icon(
              Icons.location_on_rounded,
              size: size + 14,
              color: colors.primary,
            ),
          ),
          Container(
            width: size,
            height: size,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: colors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: colors.primary, width: 2),
              boxShadow: [
                BoxShadow(
                  color: colors.shadow.withValues(alpha: .3),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/images/logo1.png',
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Icon(
                  Icons.coffee_rounded,
                  color: colors.primary,
                  size: size * .65,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
