import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../main.dart';
import '../services/booking_service.dart';

/// Live navigation map shown on a provider's booking details page once a
/// booking has been accepted. What it shows layers on top of the booking's
/// own status, and the caller drives that just by passing the current
/// [status] in — this widget reacts to it rather than tracking its own
/// copy:
///
///   accepted             -> the customer's pin only, map centered on them.
///   on_the_way / arrived -> + the provider's own live position (tracked
///                           via the device GPS and pushed to the server
///                           every few seconds so it survives the provider
///                           backgrounding the app) and the driving route
///                           between the two.
///   anything else         -> nothing: sharing stops. In practice the
///                           caller simply stops rendering this widget once
///                           a job is completed (see
///                           ProviderBookingDetailsPage), which tears this
///                           State down and — via [dispose] — cancels the
///                           GPS stream and the periodic route refresh for
///                           us. That's what actually "stops live location
///                           sharing and removes the route/location from
///                           the map".
///
/// Routing uses the public OSRM demo server, matching the OpenStreetMap
/// stack the rest of the app already uses for tiles/geocoding (see
/// location_picker.dart) rather than pulling in a Google Maps key.
class ProviderNavigationMap extends StatefulWidget {
  final String accessToken;
  final String bookingId;
  final String status; // 'accepted' | 'on_the_way' | 'arrived' | ...
  final double customerLatitude;
  final double customerLongitude;
  final String customerAddress;

  const ProviderNavigationMap({
    super.key,
    required this.accessToken,
    required this.bookingId,
    required this.status,
    required this.customerLatitude,
    required this.customerLongitude,
    required this.customerAddress,
  });

  @override
  State<ProviderNavigationMap> createState() => _ProviderNavigationMapState();
}

class _ProviderNavigationMapState extends State<ProviderNavigationMap> {
  final MapController _mapController = MapController();

  StreamSubscription<Position>? _positionSub;
  Timer? _routeRefreshTimer;

  LatLng? _providerLocation;
  List<LatLng> _routePoints = [];
  double? _routeDistanceMeters;
  double? _routeDurationSeconds;

  String? _locationError;
  bool _fetchingRoute = false;
  bool _fittedInitialBounds = false;

  // Throttle: don't push every single GPS sample to the server.
  DateTime? _lastPushedAt;
  static const _minPushInterval = Duration(seconds: 4);

  LatLng get _customerLocation => LatLng(widget.customerLatitude, widget.customerLongitude);

  bool get _isTracking => widget.status == 'on_the_way' || widget.status == 'arrived';

  @override
  void initState() {
    super.initState();
    if (_isTracking) _startTracking();
  }

  @override
  void didUpdateWidget(covariant ProviderNavigationMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasTracking = oldWidget.status == 'on_the_way' || oldWidget.status == 'arrived';
    if (_isTracking && !wasTracking) {
      _startTracking();
    } else if (!_isTracking && wasTracking) {
      _stopTracking();
    }
  }

  @override
  void dispose() {
    _stopTracking();
    super.dispose();
  }

