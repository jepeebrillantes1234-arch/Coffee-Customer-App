import 'api.dart';

class ResolvedPlace {
  const ResolvedPlace({
    required this.name,
    required this.address,
    this.street = '',
    this.barangay = '',
    this.city = '',
    this.province = '',
    this.postalCode = '',
  });

  final String name;
  final String address;
  final String street;
  final String barangay;
  final String city;
  final String province;
  final String postalCode;
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
      // Google's formatted result can include a nearby road/street while the
      // API's compact address is intentionally limited to locality fields.
      final formattedAddress = (data['formatted_address'] ?? '')
          .toString()
          .trim();
      final address = (data['address'] ?? '').toString().trim();
      final name = (data['name'] ?? '').toString().trim();
      final readableAddress = formattedAddress.isNotEmpty
          ? formattedAddress
          : address;
      if (readableAddress.isEmpty && name.isEmpty) return null;
      return ResolvedPlace(
        name: name.isEmpty ? 'Selected location' : name,
        address: readableAddress.isEmpty ? name : readableAddress,
        street: (data['street'] ?? '').toString().trim(),
        barangay: (data['barangay'] ?? '').toString().trim(),
        city: (data['city'] ?? '').toString().trim(),
        province: (data['province'] ?? '').toString().trim(),
        postalCode: (data['postal_code'] ?? '').toString().trim(),
      );
    } catch (_) {
      return null;
    }
  }
}
