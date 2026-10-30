import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

List<LatLng> routePointsFrom(dynamic route) {
  if (route is! Map || route['points'] is! List) return const [];
  return (route['points'] as List)
      .whereType<Map>()
      .map((point) {
        final lat = double.tryParse('${point['lat'] ?? ''}');
        final lng = double.tryParse('${point['lng'] ?? ''}');
        return lat == null || lng == null ? null : LatLng(lat, lng);
      })
      .whereType<LatLng>()
      .toList(growable: false);
}

/// Returns a road point for display only when the live GPS point is nearby.
/// The original GPS coordinates are still used for location uploads.
LatLng? nearestRoadPoint(LatLng? gps, List<LatLng> route) {
  if (gps == null || route.isEmpty) return null;
  var nearest = route.first;
  var nearestMeters = double.infinity;
  for (final point in route) {
    final meters = Geolocator.distanceBetween(
      gps.latitude,
      gps.longitude,
      point.latitude,
      point.longitude,
    );
    if (meters < nearestMeters) {
      nearest = point;
      nearestMeters = meters;
    }
  }
  return nearestMeters <= 120 ? nearest : null;
}
