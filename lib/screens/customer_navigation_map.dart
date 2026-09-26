import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../main.dart';

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

  const _NavSnapshot({
    this.providerLocation,
    this.routePoints = const [],
    this.routeDistanceMeters,
    this.routeDurationSeconds,
  });

  _NavSnapshot copyWith({
    LatLng? providerLocation,
    List<LatLng>? routePoints,
    double? routeDistanceMeters,
    double? routeDurationSeconds,
  }) {
    return _NavSnapshot(
      providerLocation: providerLocation ?? this.providerLocation,
      routePoints: routePoints ?? this.routePoints,
      routeDistanceMeters: routeDistanceMeters ?? this.routeDistanceMeters,
      routeDurationSeconds: routeDurationSeconds ?? this.routeDurationSeconds,
    );
  }
}

/// Read-only live tracking map shown on the customer's booking details page
/// once the provider has clicked "I'm on my way". Unlike
/// `ProviderNavigationMap` this widget never touches the device's own GPS —
/// the customer isn't the one moving, they're just watching. All it needs
/// is the provider's latest position, which the *parent* page polls the
/// server for (see BookingDetailsPage._pollBooking) and passes down as
/// [providerLatitude] / [providerLongitude] on every rebuild; this widget's
/// own job is just to render that, keep an OSRM driving route between the
/// two points fresh, and fit the camera.
///
/// The parent stops rendering this widget the moment the booking is marked
/// completed (its status leaves 'on_the_way' / 'arrived'), which is what
/// actually removes the provider's location from the customer's map —
/// there's nothing left here to keep polling or displaying once that
/// happens.
///
/// Tapping the map pushes a full-screen page showing the exact same
/// content, larger — see [_openFullScreen]. It reads from the same
/// [_NavSnapshot] notifier as the compact map, so as long as it stays
/// open it keeps reflecting whatever the parent's polling delivers next,
/// rather than showing a frozen snapshot from the moment it was tapped.
class CustomerNavigationMap extends StatefulWidget {
  final double customerLatitude;
  final double customerLongitude;
  final double? providerLatitude;
  final double? providerLongitude;

  const CustomerNavigationMap({
    super.key,
    required this.customerLatitude,
    required this.customerLongitude,
    required this.providerLatitude,
    required this.providerLongitude,
  });

  @override
  State<CustomerNavigationMap> createState() => _CustomerNavigationMapState();
}

class _CustomerNavigationMapState extends State<CustomerNavigationMap> {
  late final ValueNotifier<_NavSnapshot> _snapshot = ValueNotifier(
    _NavSnapshot(providerLocation: _providerLocationFromWidget),
  );

  bool _fetchingRoute = false;

  LatLng get _customerLocation => LatLng(widget.customerLatitude, widget.customerLongitude);

  LatLng? get _providerLocationFromWidget =>
      widget.providerLatitude != null && widget.providerLongitude != null
          ? LatLng(widget.providerLatitude!, widget.providerLongitude!)
          : null;

  @override
  void initState() {
    super.initState();
    final location = _providerLocationFromWidget;
    if (location != null) _fetchRoute(location);
  }

  @override
  void didUpdateWidget(covariant CustomerNavigationMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final moved = oldWidget.providerLatitude != widget.providerLatitude ||
        oldWidget.providerLongitude != widget.providerLongitude;
    final location = _providerLocationFromWidget;
    if (moved && location != null) {
      _snapshot.value = _snapshot.value.copyWith(providerLocation: location);
      _fetchRoute(location);
    }
  }

  @override
  void dispose() {
    _snapshot.dispose();
    super.dispose();
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
      // Keep whatever route is already on screen — the next poll (and the
      // route refresh it triggers) will try again.
    } finally {
      _fetchingRoute = false;
    }
  }

  void _openFullScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FullScreenCustomerMap(
          snapshot: _snapshot,
          customerLocation: _customerLocation,
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
        child: _CustomerMapBody(
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
class _FullScreenCustomerMap extends StatelessWidget {
  final ValueListenable<_NavSnapshot> snapshot;
  final LatLng customerLocation;

  const _FullScreenCustomerMap({required this.snapshot, required this.customerLocation});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: kDarkText,
        elevation: 0,
        title: const Text('Live Tracking'),
      ),
      body: _CustomerMapBody(
        snapshot: snapshot,
        customerLocation: customerLocation,
        expanded: true,
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
class _CustomerMapBody extends StatefulWidget {
  final ValueListenable<_NavSnapshot> snapshot;
  final LatLng customerLocation;
  final bool expanded;

  const _CustomerMapBody({
    required this.snapshot,
    required this.customerLocation,
    required this.expanded,
  });

  @override
  State<_CustomerMapBody> createState() => _CustomerMapBodyState();
}

class _CustomerMapBodyState extends State<_CustomerMapBody> {
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
    final homeMarkerSize = widget.expanded ? 44.0 : 40.0;
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
                          width: homeMarkerSize,
                          height: homeMarkerSize,
                          child: Icon(Icons.home_rounded, color: kPrimaryGreen, size: homeMarkerSize * 0.85),
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

              // ETA / distance pill, once we have both a fix and a route.
              if (providerLocation != null && snap.routeDistanceMeters != null)
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

              // Shown briefly right after the provider taps "I'm on my way",
              // before their very first GPS fix has made it to the server.
              if (providerLocation == null)
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "Waiting for the provider's location…",
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
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