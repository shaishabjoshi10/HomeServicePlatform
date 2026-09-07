import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../main.dart';

/// Result handed back to the caller once the user confirms a point on the map.
class PickedLocation {
  final double latitude;
  final double longitude;
  final String address;

  const PickedLocation({
    required this.latitude,
    required this.longitude,
    required this.address,
  });
}

// Default map center when we can't get the device's location — central Kathmandu.
const LatLng _kathmanduFallback = LatLng(27.7172, 85.3240);

/// One row returned by the place-search box (Nominatim's forward geocoder).
class _SearchResult {
  final String displayName;
  final double latitude;
  final double longitude;

  const _SearchResult({
    required this.displayName,
    required this.latitude,
    required this.longitude,
  });
}

/// Full-screen map picker: the map pans under a fixed center pin, the
/// address for whatever's under the pin is reverse-geocoded live, and
/// "Confirm Location" hands both the coordinates and address back.
class LocationPickerPage extends StatefulWidget {
  /// Optional starting point (e.g. a location picked previously).
  final LatLng? initialLocation;

  const LocationPickerPage({super.key, this.initialLocation});

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  final MapController _mapController = MapController();
  final _searchController = TextEditingController();

  late LatLng _center = widget.initialLocation ?? _kathmanduFallback;
  String _address = 'Move the map to choose a location';
  bool _resolvingAddress = false;
  bool _locatingDevice = false;

  List<_SearchResult> _searchResults = [];
  bool _searching = false;

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    if (widget.initialLocation != null) {
      _resolveAddress(_center);
    } else {
      _useDeviceLocation(recenterMap: false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _useDeviceLocation({bool recenterMap = true}) async {
    setState(() => _locatingDevice = true);
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

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 10));

      final here = LatLng(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() {
        _center = here;
        _locatingDevice = false;
      });
      if (recenterMap) {
        _mapController.move(here, _mapController.camera.zoom);
      }
      _resolveAddress(here);
    } catch (_) {
      if (!mounted) return;
      setState(() => _locatingDevice = false);
      // Couldn't get the device location — leave the map at its current
      // center (Kathmandu, or wherever the user had already panned to)
      // and just resolve whatever's there so the flow isn't a dead end.
      _resolveAddress(_center);
    }
  }

  void _onMapEvent(MapEvent event) {
    if (event is MapEventMoveEnd || event is MapEventFlingAnimationEnd) {
      final newCenter = _mapController.camera.center;
      setState(() => _center = newCenter);
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 400), () => _resolveAddress(newCenter));
    }
  }

  Future<void> _resolveAddress(LatLng point) async {
    setState(() => _resolvingAddress = true);
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
            '?format=json&lat=${point.latitude}&lon=${point.longitude}&zoom=18&addressdetails=0',
      );
      // Nominatim's usage policy requires a real User-Agent identifying the app.
      final response = await http
          .get(uri, headers: {'User-Agent': 'GharSewaApp/1.0'})
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final displayName = data['display_name'] as String?;
        if (!mounted) return;
        setState(() {
          _address = displayName ?? _fallbackLabel(point);
          _resolvingAddress = false;
        });
        return;
      }
    } catch (_) {
      // fall through to the coordinate label below
    }
    if (!mounted) return;
    setState(() {
      _address = _fallbackLabel(point);
      _resolvingAddress = false;
    });
  }

  String _fallbackLabel(LatLng point) =>
      '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';

  Future<void> _performSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
            '?q=${Uri.encodeQueryComponent(q)}&format=json&limit=6&addressdetails=0&countrycodes=np',
      );
      // Nominatim's usage policy requires a real User-Agent identifying the app.
      final response = await http
          .get(uri, headers: {'User-Agent': 'GharSewaApp/1.0'})
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
        if (!mounted) return;
        setState(() {
          _searchResults = data
              .map((e) => _SearchResult(
            displayName: e['display_name'] as String,
            latitude: double.parse(e['lat'] as String),
            longitude: double.parse(e['lon'] as String),
          ))
              .toList();
          _searching = false;
        });
        return;
      }
    } catch (_) {
      // fall through to the empty-results state below
    }
    if (!mounted) return;
    setState(() {
      _searchResults = [];
      _searching = false;
    });
  }

  void _selectSearchResult(_SearchResult result) {
    final point = LatLng(result.latitude, result.longitude);
    _mapController.move(point, 16);
    setState(() {
      _center = point;
      _address = result.displayName;
      _searchResults = [];
      _searchController.clear();
    });
    FocusScope.of(context).unfocus();
  }

  void _clearSearch() {
    setState(() {
      _searchController.clear();
      _searchResults = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose Your Location'),
        backgroundColor: Colors.white,
        foregroundColor: kDarkText,
        elevation: 0,
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 15,
              onMapEvent: _onMapEvent,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.gharsewa.app',
              ),
            ],
          ),

          // Fixed center pin — the map moves underneath it, not the pin.
          IgnorePointer(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 36),
                child: Icon(Icons.location_on_rounded, color: kPrimaryGreen, size: 44),
              ),
            ),
          ),

          // Search box + results — type an area name and jump the map there.
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Column(
              children: [
                Material(
                  elevation: 3,
                  borderRadius: BorderRadius.circular(14),
                  child: TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: _performSearch,
                    decoration: InputDecoration(
                      hintText: 'Search for an area or place',
                      prefixIcon: const Icon(Icons.search_rounded, color: kPrimaryGreen),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: _clearSearch,
                      )
                          : null,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                if (_searching || _searchResults.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    constraints: const BoxConstraints(maxHeight: 240),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
                    ),
                    child: _searching
                        ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                        child: SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: kPrimaryGreen),
                        ),
                      ),
                    )
                        : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: _searchResults.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
                      itemBuilder: (context, index) {
                        final result = _searchResults[index];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.place_outlined, color: kPrimaryGreen),
                          title: Text(
                            result.displayName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                          onTap: () => _selectSearchResult(result),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          Positioned(
            right: 16,
            bottom: 168,
            child: FloatingActionButton(
              heroTag: 'use_device_location',
              backgroundColor: Colors.white,
              foregroundColor: kPrimaryGreen,
              onPressed: _locatingDevice ? null : () => _useDeviceLocation(),
              child: _locatingDevice
                  ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: kPrimaryGreen),
              )
                  : const Icon(Icons.my_location_rounded),
            ),
          ),

          // Resolved address + confirm button, docked to the bottom.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 12, offset: Offset(0, -2))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(Icons.location_on_outlined, size: 18, color: kPrimaryGreen),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _resolvingAddress
                            ? Text('Finding address...',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600))
                            : Text(
                          _address,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: kPrimaryGreen,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _resolvingAddress
                          ? null
                          : () => Navigator.pop(
                        context,
                        PickedLocation(
                          latitude: _center.latitude,
                          longitude: _center.longitude,
                          address: _address,
                        ),
                      ),
                      child: const Text('Confirm Location', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}