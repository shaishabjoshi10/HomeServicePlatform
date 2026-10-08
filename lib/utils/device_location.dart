import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// A location problem the user can act on (GPS off, permission denied, ...).
class DeviceLocationException implements Exception {
  final String message;
  const DeviceLocationException(this.message);

  @override
  String toString() => message;
}

/// One place that reads the phone's position for the whole emergency flow, so
/// the provider and the customer always get a position the same way.
///
/// A single high-accuracy GPS request often takes longer than 10s indoors
/// (the usual place to test). Failing there silently left providers with a
/// stale position that the server then hid, and left customers with a
/// "location" error. Instead we step down: high accuracy -> balanced
/// (Wi-Fi/cell) -> last known position.
class DeviceLocation {
  static Future<void> _ensureReady() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const DeviceLocationException(
          'Location services are turned off. Turn on your phone\'s location (GPS) and try again.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const DeviceLocationException(
          'Location permission is blocked. Allow it in your phone\'s app settings.');
    }
    if (permission == LocationPermission.denied) {
      throw const DeviceLocationException('Location permission is needed for emergency service.');
    }
  }

  static Future<Position?> _try(LocationAccuracy accuracy, Duration limit) async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: accuracy),
      ).timeout(limit);
    } catch (_) {
      return null;
    }
  }

  /// Best available position, or throws a [DeviceLocationException].
  ///
  /// The last-known fallback is only used while it is recent
  /// ([maxLastKnownAge]): the server stamps whatever we send as "now", so an
  /// hours-old cached fix would otherwise place the provider (or customer) at
  /// a spot they left long ago and show them as nearby when they are not.
  static Future<Position> getBest({
    Duration maxLastKnownAge = const Duration(minutes: 2),
  }) async {
    await _ensureReady();

    final precise = await _try(LocationAccuracy.high, const Duration(seconds: 8));
    if (precise != null) return precise;

    final balanced = await _try(LocationAccuracy.medium, const Duration(seconds: 8));
    if (balanced != null) return balanced;

    try {
      final last = await Geolocator.getLastKnownPosition();
      final DateTime? fixedAt = last?.timestamp;
      if (last != null &&
          fixedAt != null &&
          DateTime.now().difference(fixedAt) <= maxLastKnownAge) {
        return last;
      }
    } catch (_) {
      // fall through
    }
    throw const DeviceLocationException(
        'Could not get your location. Move to an open area or check that GPS is on, then try again.');
  }
}