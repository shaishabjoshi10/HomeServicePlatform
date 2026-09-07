import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../main.dart';
import '../models/customer_profile.dart';
import '../models/provider_profile.dart';
import '../services/booking_service.dart';
import '../services/profile_service.dart';
import '../services/provider_service.dart';
import 'location_picker.dart';
import 'my_bookings.dart';
import 'role_selection.dart';

class _Category {
  final String name;
  final IconData icon;
  const _Category(this.name, this.icon);
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
  static const int _profileTabIndex = 4;

  final _searchController = TextEditingController();
  List<ProviderProfile> _searchResults = [];
  bool get _isSearching => _searchController.text.trim().isNotEmpty;

  final _categories = const [
    _Category('Cleaning', Icons.cleaning_services_outlined),
    _Category('Plumbing', Icons.plumbing_outlined),
    _Category('Electrical', Icons.lightbulb_outline_rounded),
    _Category('Carpentry', Icons.handyman_outlined),
    _Category('Painting', Icons.format_paint_outlined),
    _Category('Appliance Repair', Icons.local_laundry_service_outlined),
    _Category('Pest Control', Icons.pest_control_outlined),
    _Category('More', Icons.more_horiz_rounded),
  ];

  List<ProviderProfile> _professionals = [];
  bool _loadingProfessionals = true;
  String? _professionalsError;

  PickedLocation? _defaultLocation;

