import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../main.dart';
import '../services/booking_service.dart';

/// Immutable snapshot of everything the map body needs to render, at one
/// point in time. Kept separate from the tracking `State` itself so that
/// both the compact, inline map and the full-screen map opened by tapping
/// it can render from the exact same live data via a single
/// `ValueListenable`, instead of the full-screen view being frozen at
/// whatever the data happened to be the moment it was opened.
class _NavSnapshot {
  final LatLng? providerLocation;
  final List<LatLng> routePoints;
  final double? routeDistanceMeters;
  final double? routeDurationSeconds;
  final String? locationError;
  final bool isTracking;

  const _NavSnapshot({
    this.providerLocation,
    this.routePoints = const [],
    this.routeDistanceMeters,
    this.routeDurationSeconds,
    this.locationError,
    required this.isTracking,
  });

  _NavSnapshot copyWith({
    LatLng? providerLocation,
    bool clearProviderLocation = false,
    List<LatLng>? routePoints,
    double? routeDistanceMeters,
    double? routeDurationSeconds,
    String? locationError,
    bool clearLocationError = false,
    bool? isTracking,
  }) {
    return _NavSnapshot(
      providerLocation: clearProviderLocation ? null : (providerLocation ?? this.providerLocation),
      routePoints: routePoints ?? this.routePoints,
      routeDistanceMeters: routeDistanceMeters ?? this.routeDistanceMeters,
      routeDurationSeconds: routeDurationSeconds ?? this.routeDurationSeconds,
      locationError: clearLocationError ? null : (locationError ?? this.locationError),
      isTracking: isTracking ?? this.isTracking,
    );
  }
}

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
/// Tapping the map pushes a full-screen page showing the exact same
/// content, larger — see [_openFullScreen]. It reads from the same
/// [_NavSnapshot] notifier as the compact map, so it keeps updating live
/// (new GPS fixes, route refreshes) for as long as it's open, rather than
/// showing a frozen snapshot from the moment it was tapped.
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
  bool get _isTracking => widget.status == 'on_the_way' || widget.status == 'arrived';

  late final ValueNotifier<_NavSnapshot> _snapshot =
  ValueNotifier(_NavSnapshot(isTracking: _isTracking));

  StreamSubscription<Position>? _positionSub;
  Timer? _routeRefreshTimer;
  bool _fetchingRoute = false;

  // Throttle: don't push every single GPS sample to the server.
  DateTime? _lastPushedAt;
  static const _minPushInterval = Duration(seconds: 4);

  LatLng get _customerLocation => LatLng(widget.customerLatitude, widget.customerLongitude);

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
      _snapshot.value = _snapshot.value.copyWith(isTracking: true);
      _startTracking();
    } else if (!_isTracking && wasTracking) {
      _stopTracking();
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _routeRefreshTimer?.cancel();
    _snapshot.dispose();
    super.dispose();
  }

  Future<void> _startTracking() async {
    _snapshot.value = _snapshot.value.copyWith(clearLocationError: true);
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
      _snapshot.value = _snapshot.value.copyWith(
        locationError: "Couldn't access your location. Enable location sharing to start the journey.",
      );
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
      final current = _snapshot.value.providerLocation;
      if (current != null) _fetchRoute(current);
    });
  }

  void _stopTracking() {
    _positionSub?.cancel();
    _positionSub = null;
    _routeRefreshTimer?.cancel();
    _routeRefreshTimer = null;
    _snapshot.value = _NavSnapshot(isTracking: false);
  }

  void _onNewPosition(Position position) {
    if (!mounted) return;
    final point = LatLng(position.latitude, position.longitude);
    _snapshot.value = _snapshot.value.copyWith(providerLocation: point);
    _pushLocation(point);
    _fetchRoute(point);
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
          _snapshot.value = _snapshot.value.copyWith(
            routePoints: points,
            routeDistanceMeters: (route['distance'] as num?)?.toDouble(),
            routeDurationSeconds: (route['duration'] as num?)?.toDouble(),
          );
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

  void _openFullScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FullScreenNavigationMap(
          snapshot: _snapshot,
          customerLocation: _customerLocation,
          customerAddress: widget.customerAddress,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: _openFullScreen,
      child: SizedBox(
        height: 260,
        child: _NavigationMapBody(
          snapshot: _snapshot,
          customerLocation: _customerLocation,
          expanded: false,
        ),
      ),
    );
  }
}

/// The full-screen page opened by tapping the compact map. Same location,
/// markers, route and live-location information as the inline card — just
/// larger, and kept live via the shared [snapshot] rather than frozen at
/// the moment it was opened.
class _FullScreenNavigationMap extends StatelessWidget {
  final ValueListenable<_NavSnapshot> snapshot;
  final LatLng customerLocation;
  final String customerAddress;

