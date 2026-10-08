import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import '../main.dart';
import '../models/service_job.dart';
import '../models/service_rating.dart';
import '../services/api_config.dart';
import '../services/booking_service.dart';
import '../services/profile_service.dart';
import '../services/service_catalog_service.dart';
import '../services/service_rating_service.dart';
import '../widgets/profile_picture_picker.dart';
import '../widgets/notification_bell.dart';
import 'location_picker.dart';
import 'emergency_providers.dart';
import 'my_bookings.dart';
import 'login.dart';

class _Category {
  final String name;
  final IconData icon;
  const _Category(this.name, this.icon);
}

/// One hit in the home-screen search: either a whole service (job == null)
/// or a specific job under a service, which goes straight to that job's
/// booking sheet.
class _ServiceSearchResult {
  final String category;
  final ServiceJob? job;
  const _ServiceSearchResult(this.category, [this.job]);
}

class CustomerHomePage extends StatefulWidget {
  final String userName;
  final String userEmail;
  final String accessToken;

  const CustomerHomePage({
    super.key,
    required this.accessToken,
    this.userName = 'Guest User',
    this.userEmail = '',
  });

  @override
  State<CustomerHomePage> createState() => _CustomerHomePageState();
}

class _CustomerHomePageState extends State<CustomerHomePage> {
  int _navIndex = 0;
  static const int _profileTabIndex = 2;

  final _searchController = TextEditingController();
  List<_ServiceSearchResult> _searchResults = [];
  bool get _isSearching => _searchController.text.trim().isNotEmpty;

  final _categories = const [
    _Category('Electrical', Icons.lightbulb_outline_rounded),
    _Category('Cleaning', Icons.cleaning_services_outlined),
    _Category('Plumbing', Icons.plumbing_outlined),
    _Category('Painting', Icons.format_paint_outlined),
    _Category('Appliance Repair', Icons.local_laundry_service_outlined),
    _Category('Carpentry', Icons.handyman_outlined),
    _Category('Laundry', Icons.dry_cleaning_outlined),
    _Category('Pest Control', Icons.pest_control_outlined),
  ];

  // The priced service catalogue: every service, the specific jobs under
  // it, and what each job costs. Loaded from GET /api/services/catalog so
  // prices always come from the server; the local fallback below is only
  // used if that request fails, and never decides what a booking is
  // actually charged (the server prices the booking from its own copy).
  List<ServiceCatalogEntry> _catalog = ServiceCatalogService.fallbackCatalog;

  // Every bookable service, in the catalogue's own order.
  List<String> get _serviceNames => _catalog.map((e) => e.serviceCategory).toList();

  ServiceCatalogEntry? _entryFor(String categoryName) {
    for (final entry in _catalog) {
      if (entry.serviceCategory == categoryName) return entry;
    }
    return null;
  }

  /// The specific jobs under a service, each with its own price.
  List<ServiceJob> _jobsFor(String categoryName) =>
      _entryFor(categoryName)?.jobs ?? const <ServiceJob>[];

  // Overall rating of each service — a rating of the service as a whole,
  // never of an individual provider. Empty until loaded (or if loading
  // fails), in which case the rating line is simply not shown.
  List<ServiceRating> _serviceRatings = [];

  PickedLocation? _defaultLocation;
  String? _profilePictureUrl;

  Future<void> _loadServices() async {
    // getCatalogOrFallback() never throws — it falls back to a local copy
    // itself, so the services list always renders.
    final catalog = await ServiceCatalogService.getCatalogOrFallback(widget.accessToken);
    if (mounted && catalog.isNotEmpty) setState(() => _catalog = catalog);

    try {
      final ratings = await ServiceRatingService.getServiceRatings(widget.accessToken);
      if (!mounted) return;
      setState(() => _serviceRatings = ratings);
    } catch (_) {
      // Ratings are informational: if they can't load, services still work,
      // they just don't show a rating line.
    }
  }

  ServiceRating? _ratingFor(String categoryName) {
    for (final r in _serviceRatings) {
      if (r.serviceCategory == categoryName) return r;
    }
    return null;
  }

  IconData _iconFor(String categoryName) {
    for (final c in _categories) {
      if (c.name == categoryName) return c.icon;
    }
    return Icons.home_repair_service_outlined;
  }

