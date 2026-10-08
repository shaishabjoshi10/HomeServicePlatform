import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../main.dart';
import '../models/emergency_provider.dart';
import '../models/service_job.dart';
import '../services/api_config.dart';
import '../services/emergency_provider_service.dart';
import '../services/booking_service.dart';
import '../services/service_catalog_service.dart';
import '../utils/device_location.dart';
import '../models/booking.dart';
import 'booking_details_page.dart';
import 'location_picker.dart';

class EmergencyProvidersPage extends StatefulWidget {
  final String accessToken;

  const EmergencyProvidersPage({
    super.key,
    required this.accessToken,
  });

  @override
  State<EmergencyProvidersPage> createState() => _EmergencyProvidersPageState();
}

class _EmergencyProvidersPageState extends State<EmergencyProvidersPage> {
  static const _categories = <_EmergencyCategory>[
    _EmergencyCategory('Plumbing', Icons.plumbing_outlined),
    _EmergencyCategory('Electrical', Icons.electrical_services_outlined),
  ];

  String? _selectedCategory;
  Position? _position;
  List<EmergencyProvider> _providers = const [];
  bool _loadingLocation = true;
  bool _searching = false;
  bool _submitting = false;
  String? _error;
  int _searchToken = 0;
  List<ServiceCatalogEntry> _catalog = ServiceCatalogService.fallbackCatalog;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadCurrentLocation();
    _loadCatalog();
    // Providers switch availability on and off and move around, so keep the
    // live list current without the customer having to pull to refresh.
    _refreshTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted && !_submitting && !_searching && _selectedCategory != null) {
        _findProviders(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    final catalog = await ServiceCatalogService.getCatalogOrFallback(widget.accessToken);
    if (!mounted) return;
    setState(() => _catalog = catalog);
  }

  List<ServiceJob> _jobsFor(String category) {
    for (final entry in _catalog) {
      if (entry.serviceCategory == category) return entry.jobs;
    }
    return const [];
  }

  Future<void> _loadCurrentLocation() async {
    setState(() {
      _loadingLocation = true;
      _error = null;
    });

    try {
      // A customer indoors may only have a slightly older fix; allow a bit
      // more than the provider side, which must always be fresh.
      final position = await DeviceLocation.getBest(
        maxLastKnownAge: const Duration(minutes: 5),
      );

      if (!mounted) return;
      setState(() {
        _position = position;
        _loadingLocation = false;
      });

      if (_selectedCategory != null) {
        await _findProviders();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingLocation = false;
        _error = e.toString().replaceFirst('Exception: ', '');
        _providers = const [];
      });
    }
  }

  Future<void> _selectCategory(String category) async {
    setState(() {
      _selectedCategory = category;
      _providers = const [];
      _error = null;
    });
    if (_position == null) {
      await _loadCurrentLocation();
      return;
    }
    await _findProviders();
  }

  /// [silent] refreshes in the background: no spinner, and a failed refresh
  /// keeps showing the last list instead of replacing it with an error.
  Future<void> _findProviders({bool silent = false}) async {
    final position = _position;
    final category = _selectedCategory;
    if (position == null || category == null) return;

    final token = ++_searchToken;
    if (!silent) {
      setState(() {
        _searching = true;
        _error = null;
      });
    }

    try {
      final providers = await EmergencyProviderService.findNearby(
        accessToken: widget.accessToken,
        serviceCategory: category,
        latitude: position.latitude,
        longitude: position.longitude,
      );
      // Ignore a slow response for a category the user has since left.
      if (!mounted || token != _searchToken) return;
      setState(() {
        _providers = providers;
        _searching = false;
        _error = null;
      });
    } on EmergencyProviderServiceException catch (e) {
      if (!mounted || token != _searchToken) return;
      if (silent) return;
      setState(() {
        _providers = const [];
        _searching = false;
        _error = e.message;
      });
    }
  }

  Future<String> _resolveAddress(double lat, double lon) async {
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
            '?format=json&lat=$lat&lon=$lon&zoom=18&addressdetails=0',
      );
      final response = await http
          .get(uri, headers: {'User-Agent': 'GharSewaApp/1.0'})
          .timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final name = (data['display_name'] as String?)?.trim();
        if (name != null && name.isNotEmpty) {
          return name.length > 480 ? name.substring(0, 480) : name;
        }
      }
    } catch (_) {
      // fall through to the coordinate label
    }
    return '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}';
  }

  /// Opens the emergency booking form. It mirrors the normal booking form
  /// (service + price card, address, preferred time, problem description,
  /// notes) so both flows collect and show the same booking details. The only
  /// difference is the time: an emergency is always "as soon as possible".
  Future<void> _requestEmergency(EmergencyProvider provider) async {
    if (_submitting) return;
    final position = _position;
    if (position == null) return;

    // Resolve the address first so the form opens with it already filled in,
    // exactly like the normal form opens with the customer's saved address.
    setState(() => _submitting = true);
    final address = await _resolveAddress(position.latitude, position.longitude);
    if (!mounted) return;
    setState(() => _submitting = false);

    final jobs = _jobsFor(provider.serviceCategory);
    final problemController = TextEditingController();
    final notesController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    ServiceJob? selectedJob = jobs.isNotEmpty ? jobs.first : null;
    PickedLocation? pickedLocation = PickedLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      address: address,
    );
    bool isSubmitting = false;
    bool isSubmitted = false;
    String? errorMessage;
    final pageContext = context;

    final booking = await showModalBottomSheet<Booking>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            if (isSubmitted) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
                      child: Icon(Icons.check_rounded, color: Colors.red.shade600, size: 36),
                    ),
                    const SizedBox(height: 16),
                    const Text('Emergency request sent!',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: kDarkText)),
                    const SizedBox(height: 6),
                    Text('Opening your booking…', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                  ],
                ),
              );
            }

            final job = selectedJob;
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 12,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(job?.name ?? provider.serviceCategory,
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: kDarkText)),
                                if (job != null) ...[
                                  const SizedBox(height: 2),
                                  Text(provider.serviceCategory,
                                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                                ],
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(20)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.emergency_rounded, size: 12, color: Colors.red.shade700),
                                const SizedBox(width: 3),
                                Text('EMERGENCY',
                                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.red.shade700)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text('What do you need done? *',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: kDarkText)),
                      const SizedBox(height: 8),
                      for (final j in jobs)
                        Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            color: j.name == job?.name ? kLightGreenBg : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: j.name == job?.name ? kPrimaryGreen : Colors.grey.shade300),
                          ),
                          child: ListTile(
                            dense: true,
                            onTap: () => setSheetState(() {
                              selectedJob = j;
                              errorMessage = null;
                            }),
                            title: Text(j.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            trailing: j.name == job?.name
                                ? const Icon(Icons.check_circle_rounded, color: kPrimaryGreen)
                                : Icon(Icons.circle_outlined, color: Colors.grey.shade400),
                          ),
                        ),
                      if (jobs.isEmpty)
                        Text('Services could not be loaded. Close this and try again.',
                            style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
                      // Same description + price card as the normal booking form.
                      if (job != null) ...[
                        if (job.description.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(job.description,
                              style: TextStyle(fontSize: 13, height: 1.4, color: Colors.grey.shade700)),
                        ],
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(color: kLightGreenBg, borderRadius: BorderRadius.circular(14)),
                          child: Row(
                            children: [
                              const Icon(Icons.payments_outlined, size: 20, color: kPrimaryGreen),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(job.priceLabel,
                                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: kDarkText)),
                                    const SizedBox(height: 2),
                                    Text(job.priceNote, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      const Text('Address *',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: kDarkText)),
                      const SizedBox(height: 8),
                      FormField<PickedLocation>(
                        initialValue: pickedLocation,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        validator: (value) {
                          if (value == null) return 'Please choose your location on the map';
                          if (value.address.trim().isEmpty || value.address == 'Move the map to choose a location') {
                            return 'Please wait for your address to load, then confirm it';
                          }
                          return null;
                        },
                        builder: (fieldState) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () async {
                                  final result = await Navigator.push<PickedLocation>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => LocationPickerPage(
                                        initialLocation: pickedLocation != null
                                            ? LatLng(pickedLocation!.latitude, pickedLocation!.longitude)
                                            : null,
                                      ),
                                    ),
                                  );
                                  if (result != null) {
                                    setSheetState(() => pickedLocation = result);
                                    fieldState.didChange(result);
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: fieldState.hasError ? Colors.red.shade400 : Colors.grey.shade300),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(Icons.location_on_outlined,
                                          size: 18, color: pickedLocation != null ? kPrimaryGreen : Colors.grey.shade600),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          pickedLocation?.address ?? 'Choose your location on the map',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(color: pickedLocation != null ? kDarkText : Colors.grey.shade600),
                                        ),
                                      ),
                                      Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
                                    ],
                                  ),
                                ),
                              ),
                              if (fieldState.hasError)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6, left: 4),
                                  child: Text(fieldState.errorText!,
                                      style: TextStyle(color: Colors.red.shade600, fontSize: 12)),
                                ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      const Text('Preferred Date & Time',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: kDarkText)),
                      const SizedBox(height: 8),
                      // Fixed for emergencies: the request goes out right now.
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          border: Border.all(color: Colors.red.shade100),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.bolt_rounded, size: 18, color: Colors.red.shade700),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text('As soon as possible (emergency)',
                                  style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('Problem Description *',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: kDarkText)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: problemController,
                        maxLines: 3,
                        maxLength: 1000,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        validator: (value) {
                          final trimmed = value?.trim() ?? '';
                          if (trimmed.isEmpty) return 'Please describe the problem';
                          if (trimmed.length < 10) return 'Please add a few more details (at least 10 characters)';
                          return null;
                        },
                        decoration: InputDecoration(
                          hintText: 'What do you need help with? e.g. Leaking kitchen tap',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('Additional Notes (optional)',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: kDarkText)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: notesController,
                        maxLines: 3,
                        maxLength: 1000,
                        decoration: InputDecoration(
                          hintText: 'Anything else the professional should know...',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                      ),
                      if (errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.error_outline, color: Colors.red.shade600, size: 20),
                              const SizedBox(width: 10),
                              Expanded(child: Text(errorMessage!, style: TextStyle(color: Colors.red.shade700, fontSize: 13))),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red.shade600,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: isSubmitting
                              ? null
                              : () async {
                            if (selectedJob == null) {
                              setSheetState(() => errorMessage = 'Please choose what you need done.');
                              return;
                            }
                            if (!formKey.currentState!.validate()) return;
                            setSheetState(() {
                              isSubmitting = true;
                              errorMessage = null;
                            });
                            try {
                              final notes = notesController.text.trim();
                              final created = await BookingService.createEmergencyBooking(
                                accessToken: widget.accessToken,
                                providerId: provider.userId,
                                serviceCategory: provider.serviceCategory,
                                jobTitle: selectedJob!.name,
                                address: pickedLocation!.address,
                                latitude: pickedLocation!.latitude,
                                longitude: pickedLocation!.longitude,
                                problemDescription: problemController.text.trim(),
                                notes: notes.isEmpty ? null : notes,
                              );
                              if (!sheetContext.mounted) return;
                              setSheetState(() => isSubmitted = true);
                              await Future.delayed(const Duration(milliseconds: 1100));
                              if (!sheetContext.mounted) return;
                              Navigator.pop(sheetContext, created);
                            } on BookingServiceException catch (e) {
                              if (!sheetContext.mounted) return;
                              setSheetState(() {
                                isSubmitting = false;
                                errorMessage = e.message;
                              });
                            } catch (_) {
                              if (!sheetContext.mounted) return;
                              setSheetState(() {
                                isSubmitting = false;
                                errorMessage = 'Something went wrong. Please try again.';
                              });
                            }
                          },
                          child: isSubmitting
                              ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                          )
                              : const Text('Send Emergency Request', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    problemController.dispose();
    notesController.dispose();

    if (booking == null) {
      // Sheet dismissed. If it was a failure such as the provider becoming
      // unavailable, the list may be stale, so refresh it.
      if (pageContext.mounted) await _findProviders();
      return;
    }
    if (!pageContext.mounted) return;
    // Replace this page so Back returns to the home screen instead of a
    // stale provider list that could be used to send a duplicate request.
    await Navigator.pushReplacement(
      pageContext,
      MaterialPageRoute(
        builder: (_) => BookingDetailsPage(accessToken: widget.accessToken, booking: booking),
      ),
    );
  }

  IconData _iconFor(String category) {
    for (final item in _categories) {
      if (item.name == category) return item.icon;
    }
    return Icons.home_repair_service_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F8),
      appBar: AppBar(
        title: const Text('Emergency Services'),
        backgroundColor: Colors.white,
        foregroundColor: kDarkText,
        elevation: 0,
      ),
      body: RefreshIndicator(
        // _loadCurrentLocation re-runs the provider search itself.
        onRefresh: _loadCurrentLocation,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
          children: [
            if (_submitting) ...[
              const LinearProgressIndicator(color: Colors.red, minHeight: 3),
              const SizedBox(height: 12),
            ],
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.red.shade100),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.emergency_rounded, color: Colors.red.shade700),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Need help right now?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                        SizedBox(height: 4),
                        Text('Choose a service. We will show verified providers who are available nearby.'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            const Text('Choose a service', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: kDarkText)),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _categories.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.7,
              ),
              itemBuilder: (_, index) {
                final item = _categories[index];
                final selected = item.name == _selectedCategory;
                return InkWell(
                  onTap: _loadingLocation ? null : () => _selectCategory(item.name),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: selected ? kLightGreenBg : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: selected ? kPrimaryGreen : Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(item.icon, color: selected ? kPrimaryGreen : Colors.grey.shade700),
                        const SizedBox(width: 8),
                        Expanded(child: Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            if (_loadingLocation)
              const _StatusCard(icon: Icons.my_location_rounded, message: 'Getting your current location...')
            else if (_error != null)
              _ErrorCard(message: _error!, onRetry: _loadCurrentLocation)
            else if (_selectedCategory == null)
                const _StatusCard(icon: Icons.touch_app_outlined, message: 'Select a service to find nearby providers.')
              else if (_searching)
                  const _StatusCard(icon: Icons.search_rounded, message: 'Finding available providers near you...')
                else if (_providers.isEmpty)
                    _StatusCard(
                      icon: Icons.person_search_outlined,
                      message: 'No verified ${_selectedCategory!} providers are currently available within 10 km.',
                    )
                  else ...[
                      Text(
                        '${_providers.length} available ${_selectedCategory!} provider${_providers.length == 1 ? '' : 's'}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: kDarkText),
                      ),
                      const SizedBox(height: 12),
                      ..._providers.map(_buildProviderCard),
                    ],
          ],
        ),
      ),
    );
  }

  Widget _buildProviderCard(EmergencyProvider provider) {
    final imageUrl = provider.profilePictureUrl == null ? null : '$apiBaseUrl${provider.profilePictureUrl}';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: kLightGreenBg,
            backgroundImage: imageUrl != null ? NetworkImage(imageUrl) : null,
            child: imageUrl == null ? const Icon(Icons.person_rounded, color: kPrimaryGreen, size: 28) : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(provider.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                      decoration: BoxDecoration(color: kLightGreenBg, borderRadius: BorderRadius.circular(20)),
                      child: const Text('AVAILABLE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: kPrimaryGreen)),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Icon(_iconFor(provider.serviceCategory), size: 14, color: kPrimaryGreen),
                    const SizedBox(width: 5),
                    Text(provider.serviceCategory, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                    const SizedBox(width: 10),
                    Icon(Icons.near_me_outlined, size: 14, color: Colors.grey.shade600),
                    const SizedBox(width: 3),
                    Text('${provider.distanceKm.toStringAsFixed(1)} km away', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                  ],
                ),
                if (provider.experience?.isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text('${provider.experience} experience', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ],
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _submitting ? null : () => _requestEmergency(provider),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red.shade600,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    icon: const Icon(Icons.emergency_rounded, size: 17),
                    label: const Text('Request This Provider'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmergencyCategory {
  final String name;
  final IconData icon;
  const _EmergencyCategory(this.name, this.icon);
}

class _StatusCard extends StatelessWidget {
  final IconData icon;
  final String message;
  const _StatusCard({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.grey.shade200)),
    child: Column(
      children: [
        Icon(icon, size: 34, color: kPrimaryGreen),
        const SizedBox(height: 10),
        Text(message, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
      ],
    ),
  );
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.red.shade100)),
    child: Column(
      children: [
        Icon(Icons.location_off_outlined, size: 34, color: Colors.red.shade600),
        const SizedBox(height: 10),
        Text(message, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
        const SizedBox(height: 10),
        TextButton(onPressed: onRetry, child: const Text('Try Again')),
      ],
    ),
  );
}