  Future<void> _startTracking() async {
    setState(() => _locationError = null);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('Location services are off');

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        throw Exception('Location permission denied');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _locationError = "Couldn't access your location. Enable location sharing to start the journey.";
      });
      return;
    }

    // Seed with a single fix right away so the map has something to show
    // immediately, rather than waiting on the first stream event.
    try {
      final initial = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 10));
      _onNewPosition(initial);
    } catch (_) {
      // Fall through — the stream below will supply a fix once it can.
    }

    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15, // meters — avoid flooding updates while stationary
      ),
    ).listen(_onNewPosition, onError: (_) {});

    // Keeps the route reasonably fresh even if the provider is stationary
    // for a while (no new GPS samples to trigger a refresh on their own).
    _routeRefreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_providerLocation != null) _fetchRoute(_providerLocation!);
    });
  }

  void _stopTracking() {
    _positionSub?.cancel();
    _positionSub = null;
    _routeRefreshTimer?.cancel();
    _routeRefreshTimer = null;
    _providerLocation = null;
    _routePoints = [];
    _routeDistanceMeters = null;
    _routeDurationSeconds = null;
    _fittedInitialBounds = false;
  }

  void _onNewPosition(Position position) {
    if (!mounted) return;
    final point = LatLng(position.latitude, position.longitude);
    setState(() => _providerLocation = point);
    _pushLocation(point);
    _fetchRoute(point);
    _maybeFitBounds();
  }

  Future<void> _pushLocation(LatLng point) async {
    final now = DateTime.now();
    if (_lastPushedAt != null && now.difference(_lastPushedAt!) < _minPushInterval) return;
    _lastPushedAt = now;
    try {
      await BookingService.updateProviderLocation(
        accessToken: widget.accessToken,
        bookingId: widget.bookingId,
        latitude: point.latitude,
        longitude: point.longitude,
      );
    } catch (_) {
      // Best-effort: a missed update just means the next GPS sample (or
      // the periodic route refresh) will catch the server back up.
    }
  }

  Future<void> _fetchRoute(LatLng from) async {
    if (_fetchingRoute) return;
    _fetchingRoute = true;
    try {
      final to = _customerLocation;
      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
        '?overview=full&geometries=geojson',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final routes = data['routes'] as List<dynamic>?;
        if (routes != null && routes.isNotEmpty) {
          final route = routes.first as Map<String, dynamic>;
          final coords = (route['geometry'] as Map<String, dynamic>)['coordinates'] as List<dynamic>;
          final points = coords
              .map((c) => LatLng((c as List<dynamic>)[1] as double, (c[0] as num).toDouble()))
              .toList();
          if (!mounted) return;
          setState(() {
            _routePoints = points;
            _routeDistanceMeters = (route['distance'] as num?)?.toDouble();
            _routeDurationSeconds = (route['duration'] as num?)?.toDouble();
          });
        }
      }
    } catch (_) {
      // Keep whatever route is already on screen — a stale route still
      // orients the customer better than none, and the next scheduled
      // refresh (or GPS sample) will try again.
    } finally {
      _fetchingRoute = false;
    }
  }

  void _maybeFitBounds() {
    if (_fittedInitialBounds || _providerLocation == null) return;
    _fittedInitialBounds = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds(_providerLocation!, _customerLocation),
            padding: const EdgeInsets.fromLTRB(36, 36, 36, 36),
          ),
        );
      } catch (_) {
        // Map not laid out yet — leave it at its initial center/zoom.
      }
    });
  }

  String _formatEta() {
    if (_routeDistanceMeters == null || _routeDurationSeconds == null) return '';
    final km = (_routeDistanceMeters! / 1000).toStringAsFixed(1);
    final minutes = (_routeDurationSeconds! / 60).ceil();
    return '$km km away · about $minutes min';
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 260,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _customerLocation,
                initialZoom: 14,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.gharsewa.app',
                ),
                if (_routePoints.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(points: _routePoints, strokeWidth: 4, color: Colors.blue.shade600),
                    ],
                  )
                else if (_providerLocation != null)
                  // No OSRM route yet (still loading, or the request
                  // failed) — a plain straight line still shows direction.
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: [_providerLocation!, _customerLocation],
                        strokeWidth: 3,
                        color: Colors.blue.shade200,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _customerLocation,
                      width: 40,
                      height: 40,
                      child: Icon(Icons.location_on_rounded, color: kPrimaryGreen, size: 36),
                    ),
                    if (_providerLocation != null)
                      Marker(
                        point: _providerLocation!,
                        width: 36,
                        height: 36,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade600,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                          ),
                          child: const Icon(Icons.two_wheeler_rounded, color: Colors.white, size: 18),
                        ),
                      ),
                  ],
                ),
              ],
            ),

            // ETA / distance pill, only once we have a route.
            if (_isTracking && _routeDistanceMeters != null)
              Positioned(
                left: 10,
                top: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.directions_car_filled_rounded, size: 14, color: Colors.blue.shade600),
                      const SizedBox(width: 6),
                      Text(_formatEta(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),

            // Location-permission error banner.
            if (_locationError != null)
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline_rounded, size: 16, color: Colors.red.shade600),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _locationError!,
                          style: TextStyle(fontSize: 11, color: Colors.red.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