  Future<void> _loadDefaultLocation() async {
    try {
      final profile = await ProfileService.getMyProfile(widget.accessToken);
      if (!mounted) return;
      setState(() {
        _profilePictureUrl = profile.profilePictureUrl;
        if (profile.latitude != null && profile.longitude != null && profile.address != null) {
          _defaultLocation = PickedLocation(
            latitude: profile.latitude!,
            longitude: profile.longitude!,
            address: profile.address!,
          );
        }
      });
    } catch (_) {
      // Default location/profile picture are conveniences, not critical —
      // fail silently and let the user just pick a location per-booking,
      // or see the placeholder avatar, as before.
    }
  }

  /// Full, absolute URL for the current profile picture, or null.
  String? get _profilePictureFullUrl =>
      _profilePictureUrl != null ? '$apiBaseUrl$_profilePictureUrl' : null;

  Future<String?> _uploadOwnProfilePicture(File file) async {
    final updated = await ProfileService.uploadProfilePicture(
      accessToken: widget.accessToken,
      file: file,
    );
    return updated.profilePictureUrl;
  }

  void _onProfilePictureUpdated(String? newUrl) {
    setState(() => _profilePictureUrl = newUrl);
  }

  Future<void> _setDefaultLocation() async {
    final result = await Navigator.push<PickedLocation>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerPage(
          initialLocation: _defaultLocation != null
              ? LatLng(_defaultLocation!.latitude, _defaultLocation!.longitude)
              : null,
        ),
      ),
    );
    if (result == null) return;

    setState(() => _defaultLocation = result);

    try {
      await ProfileService.updateDefaultLocation(
        accessToken: widget.accessToken,
        address: result.address,
        latitude: result.latitude,
        longitude: result.longitude,
      );
    } on ProfileServiceException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red.shade600),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save your default location.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadServices();
    _loadDefaultLocation();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _searchResults = [];
      } else {
        // Searches services and their jobs — never people.
        final results = <_ServiceSearchResult>[];
        for (final category in _serviceNames) {
          if (category.toLowerCase().contains(query)) {
            results.add(_ServiceSearchResult(category));
          }
          for (final job in _jobsFor(category)) {
            if (job.name.toLowerCase().contains(query) ||
                job.description.toLowerCase().contains(query)) {
              results.add(_ServiceSearchResult(category, job));
            }
          }
        }
        _searchResults = results;
      }
    });
  }

  /// Tapping a service shows the specific jobs under it first, by name
  /// only; picking a job opens the booking form, which is where its
  /// description and price are shown. The customer never chooses a provider
  /// — the server assigns one when the booking is created.
  void _openService(String categoryName) {
    final jobs = _jobsFor(categoryName);

    // A service with no listed jobs goes straight to booking.
    if (jobs.isEmpty) {
      _openBookingForm(serviceCategory: categoryName);
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ServiceJobsPage(
          categoryName: categoryName,
          jobs: jobs,
          icon: _iconFor(categoryName),
          rating: _ratingFor(categoryName),
          onSelectJob: (job) => _openBookingForm(serviceCategory: categoryName, job: job),
        ),
      ),
    );
  }

  void _openEmergencyProviders() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EmergencyProvidersPage(accessToken: widget.accessToken),
      ),
    );
  }

  void _openAllServices() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _AllServicesPage(
          services: _serviceNames,
          iconFor: _iconFor,
          ratingFor: _ratingFor,
          onSelect: _openService,
        ),
      ),
    );
  }

  /// [job] is the specific job being booked, where the customer picked one
  /// — its price is shown in the form and its name is sent with the
  /// booking. The price itself is never sent: the server prices the booking
  /// from its own catalogue.
  Future<void> _openBookingForm({required String serviceCategory, ServiceJob? job}) async {
    final jobTitle = job?.name;
    final pageContext = context; // survives after the sheet closes
    final problemDescriptionController = TextEditingController();
    final notesController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    DateTime? preferredDate;
    TimeOfDay? preferredTime;
    PickedLocation? pickedLocation = _defaultLocation;
    bool isSubmitting = false; // guards against double-tap firing two bookings
    bool isSubmitted = false; // true once the request succeeds; shows the brief confirmation
    // Shown inline in the sheet itself (see the banner just above the submit
    // button) rather than as a SnackBar on the page behind it — a SnackBar
    // attached to the page's Scaffold is covered by this modal bottom sheet,
    // so it only becomes visible once the sheet is dismissed (e.g. via the
    // back button), which made a "no provider available" failure look like
    // it silently did nothing until the customer backed out.
    String? errorMessage;

    await showModalBottomSheet(
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
                      decoration: const BoxDecoration(color: kLightGreenBg, shape: BoxShape.circle),
                      child: const Icon(Icons.check_rounded, color: kPrimaryGreen, size: 36),
                    ),
                    const SizedBox(height: 16),
                    const Text('Booking request sent!',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: kDarkText)),
                    const SizedBox(height: 6),
                    Text('Taking you to your bookings…',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                  ],
                ),
              );
            }
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
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      _ServiceHeroImage(
                        categoryName: serviceCategory,
                        icon: _iconFor(serviceCategory),
                        height: 220,
                        jobName: job?.name,
                      ),
                      const SizedBox(height: 16),
                      Text(jobTitle ?? serviceCategory,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: kDarkText)),
                      if (jobTitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          serviceCategory,
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                        ),
                      ],
                      // What the job involves and what it costs. This is the
                      // first place either appears: the services list shows
                      // only job names, so the customer gets the detail here,
                      // once they've picked one, and confirms the price as
                      // part of booking rather than discovering it later.
                      // Shown only when a specific job was picked — a
                      // category on its own has neither.
                      if (job != null) ...[
                        if (job.description.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            job.description,
                            style: TextStyle(fontSize: 13, height: 1.4, color: Colors.grey.shade700),
                          ),
                        ],
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: kLightGreenBg,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.payments_outlined, size: 20, color: kPrimaryGreen),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      job.priceLabel,
                                      style: const TextStyle(
                                          fontSize: 17, fontWeight: FontWeight.w700, color: kDarkText),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      job.priceNote,
                                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                    ),
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
                      // Wrapped in a FormField so a missing address is caught by
                      // formKey.currentState!.validate() along with every other
                      // required field, and shows an inline error message right
                      // under the picker instead of only a one-off snackbar.
                      FormField<PickedLocation>(
                        initialValue: pickedLocation,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        // Also reject a location whose address is still the
                        // picker's unresolved placeholder text — belt-and-
                        // suspenders in case the picker ever hands one back
                        // (e.g. a future regression re-opens that window),
                        // so a booking can never go out with a fake address.
                        validator: (value) {
                          if (value == null) return 'Please choose your location on the map';
                          if (value.address.trim().isEmpty ||
                              value.address == 'Move the map to choose a location') {
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
                                    border: Border.all(
                                      color: fieldState.hasError ? Colors.red.shade400 : Colors.grey.shade300,
                                    ),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(Icons.location_on_outlined,
                                          size: 18,
                                          color: pickedLocation != null ? kPrimaryGreen : Colors.grey.shade600),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          pickedLocation?.address ?? 'Choose your location on the map',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: pickedLocation != null ? kDarkText : Colors.grey.shade600,
                                          ),
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
                                  child: Text(
                                    fieldState.errorText!,
                                    style: TextStyle(color: Colors.red.shade600, fontSize: 12),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      const Text('Preferred Date & Time *',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: kDarkText)),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            // Own FormField so a missing date is caught by
                            // formKey.currentState!.validate() along with
                            // every other required field, with its own
                            // inline error instead of only a snackbar.
                            child: FormField<DateTime>(
                              initialValue: preferredDate,
                              autovalidateMode: AutovalidateMode.onUserInteraction,
                              validator: (value) => value == null ? 'Select a date' : null,
                              builder: (dateFieldState) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    InkWell(
                                      borderRadius: BorderRadius.circular(14),
                                      onTap: () async {
                                        final picked = await showDatePicker(
                                          context: context,
                                          initialDate: DateTime.now().add(const Duration(days: 1)),
                                          firstDate: DateTime.now(),
                                          lastDate: DateTime.now().add(const Duration(days: 90)),
                                        );
                                        if (picked != null) {
                                          setSheetState(() => preferredDate = picked);
                                          dateFieldState.didChange(picked);
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: dateFieldState.hasError
                                                ? Colors.red.shade400
                                                : Colors.grey.shade300,
                                          ),
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(Icons.calendar_today_outlined,
                                                size: 18, color: Colors.grey.shade600),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                preferredDate != null
                                                    ? '${preferredDate!.year}-${preferredDate!.month.toString().padLeft(2, '0')}-${preferredDate!.day.toString().padLeft(2, '0')}'
                                                    : 'Select a date',
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                    color: preferredDate != null
                                                        ? kDarkText
                                                        : Colors.grey.shade600),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (dateFieldState.hasError)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6, left: 4),
                                        child: Text(
                                          dateFieldState.errorText!,
                                          style: TextStyle(color: Colors.red.shade600, fontSize: 12),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FormField<TimeOfDay>(
                              initialValue: preferredTime,
                              autovalidateMode: AutovalidateMode.onUserInteraction,
                              validator: (value) {
                                if (value == null) return 'Select a time';
                                final minutesSinceMidnight = value.hour * 60 + value.minute;
                                const earliest = 8 * 60; // 8:00 AM
                                const latest = 17 * 60; // 5:00 PM
                                if (minutesSinceMidnight < earliest || minutesSinceMidnight > latest) {
                                  return 'Choose a time between 8:00 AM and 5:00 PM';
                                }
                                return null;
                              },
                              builder: (timeFieldState) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    InkWell(
                                      borderRadius: BorderRadius.circular(14),
                                      onTap: () async {
                                        final picked = await showTimePicker(
                                          context: context,
                                          initialTime: preferredTime ?? const TimeOfDay(hour: 9, minute: 0),
                                        );
                                        if (picked != null) {
                                          setSheetState(() => preferredTime = picked);
                                          timeFieldState.didChange(picked);
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: timeFieldState.hasError
                                                ? Colors.red.shade400
                                                : Colors.grey.shade300,
                                          ),
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(Icons.access_time_rounded,
                                                size: 18, color: Colors.grey.shade600),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                preferredTime != null
                                                    ? preferredTime!.format(context)
                                                    : 'Select time',
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                    color: preferredTime != null
                                                        ? kDarkText
                                                        : Colors.grey.shade600),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (timeFieldState.hasError)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6, left: 4),
                                        child: Text(
                                          timeFieldState.errorText!,
                                          style: TextStyle(color: Colors.red.shade600, fontSize: 12),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text('Problem Description *',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: kDarkText)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: problemDescriptionController,
                        maxLines: 3,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        validator: (value) {
                          final trimmed = value?.trim() ?? '';
                          if (trimmed.isEmpty) return 'Please describe the problem';
                          if (trimmed.length < 10) {
                            return 'Please add a few more details (at least 10 characters)';
                          }
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
                              Expanded(
                                child: Text(
                                  errorMessage!,
                                  style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: kPrimaryGreen,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: isSubmitting
                              ? null
                              : () async {
                            // Runs every field's validator (address, date, time,
                            // problem description) and, if any fails, stops the
                            // submit and shows each inline error instead of
                            // sending an incomplete request. Only notes is left
                            // out of this check because it's the one optional
                            // field.
                            if (!formKey.currentState!.validate()) return;
                            // Both guaranteed non-null here: validate() above
                            // only passes once each FormField's own validator
                            // (which rejects a null date/time) has passed.
                            final combinedDateTime = DateTime(
                              preferredDate!.year,
                              preferredDate!.month,
                              preferredDate!.day,
                              preferredTime!.hour,
                              preferredTime!.minute,
                            );
                            setSheetState(() {
                              isSubmitting = true;
                              errorMessage = null;
                            });
                            try {
                              await BookingService.createBooking(
                                accessToken: widget.accessToken,
                                address: pickedLocation!.address,
                                latitude: pickedLocation!.latitude,
                                longitude: pickedLocation!.longitude,
                                serviceCategory: serviceCategory,
                                jobTitle: jobTitle,
                                problemDescription: problemDescriptionController.text.trim(),
                                notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
                                preferredDate: combinedDateTime,
                              );
                              if (!sheetContext.mounted) return;
                              // Show the brief confirmation in place of the form first...
                              setSheetState(() => isSubmitted = true);
                              await Future.delayed(const Duration(milliseconds: 1100));
                              // ...then close the sheet and hand off to a fresh Booking List,
                              // which reloads from the server on its own, so it always shows
                              // the new request with its current status.
                              if (!sheetContext.mounted) return;
                              Navigator.pop(sheetContext);
                              if (!pageContext.mounted) return;
                              Navigator.push(
                                pageContext,
                                MaterialPageRoute(
                                  builder: (_) => MyBookingsPage(accessToken: widget.accessToken),
                                ),
                              );
                            } on BookingServiceException catch (e) {
                              if (!sheetContext.mounted) return;
                              setSheetState(() {
                                isSubmitting = false;
                                errorMessage = e.message;
                              });
                            } catch (_) {
                              // Any other failure (timeout, bad response, etc.) still has to
                              // re-enable the button — otherwise it's stuck disabled forever
                              // with no way to retry.
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
                              : const Text('Send Booking Request',
                              style: TextStyle(fontWeight: FontWeight.w600)),
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
  }

  void _onNavTap(int index) {
    if (index == _profileTabIndex) {
      _showProfileMenu(context);
      return; // keep current tab selected/highlighted; sheet is transient
    }
    if (index == 1) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => MyBookingsPage(accessToken: widget.accessToken)),
      );
      return; // transient navigation, keep current tab highlighted
    }
    setState(() => _navIndex = index);
  }

  void _showProfileMenu(BuildContext context) {
    final pageContext = context; // outer page context, stays valid after the sheet closes
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        // Wrapped in a StatefulBuilder so the avatar reflects a picture
        // change immediately, without needing to close and reopen the sheet.
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Row(
                        children: [
                          ProfilePictureAvatar(
                            radius: 26,
                            imageUrl: _profilePictureFullUrl,
                            uploadPicture: _uploadOwnProfilePicture,
                            onPictureUpdated: (newUrl) {
                              _onProfilePictureUpdated(newUrl);
                              setSheetState(() {});
                            },
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(widget.userName,
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                Text(widget.userEmail.isNotEmpty ? widget.userEmail : 'No email on file',
                                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 32),
                      _ProfileMenuTile(
                        icon: Icons.person_outline_rounded,
                        label: 'Edit Profile',
                        onTap: () {
                          Navigator.pop(context);
                          // TODO: navigate to edit profile page
                        },
                      ),
                      _ProfileMenuTile(
                        icon: Icons.help_outline_rounded,
                        label: 'Help & Support',
                        onTap: () {
                          Navigator.pop(context);
                          // TODO: navigate to help page
                        },
                      ),
                      _ProfileMenuTile(
                        icon: Icons.settings_outlined,
                        label: 'Settings',
                        onTap: () {
                          Navigator.pop(context);
                          // TODO: navigate to settings page
                        },
                      ),
                      const Divider(height: 24),
                      _ProfileMenuTile(
                        icon: Icons.logout_rounded,
                        label: 'Log Out',
                        isDestructive: true,
                        onTap: () {
                          Navigator.pop(context);
                          _confirmLogout(pageContext);
                        },
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade600),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      // TODO: clear auth session before navigating back
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage(role: UserRole.customer)),
            (route) => false,
      );
    }
  }

  // ── Header pieces ──────────────────────────────────────────────────

  Widget _buildLocationButton() {
    return InkWell(
      onTap: _setDefaultLocation,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.location_on_rounded, color: Colors.white, size: 17),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Your location',
                    style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.75)),
                  ),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          _defaultLocation?.address ?? 'Kathmandu, Nepal',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Colors.white),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationButton() {
    return NotificationBell(
      accessToken: widget.accessToken,
      size: 36,
      iconSize: 20,
    );
  }

  /// Compact avatar. Tapping opens the profile menu, which is where the
  /// picture can be changed (it holds the ProfilePictureAvatar uploader).
  Widget _buildProfileButton() {
    final url = _profilePictureFullUrl;
    return GestureDetector(
      onTap: () => _showProfileMenu(context),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        child: CircleAvatar(
          radius: 16,
          backgroundColor: kLightGreenBg,
          backgroundImage: url != null ? NetworkImage(url) : null,
          onBackgroundImageError: url != null ? (_, _) {} : null,
          child: url == null
              ? const Icon(Icons.person_rounded, color: kPrimaryGreen, size: 18)
              : null,
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 15, color: kDarkText),
        decoration: InputDecoration(
          hintText: 'Search for services...',
          hintStyle: TextStyle(fontSize: 15, color: Colors.grey.shade500),
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: 6),
            child: Icon(Icons.search_rounded, color: kPrimaryGreen),
          ),
          suffixIcon: _isSearching
              ? IconButton(
            icon: Icon(Icons.close_rounded, color: Colors.grey.shade600),
            onPressed: () => _searchController.clear(),
          )
              : null,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
        ),
      ),
    );
  }

  /// Compact green header: location, notifications and profile on one
  /// row, then the big heading and the search pill. The heading is hidden
  /// while searching so the results get the room.
  Widget _buildHeader(double topInset) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, topInset + 6, 20, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [kPrimaryGreen, kAccentGreen],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _buildLocationButton()),
              const SizedBox(width: 8),
              _buildNotificationButton(),
              const SizedBox(width: 10),
              _buildProfileButton(),
            ],
          ),
          if (!_isSearching) ...[
            const SizedBox(height: 12),
            const Text(
              'What service do you need today?',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                height: 1.2,
                letterSpacing: -0.2,
              ),
            ),
          ],
          SizedBox(height: _isSearching ? 12 : 14),
          _buildSearchBar(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Green header runs up under the status bar, so use light icons.
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F9F8),
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader(topInset)),

            const SliverToBoxAdapter(child: SizedBox(height: 18)),

            // ── Search results (shown only while typing) ──
            if (_isSearching) ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    '${_searchResults.length} result${_searchResults.length == 1 ? '' : 's'} found',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ),
              ),
              if (_searchResults.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      children: [
                        Icon(Icons.search_off_rounded, size: 40, color: Colors.grey.shade400),
                        const SizedBox(height: 8),
                        Text('No services match your search',
                            style: TextStyle(color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                          (context, index) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ServiceListTile(
                          title: _searchResults[index].job?.name ?? _searchResults[index].category,
                          subtitle: _searchResults[index].job != null ? _searchResults[index].category : null,
                          icon: _iconFor(_searchResults[index].category),
                          rating: _ratingFor(_searchResults[index].category),
                          jobName: _searchResults[index].job?.name,
                          onTap: () {
                            final result = _searchResults[index];
                            if (result.job != null) {
                              _openBookingForm(serviceCategory: result.category, job: result.job);
                            } else {
                              _openService(result.category);
                            }
                          },
                        ),
                      ),
                      childCount: _searchResults.length,
                    ),
                  ),
                ),
            ]

            // ── Normal home content (hidden while searching) ──
            else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                sliver: SliverToBoxAdapter(
                  child: InkWell(
                    onTap: _openEmergencyProviders,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.red.shade100),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
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
                                Text('Emergency Service', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kDarkText)),
                                SizedBox(height: 4),
                                Text('Find verified available providers near your current location', style: TextStyle(fontSize: 12, color: Colors.black54)),
                              ],
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios_rounded, size: 15, color: Colors.red),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text(
                        'Popular Services',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: kDarkText),
                      ),
                      TextButton(
                        onPressed: _openAllServices,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('View All',
                                style: TextStyle(color: kPrimaryGreen, fontWeight: FontWeight.w600)),
                            SizedBox(width: 2),
                            Icon(Icons.arrow_forward_ios_rounded, size: 12, color: kPrimaryGreen),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.82,
                  ),
                  delegate: SliverChildBuilderDelegate(
                        (context, index) => _CategoryTile(
                      category: _categories[index],
                      onTap: () => _openService(_categories[index].name),
                    ),
                    childCount: _categories.length,
                  ),
                ),
              ),
            ],
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _navIndex,
          onDestinationSelected: _onNavTap,
          backgroundColor: Colors.white,
          indicatorColor: kLightGreenBg,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded, color: kPrimaryGreen), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.calendar_today_outlined), selectedIcon: Icon(Icons.calendar_today_rounded, color: kPrimaryGreen), label: 'Bookings'),
            NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded, color: kPrimaryGreen), label: 'Profile'),
          ],
        ),
      ),
    );
  }
}

