class AppConfig {
  static const String reverbHost = String.fromEnvironment(
    'REVERB_HOST',
    defaultValue: 'agency-undecided-pantyhose.ngrok-free.dev',
  );
  static const int reverbPort = int.fromEnvironment('REVERB_PORT', defaultValue: 443);
  static const bool reverbUseTls = bool.fromEnvironment('REVERB_TLS', defaultValue: true);
  static const String reverbAppKey = 'coffee-shop-local-key';
  static const String apiBase = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://agency-undecided-pantyhose.ngrok-free.dev/api/v1',
  );

  // OAuth client ID of type 3 (Web) from this Firebase project's
  // google-services.json. This must belong to project kjm-coffee-shop.
  static const String googleServerClientId =
      '84167127871-dgvl7i9cfhm026eidb9bedh6dm12drcr.apps.googleusercontent.com';
}