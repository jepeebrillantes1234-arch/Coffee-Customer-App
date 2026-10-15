import 'dart:async';

import 'package:pusher_reverb_flutter/pusher_reverb_flutter.dart';

import 'api.dart';
import 'config.dart';

class Realtime {
  Realtime._();
  static final Realtime I = Realtime._();
  final _updates = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get updates => _updates.stream;
  bool _connecting = false;
  bool _connected = false;
  String? _channelName;

  Future<void> connect() async {
    final token = Api.I.accessToken;
    final userId = Api.I.user?['id']?.toString();
    if (token == null || userId == null || _connected || _connecting) return;
    _connecting = true;
    try {
      final base = Uri.parse(AppConfig.apiBase);
      final authUri = base.resolve('/api/v1/broadcasting/auth').toString();
      final client = ReverbClient.instance(
        host: AppConfig.reverbHost,
        port: AppConfig.reverbPort,
        appKey: AppConfig.reverbAppKey,
        useTLS: AppConfig.reverbUseTls,
        authEndpoint: authUri,
        authorizer: (channelName, socketId) async => {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );
      await client.connect();
      final channel = client.subscribeToPrivateChannel('private-users.$userId');
      void forward(dynamic event, dynamic data) {
        final payload = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
        if (!_updates.isClosed) _updates.add(payload);
      }
      channel.bind('live.updated', forward);
      final menu = client.subscribeToChannel('menu.updates');
      menu.bind('live.updated', forward);

      _channelName = 'private-users.$userId';
      _connected = true;
    } catch (_) {
      // Live events are an enhancement; API actions and manual refresh remain available.
    } finally {
      _connecting = false;
    }
  }

  Future<void> disconnect() async {
    if (!_connected || _channelName == null) return;
    try {
      final client = ReverbClient.instance();
      await client.subscribeToPrivateChannel(_channelName!).unsubscribe();
      client.disconnect();
    } catch (_) {}
    _connected = false;
    _channelName = null;
  }
}

