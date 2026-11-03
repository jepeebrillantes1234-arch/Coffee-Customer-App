import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../core/api.dart';

/// Shares the rider phone's fresh GPS with every active en-route delivery.
class LocationService {
  LocationService._();
  static final LocationService I = LocationService._();

  StreamSubscription<Position>? _sub;
  Timer? _timer;
  Position? _last;
  final Set<int> _deliveryIds = {};
  bool _sending = false;
  bool _starting = false;
  bool _streamHasFix = false;
  int _generation = 0;

  final ValueNotifier<Position?> position = ValueNotifier<Position?>(null);
  final ValueNotifier<bool> tracking = ValueNotifier<bool>(false);
  final ValueNotifier<String?> error = ValueNotifier<String?>(null);
  final ValueNotifier<String?> settingsAction = ValueNotifier<String?>(null);

  Future<bool> _ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      error.value = 'Turn on your phone location/GPS.';
      settingsAction.value = 'location';
      return false;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.unableToDetermine) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever ||
        perm == LocationPermission.unableToDetermine) {
      error.value = perm == LocationPermission.deniedForever
          ? 'Location permission is blocked. Allow it in app Settings.'
          : 'Location permission was denied. Allow access while using the app.';
      settingsAction.value = perm == LocationPermission.deniedForever
          ? 'app'
          : null;
      return false;
    }
    settingsAction.value = null;
    return true;
  }

  Future<bool> ensureReady() => _ensurePermission();

  LocationSettings _settings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        intervalDuration: const Duration(seconds: 5),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Coffee Rider',
          notificationText: 'Sharing location during delivery',
          enableWakeLock: true,
        ),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        activityType: ActivityType.automotiveNavigation,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );
  }

  Future<bool> start({required int deliveryId}) async {
    if (deliveryId <= 0) return false;
    _deliveryIds.add(deliveryId);
    if (_sub != null) {
      unawaited(_send());
      return true;
    }
    return _startTracking();
  }

  /// Replaces the set of deliveries that should receive this rider phone's GPS.
  Future<bool> syncActiveDeliveries(Iterable<int> deliveryIds) async {
    final next = deliveryIds.where((id) => id > 0).toSet();
    if (next.isEmpty) {
      await stop();
      return true;
    }

    final unchanged =
        _deliveryIds.length == next.length && _deliveryIds.containsAll(next);
    _deliveryIds
      ..clear()
      ..addAll(next);
    if (_sub != null) {
      if (!unchanged) unawaited(_send());
      return true;
    }
    if (unchanged && _starting) return true;
    return _startTracking();
  }

  Future<void> removeDelivery(int deliveryId) async {
    _deliveryIds.remove(deliveryId);
    if (_deliveryIds.isEmpty) {
      await stop();
    } else if (_sub != null) {
      unawaited(_send());
    }
  }

  Future<bool> _startTracking() async {
    if (_sub != null) return true;
    if (_starting) return true;
    _starting = true;
    final generation = _generation;
    try {
      if (!await _ensurePermission()) return false;
      if (generation != _generation || _deliveryIds.isEmpty) return false;

      _streamHasFix = false;
      _last = null;
      position.value = null;
      tracking.value = false;
      error.value = null;
      _sub = Geolocator.getPositionStream(locationSettings: _settings()).listen(
        (p) {
          final firstFix = !_streamHasFix;
          _streamHasFix = true;
          _last = p;
          position.value = p;
          if (firstFix) unawaited(_send());
        },
        onError: (Object e) {
          // Do not refresh the server timestamp using an old GPS fix.
          _last = null;
          position.value = null;
          tracking.value = false;
          error.value = 'GPS updates stopped. Check location access and GPS.';
        },
      );

      try {
        final p = await Geolocator.getCurrentPosition();
        if (generation != _generation || _deliveryIds.isEmpty) return false;
        // Keep a newer stream position if it arrived during this request.
        if (!_streamHasFix) {
          _last = p;
          position.value = p;
        }
      } catch (_) {
        if (_last == null) {
          tracking.value = false;
          error.value = 'Could not get the current GPS location. Check GPS and try again.';
          await _sub?.cancel();
          _sub = null;
          return false;
        }
      }

      if (generation != _generation || _deliveryIds.isEmpty) return false;
      // Keep the update cadence below the per-rider API throttle while still
      // refreshing customer tracking frequently.
      _timer = Timer.periodic(const Duration(seconds: 8), (_) => _send());
      await _send();
      return _last != null;
    } finally {
      _starting = false;
    }
  }

  Future<void> _send() async {
    final p = _last;
    if (p == null || _sending || _deliveryIds.isEmpty) return;
    if (DateTime.now().difference(p.timestamp).abs() >
        const Duration(seconds: 30)) {
      _last = null;
      position.value = null;
      tracking.value = false;
      error.value =
          'Waiting for a fresh GPS location. Check GPS and location access.';
      return;
    }
    _sending = true;
    try {
      final kmh = p.speed < 0 ? 0.0 : p.speed * 3.6;
      final ids = _deliveryIds.toList(growable: false);
      String? sendError;
      for (final id in ids) {
        if (!_deliveryIds.contains(id)) continue;
        try {
          await Api.I.sendLocation(id, p.latitude, p.longitude, kmh);
        } on ApiException catch (e) {
          sendError ??= e.message;
        } catch (_) {
          sendError ??= 'Unable to share live location. Check your connection.';
        }
      }
      if (_deliveryIds.isEmpty) return;
      if (sendError != null) {
        tracking.value = false;
        error.value = sendError;
      } else {
        tracking.value = true;
        error.value = null;
      }
    } catch (_) {
      tracking.value = false;
      error.value = 'Unable to share live location. Check your connection.';
    } finally {
      _sending = false;
    }
  }

  Future<void> stop() async {
    _generation++;
    await _sub?.cancel();
    _sub = null;
    _timer?.cancel();
    _timer = null;
    _last = null;
    _streamHasFix = false;
    _deliveryIds.clear();
    _sending = false;
    position.value = null;
    tracking.value = false;
    settingsAction.value = null;
  }
}
