import 'package:flutter/foundation.dart';

class AppConfig {
  static const String publicWebsiteUrl = String.fromEnvironment(
    'PUBLIC_WEBSITE_URL',
    defaultValue: '',
  );

  static Uri? get productionWebsiteUri =>
      parseProductionWebsiteUri(publicWebsiteUrl);

  @visibleForTesting
  static Uri? parseProductionWebsiteUri(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        !uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443)) {
      return null;
    }

    final host = uri.host.toLowerCase();
    if (host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '::1' ||
        host == '0.0.0.0' ||
        host.contains('ngrok')) {
      return null;
    }

    return uri;
  }

  static const String reverbHost = String.fromEnvironment(
    'REVERB_HOST',
    defaultValue: 'switch-geometric-coagulant.ngrok-free.dev',
  );
  static const int reverbPort = int.fromEnvironment(
    'REVERB_PORT',
    defaultValue: 443,
  );
  static const bool reverbUseTls = bool.fromEnvironment(
    'REVERB_TLS',
    defaultValue: true,
  );
  static const String reverbAppKey = 'coffee-shop-local-key';
  static const String apiBase = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://switch-geometric-coagulant.ngrok-free.dev/api/v1',
  );

  // OAuth client ID of type 3 (Web) from this Firebase project's
  // google-services.json. This must belong to project kjm-coffee-shop.
  static const String googleServerClientId =
      '84167127871-dgvl7i9cfhm026eidb9bedh6dm12drcr.apps.googleusercontent.com';
}