class _ProfileMenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  const _ProfileMenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? Colors.red.shade600 : kDarkText;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(width: 16),
            Text(label, style: TextStyle(fontSize: 15, color: color)),
          ],
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final _Category category;
  final VoidCallback onTap;
  const _CategoryTile({required this.category, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      // Green icon box + label, with no white card around them.
      // Anchored at the top with a fixed-height label area so every icon
      // sits at the same position, even when a name wraps to two lines
      // (e.g. "Appliance Repair").
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: kLightGreenBg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(category.icon, color: kPrimaryGreen, size: 26),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 30,
            child: Text(
              category.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: kDarkText,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Shared row-style card for a service — used by search results and the
// "All Services" page. Shows the service's overall rating, never a provider.
class _ServiceListTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final ServiceRating? rating;
  final VoidCallback onTap;

  /// Name of the specific job this tile represents — set only when this
  /// tile is a job (a "subcategory") rather than a whole service category,
  /// e.g. a job hit in search results. Null keeps the plain category icon
  /// this tile has always shown.
  final String? jobName;

  const _ServiceListTile({
    required this.title,
    required this.icon,
    required this.onTap,
    this.subtitle,
    this.rating,
    this.jobName,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade200),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            jobName != null
                ? _JobThumbnail(jobName: jobName!, icon: icon, size: 52)
                : Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(color: kLightGreenBg, shape: BoxShape.circle),
              child: Icon(icon, color: kPrimaryGreen),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    ),
                  ],
                  if (rating != null) ...[
                    const SizedBox(height: 4),
                    _ServiceRatingLine(rating: rating!),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}

/// Bundled photo for a specific job (a "subcategory"), keyed by the job's
/// exact name — same idea as the per-category hero images in
/// `assets/services/`, just in their own `assets/service-jobs/` folder and
/// keyed by job name rather than derived from it, since a curated photo's
/// filename doesn't follow a fixed pattern the way a category slug does.
///
/// Not every job has a photo yet — [_JobThumbnail] and [_ServiceHeroImage]
/// fall back to a plain icon for any job not listed here. Add a new job's
/// entry here once its photo is dropped into `assets/service-jobs/` and
/// declared in pubspec.yaml.
const Map<String, String> _jobAssetPaths = {
  // Cleaning
  'Room Cleaning': 'assets/service-jobs/room_cleaning.png',
  'Deep House Cleaning': 'assets/service-jobs/deep_cleaning.png',
  'Bathroom & Kitchen Cleaning': 'assets/service-jobs/bathroom_kitchen_cleaning.png',
  'Sofa & Carpet Cleaning': 'assets/service-jobs/sofa_carpet_cleaning.png',
  // Plumbing
  'Leak & Pipe Repair': 'assets/service-jobs/leak_and_pipe_repair.png',
  'Tap & Fixture Installation': 'assets/service-jobs/tap_installation.png',
  'Water Tank Cleaning': 'assets/service-jobs/water_tank_cleaning.png',
  // Electrical
  'Fan Installation': 'assets/service-jobs/fan_installation.png',
  'Switchboard & Socket Repair': 'assets/service-jobs/switchboard_and_socket_repair.png',
  'Light Fitting Installation': 'assets/service-jobs/light_fitting.png',
  'Wiring & Rewiring': 'assets/service-jobs/wiring.png',
  // Carpentry
  'Furniture Repair': 'assets/service-jobs/furniture_repair.png',
  'Door & Window Fitting': 'assets/service-jobs/door_fitting.png',
  'Custom Furniture Assembly': 'assets/service-jobs/custom_furniture.png',
  // Painting
  'Interior Wall Painting': 'assets/service-jobs/interior_wall_painting.png',
  'Exterior Wall Painting': 'assets/service-jobs/exterior_wall_painting.png',
  'Waterproofing & Wall Repair': 'assets/service-jobs/waterproofing.png',
  // Appliance Repair
  'Washing Machine Repair': 'assets/service-jobs/washing_machine_repair.png',
  'Refrigerator Repair': 'assets/service-jobs/refrigerator_repair.png',
  'Microwave & Oven Repair': 'assets/service-jobs/microwave_repair.png',
  // Laundry
  'Wash & Fold': 'assets/service-jobs/wash_and_fold.png',
  'Dry Cleaning': 'assets/service-jobs/dry_cleaning.png',
  'Ironing & Pressing': 'assets/service-jobs/ironing.png',
  // Pest Control — no bundled photos yet; falls back to the category
  // banner / icon tile until photos are added.
};

/// Banner photo for a service, loaded from `assets/services/<service>.jpg`
/// (e.g. Cleaning -> cleaning.jpg, Appliance Repair -> appliance_repair.jpg,
/// Pest Control -> pest_control.jpg). If a photo is missing, it falls
/// back to a plain tile with the service's icon instead of breaking the page.
class _ServiceHeroImage extends StatelessWidget {
  final String categoryName;
  final IconData icon;
  final double height;

  /// Name of the specific job being shown, if any — looked up in
  /// [_jobAssetPaths] for a curated bundled photo. Takes priority over the
  /// generic category shot when the job has one.
  final String? jobName;

  const _ServiceHeroImage({
    required this.categoryName,
    required this.icon,
    this.height = 160,
    this.jobName,
  });

  static String pathFor(String categoryName) {
    final slug = categoryName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return 'assets/services/$slug.jpg';
  }

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      color: kLightGreenBg,
      alignment: Alignment.center,
      child: Icon(icon, size: 48, color: kPrimaryGreen),
    );
    final categoryImage = Image.asset(
      pathFor(categoryName),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => fallback,
    );
    final jobAssetPath = jobName != null ? _jobAssetPaths[jobName] : null;
    final image = jobAssetPath != null
        ? Image.asset(
      jobAssetPath,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => categoryImage,
    )
        : categoryImage;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: image,
      ),
    );
  }
}

