import 'api.dart';

class ResolvedPlace {
  const ResolvedPlace({required this.name, required this.address});

  final String name;
  final String address;
}

/// Resolves coordinates using the authenticated Laravel proxy, which keeps the
/// Google Geocoding API key on the server.
class ReverseGeocoder {
  static int _requestSequence = 0;

  static Future<ResolvedPlace?> resolve(
    double latitude,
    double longitude,
  ) async {
    final sequence = ++_requestSequence;
    try {
      final data = await Api.I.reverseGeocode(latitude, longitude);
      // Ignore a slower response if the customer has already moved the pin.
      if (sequence != _requestSequence) return null;
      final address = (data['address'] ?? '').toString().trim();
      final name = (data['name'] ?? '').toString().trim();
      if (address.isEmpty && name.isEmpty) return null;
      return ResolvedPlace(
        name: name.isEmpty ? 'Selected location' : name,
        address: address.isEmpty ? name : address,
      );
    } catch (_) {
      return null;
    }
  }
}
