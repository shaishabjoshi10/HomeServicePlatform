import 'package:flutter/material.dart';
import '../main.dart';
import '../models/booking.dart';
import '../models/provider_profile.dart';
import '../services/booking_service.dart';
import '../services/provider_service.dart';
import 'booking_detail_sheet.dart';
import 'complete_profile.dart';
import 'provider_bookings.dart';
import 'role_selection.dart';

class ServiceProviderHomePage extends StatefulWidget {
  final String providerName;
  final String accessToken;

  const ServiceProviderHomePage({
    super.key,
    required this.accessToken,
    this.providerName = 'Provider Name',
  });

  @override
  State<ServiceProviderHomePage> createState() => _ServiceProviderHomePageState();
}

class _ServiceProviderHomePageState extends State<ServiceProviderHomePage> {
  int _navIndex = 0;
  static const int _profileTabIndex = 4;

  ProviderProfile? _profile;
  bool _loadingProfile = true;
  String? _profileError;

  List<Booking> _allBookings = [];
  List<Booking> _pendingBookings = [];
  List<Booking> _acceptedBookings = [];
  bool _loadingBookings = true;
  String? _bookingsError;

  // See _respondToBooking — guards against a double-tap firing a second
  // status-change request for a booking whose first request hasn't
  // finished yet.
  final Set<String> _updatingBookingIds = {};

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadBookings();
  }

  Future<void> _loadBookings() async {
    setState(() {
      _loadingBookings = true;
      _bookingsError = null;
    });

    try {
      final bookings = await BookingService.getMyBookings(accessToken: widget.accessToken);
      if (!mounted) return;
      setState(() {
        _allBookings = bookings;
        _pendingBookings = bookings.where((b) => b.status == 'pending').toList();
        _acceptedBookings = bookings.where((b) => b.status == 'accepted').toList();
        _loadingBookings = false;
      });
    } on BookingServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _bookingsError = e.message;
        _loadingBookings = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _bookingsError = 'Something went wrong loading your bookings.';
        _loadingBookings = false;
      });
    }
  }

  Future<void> _respondToBooking(Booking booking, String status) async {
    // Without this guard, a double-tap (or a slow connection) can fire a
    // second status-change request after the first has already succeeded;
    // the backend correctly rejects that redundant transition, which would
    // otherwise surface as a confusing error even though the original
    // action worked.
    if (_updatingBookingIds.contains(booking.id)) return;
    setState(() => _updatingBookingIds.add(booking.id));
    try {
      await BookingService.updateStatus(
        accessToken: widget.accessToken,
        bookingId: booking.id,
        status: status,
      );
      await _loadBookings();
    } on BookingServiceException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red.shade600),
      );
    } finally {
      if (mounted) setState(() => _updatingBookingIds.remove(booking.id));
    }
  }

  int _todaysAcceptedCount() {
    final now = DateTime.now();
    return _acceptedBookings.where((b) {
      final d = b.preferredDate;
      return d != null && d.year == now.year && d.month == now.month && d.day == now.day;
    }).length;
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loadingProfile = true;
      _profileError = null;
    });

    try {
      final profile = await ProviderService.getMyProfile(widget.accessToken);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loadingProfile = false;
      });
    } on ProviderServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _profileError = e.message;
        _loadingProfile = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _profileError = 'Something went wrong loading your profile.';
        _loadingProfile = false;
      });
    }
  }

  void _onNavTap(int index) {
    if (index == _profileTabIndex) {
      _showProfileMenu(context);
      return;
    }
    if (index == 1) {
      // "Bookings" — pushes the full list instead of switching an in-page tab,
      // since Earnings/Messages don't have their own screens built yet.
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ProviderBookingsPage(accessToken: widget.accessToken)),
      ).then((_) => _loadBookings());
      return;
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
                        child: const Icon(Icons.engineering_rounded, color: kPrimaryGreen, size: 26),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.providerName,
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                            Row(
                              children: [
                                const Icon(Icons.star_rounded, size: 14, color: Colors.amber),
                                const SizedBox(width: 2),
                                Text(
                                  _loadingProfile
                                      ? 'Loading…'
                                      : _profile != null
                                      ? '${_profile!.rating.toStringAsFixed(1)} Rating (${_profile!.reviewsCount})'
                                      : '— Rating',
                                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 32),
                  _ProfileMenuTile(
                    icon: Icons.person_outline_rounded,
                    label: 'Edit Profile',
                    onTap: () async {
                      Navigator.pop(context);
                      if (_profile == null) return;
                      final updated = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CompleteProfilePage(
                            accessToken: widget.accessToken,
                            currentProfile: _profile!,
                          ),
                        ),
                      );
                      if (updated == true) {
                        _loadProfile();
                      }
                    },
                  ),
                  _ProfileMenuTile(
                    icon: Icons.build_outlined,
                    label: 'Manage Services',
                    onTap: () {
                      Navigator.pop(context);
                      // TODO: navigate to manage services page
                    },
                  ),
                  _ProfileMenuTile(
                    icon: Icons.event_available_outlined,
                    label: 'Availability & Schedule',
                    onTap: () {
                      Navigator.pop(context);
                      // TODO: navigate to availability settings
                    },
                  ),
                  _ProfileMenuTile(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Earnings & Payouts',
                    onTap: () {
                      Navigator.pop(context);
                      // TODO: navigate to earnings page
                    },
                  ),
                  _ProfileMenuTile(
                    icon: Icons.history_rounded,
                    label: 'Job History',
                    onTap: () {
                      Navigator.pop(context);
                      // TODO: navigate to job history page
                    },
                  ),
                  _ProfileMenuTile(
                    icon: Icons.verified_user_outlined,
                    label: 'Verification & Documents',
                    onTap: () {
                      Navigator.pop(context);
                      // TODO: navigate to verification page
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
                padding: const EdgeInsets.fromLTRB(16, 12, 20, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.menu_rounded),
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
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.notifications_none_rounded),
                    ),
                  ],
                ),
              ),
            ),

            // Greeting
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Ready to serve today?',
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: kDarkText)),
                          const SizedBox(height: 4),
                          if (_loadingProfile)
                            Text('Loading your profile…',
                                style: TextStyle(fontSize: 13, color: Colors.grey.shade600))
                          else if (_profileError != null)
                            Row(
                              children: [
                                Flexible(
                                  child: Text(_profileError!,
                                      style: TextStyle(fontSize: 12, color: Colors.red.shade600)),
                                ),
                                TextButton(
                                  onPressed: _loadProfile,
                                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                                  child: const Text('Retry',
                                      style: TextStyle(color: kPrimaryGreen, fontWeight: FontWeight.w600)),
                                ),
                              ],
                            )
                          else
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    _profile?.displayRole ?? 'Service Provider',
                                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (_profile != null) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _profile!.verificationStatus == 'verified'
                                          ? kLightGreenBg
                                          : Colors.orange.shade50,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      _profile!.verificationStatus == 'verified' ? 'Verified' : 'Pending Verification',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: _profile!.verificationStatus == 'verified'
                                            ? kPrimaryGreen
                                            : Colors.orange.shade800,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
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
                        child: const Icon(Icons.engineering_rounded, color: kPrimaryGreen, size: 36),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Complete-profile nudge
            if (!_loadingProfile && _profile != null && !_profile!.isComplete)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () async {
                      final updated = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CompleteProfilePage(
                            accessToken: widget.accessToken,
                            currentProfile: _profile!,
                          ),
                        ),
                      );
                      if (updated == true) _loadProfile();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline_rounded, color: Colors.orange.shade800),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Complete your profile to start getting bookings.',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: Colors.orange.shade800),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // Stats banner
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
                  decoration: BoxDecoration(
                    color: kPrimaryGreen,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      _StatItem(
                        icon: Icons.assignment_outlined,
                        value: _loadingBookings ? '…' : '${_pendingBookings.length}',
                        label: 'New Requests',
                      ),
                      _StatItem(
                        icon: Icons.calendar_today_outlined,
                        value: _loadingBookings ? '…' : '${_todaysAcceptedCount()}',
                        label: "Today's Bookings",
                      ),
                      _StatItem(
                        icon: Icons.check_circle_outline_rounded,
                        value: _loadingBookings
                            ? '…'
                            : '${_allBookings.where((b) => b.status == 'completed').length}',
                        label: 'Completed Jobs',
                      ),
                      _StatItem(
                        icon: Icons.star_outline_rounded,
                        value: _loadingProfile
                            ? '…'
                            : _profile != null
                            ? _profile!.rating.toStringAsFixed(1)
                            : '—',
                        label: 'Your Rating',
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // New requests — pending bookings awaiting a response
            if (!_loadingBookings && _pendingBookings.isNotEmpty) ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 8),
                sliver: SliverToBoxAdapter(
                  child: Text('New Requests',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: kDarkText)),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                        (context, index) {
                      final b = _pendingBookings[index];
                      final isUpdating = _updatingBookingIds.contains(b.id);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: isUpdating
                              ? null
                              : () => showBookingDetailSheet(
                                  context,
                                  booking: b,
                                  onAccept: () => _respondToBooking(b, 'accepted'),
                                  onDecline: () => _respondToBooking(b, 'rejected'),
                                ),
                          child: Opacity(
                            opacity: isUpdating ? 0.5 : 1,
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade200),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(b.customerName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                  if (b.serviceCategory != null) ...[
                                    const SizedBox(height: 2),
                                    Text(b.serviceCategory!, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                  ],
                                  const SizedBox(height: 6),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(Icons.location_on_outlined, size: 13, color: Colors.grey.shade600),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(b.address, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton(
                                          onPressed: isUpdating ? null : () => _respondToBooking(b, 'rejected'),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: Colors.red.shade600,
                                            side: BorderSide(color: Colors.red.shade200),
                                          ),
                                          child: const Text('Decline'),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: FilledButton(
                                          onPressed: isUpdating ? null : () => _respondToBooking(b, 'accepted'),
                                          style: FilledButton.styleFrom(backgroundColor: kPrimaryGreen),
                                          child: isUpdating
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                                )
                                              : const Text('Accept'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                    childCount: _pendingBookings.length,
                  ),
                ),
              ),
            ],

            // Today's schedule
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 8),
              sliver: SliverToBoxAdapter(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Today's Schedule",
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: kDarkText)),
                    const Text('View All', style: TextStyle(color: kPrimaryGreen, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: _acceptedBookings.isEmpty
                    ? Container(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade200),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.event_busy_outlined, size: 28, color: Colors.grey.shade400),
                      const SizedBox(height: 8),
                      Text(
                        'No appointments scheduled for today.',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                )
                    : Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade200),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: List.generate(_acceptedBookings.length, (i) {
                      final b = _acceptedBookings[i];
                      return Column(
                        children: [
                          InkWell(
                            onTap: () => showBookingDetailSheet(
                              context,
                              booking: b,
                              onComplete: () => _respondToBooking(b, 'completed'),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(b.customerName,
                                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                        const SizedBox(height: 2),
                                        if (b.serviceCategory != null)
                                          Text(b.serviceCategory!,
                                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            Icon(Icons.location_on_outlined, size: 13, color: Colors.grey.shade600),
                                            const SizedBox(width: 3),
                                            Expanded(
                                              child: Text(b.address,
                                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: kLightGreenBg,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Text('Confirmed',
                                        style: TextStyle(fontSize: 11, color: kPrimaryGreen, fontWeight: FontWeight.w600)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (i != _acceptedBookings.length - 1) Divider(height: 1, color: Colors.grey.shade200),
                        ],
                      );
                    }),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverToBoxAdapter(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Recent Activity',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: kDarkText)),
                    const Text('View All', style: TextStyle(color: kPrimaryGreen, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              sliver: SliverToBoxAdapter(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  alignment: Alignment.center,
                  child: Column(
                    children: [
                      Icon(Icons.history_toggle_off_rounded, size: 26, color: Colors.grey.shade400),
                      const SizedBox(height: 8),
                      Text(
                        'No recent activity yet.',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIndex,
        onDestinationSelected: _onNavTap,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.calendar_today_outlined), selectedIcon: Icon(Icons.calendar_today_rounded), label: 'Bookings'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet_rounded), label: 'Earnings'),
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline_rounded), selectedIcon: Icon(Icons.chat_bubble_rounded), label: 'Messages'),
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

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _StatItem({required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 10)),
        ],
      ),
    );
  }
}