/// A service job's own image, shown consistently wherever a specific job
/// (a "subcategory") is listed on its own — the jobs list under a
/// category, and job hits in search results.
///
/// Prefers a curated bundled photo (see [_jobAssetPaths]) when the job has
/// one; otherwise falls back to a plain icon tile — the same layering
/// [_ServiceHeroImage] uses for the larger hero version of the same image.
class _JobThumbnail extends StatelessWidget {
  final String jobName;
  final IconData icon;
  final double size;

  const _JobThumbnail({
    required this.jobName,
    required this.icon,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size / 3.5);
    final fallback = Container(
      decoration: BoxDecoration(color: kLightGreenBg, borderRadius: radius),
      alignment: Alignment.center,
      child: Icon(icon, color: kPrimaryGreen, size: size * 0.5),
    );
    final jobAssetPath = _jobAssetPaths[jobName];
    final image = jobAssetPath != null
        ? Image.asset(
      jobAssetPath,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => fallback,
    )
        : fallback;
    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: size,
        height: size,
        child: image,
      ),
    );
  }
}

/// "★ 4.6 (23 reviews)" for a rated service, a greyed "No ratings yet" otherwise.
class _ServiceRatingLine extends StatelessWidget {
  final ServiceRating rating;
  const _ServiceRatingLine({required this.rating});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          rating.hasReviews ? Icons.star_rounded : Icons.star_border_rounded,
          size: 15,
          color: rating.hasReviews ? Colors.amber : Colors.grey.shade400,
        ),
        const SizedBox(width: 3),
        Text(
          rating.label,
          style: TextStyle(
            fontSize: 12,
            color: rating.hasReviews ? null : Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}

// ── Category tap → 2–3 specific jobs under that category ──
class _ServiceJobsPage extends StatelessWidget {
  final String categoryName;
  final List<ServiceJob> jobs;
  final IconData icon;
  final ServiceRating? rating;
  final ValueChanged<ServiceJob> onSelectJob;

  const _ServiceJobsPage({
    required this.categoryName,
    required this.jobs,
    required this.icon,
    required this.onSelectJob,
    this.rating,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(categoryName),
        backgroundColor: Colors.white,
        foregroundColor: kDarkText,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _ServiceHeroImage(categoryName: categoryName, icon: icon, height: 220),
          const SizedBox(height: 16),
          if (rating != null) ...[
            Text(
              'Overall service rating',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 4),
            _ServiceRatingLine(rating: rating!),
            const SizedBox(height: 20),
          ],
          const Text(
            'What do you need help with?',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kDarkText),
          ),
          const SizedBox(height: 4),
          Text(
            'Pick the job that matches your need best.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          if (jobs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No specific jobs are listed for $categoryName yet.',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            )
          else
            ...jobs.map(
                  (job) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => onSelectJob(job),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade200),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    // Just the job's name here — what it involves and what
                    // it costs are shown once the customer taps through to
                    // the booking sheet, so this list stays scannable.
                    child: Row(
                      children: [
                        _JobThumbnail(
                          jobName: job.name,
                          icon: Icons.build_outlined,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(job.name,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        ),
                        Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── "View All" / "More" → every service, each with its overall rating ──
class _AllServicesPage extends StatelessWidget {
  final List<String> services;
  final IconData Function(String categoryName) iconFor;
  final ServiceRating? Function(String categoryName) ratingFor;
  final ValueChanged<String> onSelect;

  const _AllServicesPage({
    required this.services,
    required this.iconFor,
    required this.ratingFor,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('All Services'),
        backgroundColor: Colors.white,
        foregroundColor: kDarkText,
        elevation: 0,
      ),
      body: services.isEmpty
          ? Center(
        child: Text(
          'No services available yet.',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        ),
      )
          : ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: services.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final name = services[index];
          return _ServiceListTile(
            title: name,
            icon: iconFor(name),
            rating: ratingFor(name),
            onTap: () => onSelect(name),
          );
        },
      ),
    );
  }
}