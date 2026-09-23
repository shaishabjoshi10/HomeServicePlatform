import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../main.dart';

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
  final MapController _mapController = MapController();

  List<LatLng> _routePoints = [];
  double? _routeDistanceMeters;
  double? _routeDurationSeconds;
  bool _fetchingRoute = false;
  bool _fittedInitialBounds = false;

  LatLng get _customerLocation => LatLng(widget.customerLatitude, widget.customerLongitude);

  LatLng? get _providerLocation => widget.providerLatitude != null && widget.providerLongitude != null
      ? LatLng(widget.providerLatitude!, widget.providerLongitude!)
      : null;

  @override
  void initState() {
    super.initState();
    if (_providerLocation != null) {
      _fetchRoute();
      _maybeFitBounds();
    }
  }

  @override
  void didUpdateWidget(covariant CustomerNavigationMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final moved = oldWidget.providerLatitude != widget.providerLatitude ||
        oldWidget.providerLongitude != widget.providerLongitude;
    // A fresh poll landed with a new provider position — refresh the route
    // and, the very first time we ever get one, fit the camera to it.
    if (moved && _providerLocation != null) {
      _fetchRoute();
      _maybeFitBounds();
    }
  }

  Future<void> _fetchRoute() async {
    final from = _providerLocation;
    if (from == null || _fetchingRoute) return;
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
      // Keep whatever route is already on screen — the next poll (and the
      // route refresh it triggers) will try again.
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
    final providerLocation = _providerLocation;

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
                else if (providerLocation != null)
                  // No OSRM route yet (still loading, or the request
                  // failed) — a plain straight line still shows direction.
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: [providerLocation, _customerLocation],
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
                      child: Icon(Icons.home_rounded, color: kPrimaryGreen, size: 34),
                    ),
                    if (providerLocation != null)
                      Marker(
                        point: providerLocation,
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

            // ETA / distance pill, once we have both a fix and a route.
            if (providerLocation != null && _routeDistanceMeters != null)
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
          ],
        ),
      ),
    );
  }
}