  Future<void> _loadProfessionals() async {
    setState(() {
      _loadingProfessionals = true;
      _professionalsError = null;
    });

    try {
      final providers = await ProviderService.listProviders(verifiedOnly: false);
      if (!mounted) return;
      setState(() {
        _professionals = providers;
        _loadingProfessionals = false;
      });
    } on ProviderServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _professionalsError = e.message;
        _loadingProfessionals = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _professionalsError = 'Something went wrong loading service providers.';
        _loadingProfessionals = false;
      });
    }
  }

  Future<void> _loadDefaultLocation() async {
    try {
      final profile = await ProfileService.getMyProfile(widget.accessToken);
      if (!mounted) return;
      if (profile.latitude != null && profile.longitude != null && profile.address != null) {
        setState(() {
          _defaultLocation = PickedLocation(
            latitude: profile.latitude!,
            longitude: profile.longitude!,
            address: profile.address!,
          );
        });
      }
    } catch (_) {
      // Default location is a convenience, not critical — fail silently and
      // let the user just pick a location per-booking as before.
    }
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

  Widget _buildProfessionalsList() {
    if (_loadingProfessionals) {
      return const Center(
        child: SizedBox(
          height: 24,
          width: 24,
          child: CircularProgressIndicator(strokeWidth: 2, color: kPrimaryGreen),
        ),
      );
    }

    if (_professionalsError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _professionalsError!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: _loadProfessionals,
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                child: const Text('Retry', style: TextStyle(color: kPrimaryGreen, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      );
    }

    if (_professionals.isEmpty) {
      return Center(
        child: Text(
          'No service providers yet.',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      scrollDirection: Axis.horizontal,
      itemCount: _professionals.length,
      separatorBuilder: (_, __) => const SizedBox(width: 12),
      itemBuilder: (context, index) {
        final p = _professionals[index];
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openBookingForm(p),
          child: Container(
            width: 150,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade200),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircleAvatar(
                  radius: 20,
                  backgroundColor: kLightGreenBg,
                  child: Icon(Icons.person_rounded, color: kPrimaryGreen),
                ),
                const SizedBox(height: 8),
                Text(
                  p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                Text(
                  p.displayRole,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.star_rounded, size: 14, color: Colors.amber),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        '${p.rating.toStringAsFixed(1)} (${p.reviewsCount})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadProfessionals();
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
        _searchResults = _professionals.where((p) {
          return p.name.toLowerCase().contains(query) ||
              p.displayRole.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  void _openCategoryResults(String categoryName) {
    if (categoryName == 'More') return;
    final results = _professionals.where((p) => p.serviceCategory == categoryName).toList();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _CategoryResultsPage(
          categoryName: categoryName,
          providers: results,
          onBook: _openBookingForm,
        ),
      ),
    );
  }

  void _openAllServices() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _AllServicesPage(providers: _professionals, onBook: _openBookingForm),
      ),
    );
  }

  void _openAllProfessionals() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _AllProfessionalsPage(professionals: _professionals, onBook: _openBookingForm),
      ),
    );
  }

  Future<void> _openBookingForm(ProviderProfile provider) async {
    final pageContext = context; // survives after the sheet closes
    final notesController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    DateTime? preferredDate;
    TimeOfDay? preferredTime;
    PickedLocation? pickedLocation = _defaultLocation;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
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
                      Text('Book ${provider.name}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: kDarkText)),
                      const SizedBox(height: 2),
                      Text(provider.displayRole, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                      const SizedBox(height: 20),
                      const Text('Address',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: kDarkText)),
                      const SizedBox(height: 8),
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
                          if (result != null) setSheetState(() => pickedLocation = result);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
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
                      const SizedBox(height: 16),
                      const Text('Preferred Date & Time (optional)',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: kDarkText)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: DateTime.now().add(const Duration(days: 1)),
                                  firstDate: DateTime.now(),
                                  lastDate: DateTime.now().add(const Duration(days: 90)),
                                );
                                if (picked != null) setSheetState(() => preferredDate = picked);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.calendar_today_outlined, size: 18, color: Colors.grey.shade600),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        preferredDate != null
                                            ? '${preferredDate!.year}-${preferredDate!.month.toString().padLeft(2, '0')}-${preferredDate!.day.toString().padLeft(2, '0')}'
                                            : 'Select a date',
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: preferredDate != null ? kDarkText : Colors.grey.shade600),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () async {
                                final picked = await showTimePicker(
                                  context: context,
                                  initialTime: preferredTime ?? const TimeOfDay(hour: 9, minute: 0),
                                );
                                if (picked != null) setSheetState(() => preferredTime = picked);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.access_time_rounded, size: 18, color: Colors.grey.shade600),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        preferredTime != null ? preferredTime!.format(context) : 'Select time',
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: preferredTime != null ? kDarkText : Colors.grey.shade600),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text('Notes (optional)',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: kDarkText)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: notesController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: 'Describe what you need...',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: kPrimaryGreen,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: () async {
                            if (!formKey.currentState!.validate()) return;
                            if (pickedLocation == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Please choose your location on the map')),
                              );
                              return;
                            }
                            if (preferredTime != null && preferredDate == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Please also select a date for that time')),
                              );
                              return;
                            }
                            final DateTime? combinedDateTime = preferredDate == null
                                ? null
                                : DateTime(
                              preferredDate!.year,
                              preferredDate!.month,
                              preferredDate!.day,
                              preferredTime?.hour ?? 9,
                              preferredTime?.minute ?? 0,
                            );
                            try {
                              await BookingService.createBooking(
                                accessToken: widget.accessToken,
                                providerId: provider.userId,
                                address: pickedLocation!.address,
                                latitude: pickedLocation!.latitude,
                                longitude: pickedLocation!.longitude,
                                serviceCategory: provider.serviceCategory,
                                notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
                                preferredDate: combinedDateTime,
                              );
                              Navigator.pop(sheetContext);
                              if (pageContext.mounted) {
                                ScaffoldMessenger.of(pageContext).showSnackBar(
                                  SnackBar(
                                    content: const Text('Booking request sent!'),
                                    backgroundColor: kPrimaryGreen,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            } on BookingServiceException catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(e.message),
                                    backgroundColor: Colors.red.shade600,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            }
                          },
                          child: const Text('Send Booking Request',
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
                      Container(
                        width: 52,
                        height: 52,
                        decoration: const BoxDecoration(color: kLightGreenBg, shape: BoxShape.circle),
                        child: const Icon(Icons.person_rounded, color: kPrimaryGreen, size: 28),
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
                    icon: Icons.calendar_today_outlined,
                    label: 'My Bookings',
                    onTap: () {
                      Navigator.pop(context);
                      // TODO: navigate to bookings page
                    },
                  ),
                  _ProfileMenuTile(
                    icon: Icons.location_on_outlined,
                    label: 'Saved Addresses',
                    onTap: () {
                      Navigator.pop(context);
                      // TODO: navigate to addresses page
                    },
                  ),
                  _ProfileMenuTile(
                    icon: Icons.payment_outlined,
                    label: 'Payment Methods',
                    onTap: () {
                      Navigator.pop(context);
                      // TODO: navigate to payment methods page
                    },
                  ),
                  _ProfileMenuTile(
                    icon: Icons.notifications_outlined,
                    label: 'Notifications',
                    onTap: () {
                      Navigator.pop(context);
                      // TODO: navigate to notifications settings
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
        MaterialPageRoute(builder: (_) => const RoleSelectionPage()),
            (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Top bar
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    InkWell(
                      onTap: _setDefaultLocation,
                      borderRadius: BorderRadius.circular(8),
                      child: Row(
                        children: [
                          const Icon(Icons.location_on_outlined, color: kPrimaryGreen, size: 18),
                          const SizedBox(width: 4),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 110),
                            child: Text(
                              _defaultLocation?.address ?? 'Kathmandu, Nepal',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
                            ),
                          ),
                          const Icon(Icons.keyboard_arrow_down_rounded, size: 16),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        Icon(Icons.home_repair_service_rounded, color: kAccentGreen, size: 22),
                        const SizedBox(width: 4),
                        RichText(
                          text: const TextSpan(
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                            children: [
                              TextSpan(text: 'Ghar', style: TextStyle(color: kDarkText)),
                              TextSpan(text: 'Sewa', style: TextStyle(color: kAccentGreen)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(Icons.notifications_none_rounded, size: 24),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(color: kAccentGreen, shape: BoxShape.circle),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Greeting (hidden while searching to keep focus on results)
            if (!_isSearching)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Hello, 👋', style: TextStyle(fontSize: 15)),
                            const SizedBox(height: 4),
                            Text(
                              'What service do you need today?',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: kDarkText,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                      InkWell(
                        onTap: () => _showProfileMenu(context),
                        borderRadius: BorderRadius.circular(36),
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: const BoxDecoration(color: kLightGreenBg, shape: BoxShape.circle),
                          child: const Icon(Icons.person_rounded, color: kPrimaryGreen, size: 36),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Search bar
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search for services...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _isSearching
                        ? IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => _searchController.clear(),
                    )
                        : null,
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),

            // ── Search results (shown only while typing) ──
            if (_isSearching) ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
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
                        Text('No service providers match your search',
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
                        child: _ProviderListTile(
                          provider: _searchResults[index],
                          onTap: () => _openBookingForm(_searchResults[index]),
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
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Popular Services',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: kDarkText)),
                      TextButton(
                        onPressed: _openAllServices,
                        style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                        child: const Text('View All',
                            style: TextStyle(color: kPrimaryGreen, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.78,
                  ),
                  delegate: SliverChildBuilderDelegate(
                        (context, index) => _CategoryTile(
                      category: _categories[index],
                      onTap: () => _openCategoryResults(_categories[index].name),
                    ),
                    childCount: _categories.length,
                  ),
                ),
              ),

              // Top rated professionals
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Top Rated Professionals',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: kDarkText)),
                      TextButton(
                        onPressed: _openAllProfessionals,
                        style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                        child: const Text('View All',
                            style: TextStyle(color: kPrimaryGreen, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 176,
                  child: _buildProfessionalsList(),
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIndex,
        onDestinationSelected: _onNavTap,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.calendar_today_outlined), selectedIcon: Icon(Icons.calendar_today_rounded), label: 'Bookings'),
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline_rounded), selectedIcon: Icon(Icons.chat_bubble_rounded), label: 'Messages'),
          NavigationDestination(icon: Icon(Icons.local_offer_outlined), selectedIcon: Icon(Icons.local_offer_rounded), label: 'Offers'),
          NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Profile'),
        ],
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
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(category.icon, color: kPrimaryGreen, size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            category.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// Shared row-style card for a real ProviderProfile — used by search
// results, category results, and the "All Services" page.
class _ProviderListTile extends StatelessWidget {
  final ProviderProfile provider;
  final VoidCallback onTap;

  const _ProviderListTile({required this.provider, required this.onTap});

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
            const CircleAvatar(
              radius: 26,
              backgroundColor: kLightGreenBg,
              child: Icon(Icons.person_rounded, color: kPrimaryGreen),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(provider.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(provider.displayRole, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded, size: 15, color: Colors.amber),
                      const SizedBox(width: 3),
                      Text(
                        '${provider.rating.toStringAsFixed(1)} (${provider.reviewsCount} reviews)',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
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

class _CategoryResultsPage extends StatelessWidget {
  final String categoryName;
  final List<ProviderProfile> providers;
  final ValueChanged<ProviderProfile> onBook;

  const _CategoryResultsPage({
    required this.categoryName,
    required this.providers,
    required this.onBook,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(categoryName),
        backgroundColor: Colors.white,
        foregroundColor: kDarkText,
        elevation: 0,
      ),
      body: providers.isEmpty
          ? Center(
        child: Text('No service providers available in $categoryName yet',
            style: TextStyle(color: Colors.grey.shade600)),
      )
          : ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: providers.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final provider = providers[index];
          return _ProviderListTile(
            provider: provider,
            onTap: () => onBook(provider),
          );
        },
      ),
    );
  }
}

// ── "View All" → Popular Services (all providers, grouped by category) ──
class _AllServicesPage extends StatefulWidget {
  final List<ProviderProfile> providers;
  final ValueChanged<ProviderProfile> onBook;

  const _AllServicesPage({required this.providers, required this.onBook});

  @override
  State<_AllServicesPage> createState() => _AllServicesPageState();
}

class _AllServicesPageState extends State<_AllServicesPage> {
  String _selectedFilter = 'All';

  List<String> get _filters {
    final categories = widget.providers
        .map((p) => p.serviceCategory)
        .whereType<String>()
        .toSet()
        .toList();
    return ['All', ...categories];
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _selectedFilter == 'All'
        ? widget.providers
        : widget.providers.where((p) => p.serviceCategory == _selectedFilter).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('All Services'),
        backgroundColor: Colors.white,
        foregroundColor: kDarkText,
        elevation: 0,
      ),
      body: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              scrollDirection: Axis.horizontal,
              itemCount: _filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final filter = _filters[index];
                final isSelected = filter == _selectedFilter;
                return ChoiceChip(
                  label: Text(filter),
                  selected: isSelected,
                  onSelected: (_) => setState(() => _selectedFilter = filter),
                  selectedColor: kLightGreenBg,
                  labelStyle: TextStyle(
                    color: isSelected ? kPrimaryGreen : Colors.grey.shade700,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: isSelected ? kPrimaryGreen : Colors.grey.shade300),
                  ),
                  backgroundColor: Colors.white,
                );
              },
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: filtered.isEmpty
                ? Center(
              child: Text(
                'No service providers yet.',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
            )
                : ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final provider = filtered[index];
                return _ProviderListTile(
                  provider: provider,
                  onTap: () => widget.onBook(provider),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── "View All" → Top Rated Professionals ──
class _AllProfessionalsPage extends StatelessWidget {
  final List<ProviderProfile> professionals;
  final ValueChanged<ProviderProfile> onBook;

  const _AllProfessionalsPage({required this.professionals, required this.onBook});

  @override
  Widget build(BuildContext context) {
    final sorted = [...professionals]..sort((a, b) => b.rating.compareTo(a.rating));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Top Rated Professionals'),
        backgroundColor: Colors.white,
        foregroundColor: kDarkText,
        elevation: 0,
      ),
      body: sorted.isEmpty
          ? Center(
        child: Text(
          'No service providers yet.',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        ),
      )
          : ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: sorted.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final p = sorted[index];
          return Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => onBook(p),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade200),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 26,
                      backgroundColor: kLightGreenBg,
                      child: Icon(Icons.person_rounded, color: kPrimaryGreen),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                          const SizedBox(height: 2),
                          Text(p.displayRole, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.star_rounded, size: 15, color: Colors.amber),
                              const SizedBox(width: 3),
                              Text(
                                '${p.rating.toStringAsFixed(1)} (${p.reviewsCount} reviews)',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: kLightGreenBg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('Book',
                          style: TextStyle(fontSize: 12, color: kPrimaryGreen, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}