  const _FullScreenNavigationMap({
    required this.snapshot,
    required this.customerLocation,
    required this.customerAddress,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: kDarkText,
        elevation: 0,
        title: const Text('Live Navigation'),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.location_on_rounded, color: kPrimaryGreen, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      customerAddress,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: kDarkText),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _NavigationMapBody(
                snapshot: snapshot,
                customerLocation: customerLocation,
                expanded: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Presentational map body shared by the compact card and the full-screen
/// page: a `FlutterMap` with the customer/provider markers and route,
/// rebuilding whenever [snapshot] changes. Each instance owns its own
/// `MapController` and fits the camera to the two points the first time a
/// provider fix shows up — both the compact and full-screen instances can
/// be mounted at once (during the push/pop transition, and for as long as
/// the full-screen page stays open), so they can't share one controller.
class _NavigationMapBody extends StatefulWidget {
  final ValueListenable<_NavSnapshot> snapshot;
  final LatLng customerLocation;
  final bool expanded;

  const _NavigationMapBody({
    required this.snapshot,
    required this.customerLocation,
    required this.expanded,
  });

  @override
  State<_NavigationMapBody> createState() => _NavigationMapBodyState();
}

class _NavigationMapBodyState extends State<_NavigationMapBody> {
  final MapController _mapController = MapController();
  bool _fittedInitialBounds = false;

  void _maybeFitBounds(LatLng? providerLocation) {
    if (_fittedInitialBounds || providerLocation == null) return;
    _fittedInitialBounds = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds(providerLocation, widget.customerLocation),
            padding: EdgeInsets.fromLTRB(36, 36, 36, widget.expanded ? 96 : 36),
          ),
        );
      } catch (_) {
        // Map not laid out yet — leave it at its initial center/zoom.
      }
    });
  }

  String _formatEta(_NavSnapshot snap) {
    if (snap.routeDistanceMeters == null || snap.routeDurationSeconds == null) return '';
    final km = (snap.routeDistanceMeters! / 1000).toStringAsFixed(1);
    final minutes = (snap.routeDurationSeconds! / 60).ceil();
    return '$km km away · about $minutes min';
  }

  @override
  Widget build(BuildContext context) {
    final markerSize = widget.expanded ? 48.0 : 40.0;
    final providerMarkerSize = widget.expanded ? 44.0 : 36.0;
    final etaFontSize = widget.expanded ? 14.0 : 12.0;

    return ValueListenableBuilder<_NavSnapshot>(
      valueListenable: widget.snapshot,
      builder: (context, snap, _) {
        _maybeFitBounds(snap.providerLocation);
        final providerLocation = snap.providerLocation;

        return ClipRRect(
          borderRadius: widget.expanded ? BorderRadius.zero : BorderRadius.circular(16),
          child: Stack(
            children: [
              Positioned.fill(
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: widget.customerLocation,
                    initialZoom: 14,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.gharsewa.app',
                    ),
                    if (snap.routePoints.isNotEmpty)
                      PolylineLayer(
                        polylines: [
                          Polyline(points: snap.routePoints, strokeWidth: 4, color: Colors.blue.shade600),
                        ],
                      )
                    else if (providerLocation != null)
                    // No OSRM route yet (still loading, or the request
                    // failed) — a plain straight line still shows direction.
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: [providerLocation, widget.customerLocation],
                            strokeWidth: 3,
                            color: Colors.blue.shade200,
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: widget.customerLocation,
                          width: markerSize,
                          height: markerSize,
                          child: Icon(Icons.location_on_rounded, color: kPrimaryGreen, size: markerSize * 0.9),
                        ),
                        if (providerLocation != null)
                          Marker(
                            point: providerLocation,
                            width: providerMarkerSize,
                            height: providerMarkerSize,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade600,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                              ),
                              child: Icon(Icons.two_wheeler_rounded, color: Colors.white, size: providerMarkerSize * 0.5),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // ETA / distance pill, only once we have a route.
              if (snap.isTracking && snap.routeDistanceMeters != null)
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
                        Text(_formatEta(snap),
                            style: TextStyle(fontSize: etaFontSize, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),

              // Location-permission error banner.
              if (snap.locationError != null)
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
                            snap.locationError!,
                            style: TextStyle(fontSize: 11, color: Colors.red.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // A small affordance on the compact card only, hinting it's
              // tappable without needing to change any other booking UI.
              if (!widget.expanded)
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                    ),
                    child: Icon(Icons.fullscreen_rounded, size: 16, color: Colors.grey.shade700),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}