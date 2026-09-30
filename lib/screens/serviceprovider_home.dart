import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import '../models/booking.dart';
import '../models/provider_profile.dart';
import '../models/service_rating.dart';
import '../services/api_config.dart';
import '../services/booking_service.dart';
import '../services/provider_service.dart';
import '../services/service_rating_service.dart';
import '../widgets/profile_picture_picker.dart';
import 'provider_booking_details_page.dart';
import 'complete_profile.dart';
import 'provider_bookings.dart';
import 'login.dart';

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
  static const int _profileTabIndex = 3;

  ProviderProfile? _profile;
  bool _loadingProfile = true;
  String? _profileError;

  // Customers rate the overall service, not individual providers, so what a
  // provider sees here is the overall rating of the service they offer.
  List<ServiceRating> _serviceRatings = [];
  bool _loadingServiceRatings = true;

  ServiceRating? get _serviceRating {
    final category = _profile?.serviceCategory;
    if (category == null) return null;
    for (final r in _serviceRatings) {
      if (r.serviceCategory == category) return r;
    }
    return null;
  }

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
    _loadServiceRatings();
  }

  Future<void> _loadServiceRatings() async {
    try {
      final ratings = await ServiceRatingService.getServiceRatings(widget.accessToken);
      if (!mounted) return;
      setState(() {
        _serviceRatings = ratings;
        _loadingServiceRatings = false;
      });
    } catch (_) {
      // The rating is informational — if it can't load, the tile just shows
      // a dash rather than an error banner.
      if (!mounted) return;
      setState(() => _loadingServiceRatings = false);
    }
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

  /// Full, absolute URL for the current profile picture, or null.
  String? get _profilePictureFullUrl =>
      _profile?.profilePictureUrl != null ? '$apiBaseUrl${_profile!.profilePictureUrl}' : null;

  Future<String?> _uploadOwnProfilePicture(File file) async {
    final updated = await ProviderService.uploadProfilePicture(
      accessToken: widget.accessToken,
      file: file,
    );
    return updated.profilePictureUrl;
  }

  void _onProfilePictureUpdated(String? newUrl) {
    if (_profile == null) return;
    setState(() => _profile = _profile!.copyWithProfilePicture(newUrl));
  }

  void _onNavTap(int index) {
    if (index == _profileTabIndex) {
      _showProfileMenu(context);
      return;
    }
    if (index == 1) {
      // "Bookings" — pushes the full list instead of switching an in-page tab,
      // since Earnings doesn't have its own screen built yet.
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
                            placeholderIcon: Icons.engineering_rounded,
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
                                Text(widget.providerName,
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                Row(
                                  children: [
                                    const Icon(Icons.star_rounded, size: 14, color: Colors.amber),
                                    const SizedBox(width: 2),
                                    Text(
                                      _loadingProfile || _loadingServiceRatings
                                          ? 'Loading…'
                                          : _serviceRating?.hasReviews == true
                                          ? '${_serviceRating!.rating.toStringAsFixed(1)} Service rating (${_serviceRating!.reviewsCount})'
                                          : '— Service rating',
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
        MaterialPageRoute(builder: (_) => const LoginPage(role: UserRole.provider)),
            (route) => false,
      );
    }
  }

  // ── Small helpers ──────────────────────────────────────────────────

  static const _cardBorder = Color(0xFFE9EFEB);
  static const _pageBg = Color(0xFFF7F9F8);

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String get _firstName {
    final full = (_profile?.name.isNotEmpty == true ? _profile!.name : widget.providerName).trim();
    return full.isEmpty ? 'there' : full.split(RegExp(r'\s+')).first;
  }

  String _timeAgo(DateTime t) {
    final d = DateTime.now().difference(t.toLocal());
    if (d.inMinutes < 1) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return '${(d.inDays / 7).floor()}w ago';
  }

  /// Latest finished bookings (completed, declined or cancelled), newest first.
  List<Booking> get _recentActivity {
    const finished = {'completed', 'rejected', 'cancelled'};
    final done = _allBookings.where((b) => finished.contains(b.status)).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return done.take(4).toList();
  }

  Future<void> _openBooking(Booking b) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProviderBookingDetailsPage(
          accessToken: widget.accessToken,
          booking: b,
          isVerified: _profile?.isVerified ?? false,
        ),
      ),
    );
    if (!mounted) return;
    _loadBookings();
  }

  void _openAllBookings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProviderBookingsPage(accessToken: widget.accessToken)),
    ).then((_) {
      if (mounted) _loadBookings();
    });
  }

  // ── Header ─────────────────────────────────────────────────────────

  /// Small avatar; tapping opens the profile menu, which holds the
  /// picture uploader (same pattern as the customer home).
  Widget _buildProfileButton() {
    final url = _profilePictureFullUrl;
    return GestureDetector(
      onTap: () => _showProfileMenu(context),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        child: CircleAvatar(
          radius: 22,
          backgroundColor: kLightGreenBg,
          backgroundImage: url != null ? NetworkImage(url) : null,
          onBackgroundImageError: url != null ? (_, _) {} : null,
          child: url == null
              ? const Icon(Icons.engineering_rounded, color: kPrimaryGreen, size: 22)
              : null,
        ),
      ),
    );
  }

  Widget _buildNotificationButton() {
    return InkWell(
      // No notifications screen exists yet — visual only, as before.
      onTap: () {},
      customBorder: const CircleBorder(),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          shape: BoxShape.circle,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(Icons.notifications_none_rounded, size: 23, color: Colors.white),
            Positioned(
              right: 12,
              top: 11,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: kPrimaryGreen, width: 1.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Role + verification badge, or the loading / error state of the profile.
  Widget _buildStatusLine() {
    if (_loadingProfile) {
      return Text('Loading your profile…',
          style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.8)));
    }
    if (_profileError != null) {
      return Row(
        children: [
          const Icon(Icons.error_outline_rounded, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Flexible(
            child: Text(_profileError!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.white)),
          ),
          TextButton(
            onPressed: _loadProfile,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Retry',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      );
    }
    final verified = _profile?.verificationStatus == 'verified';
    return Row(
      children: [
        Flexible(
          child: Text(
            _profile?.displayRole ?? 'Service Provider',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.85)),
          ),
        ),
        if (_profile != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: verified ? Colors.white : Colors.orange.shade50,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  verified ? Icons.verified_rounded : Icons.hourglass_top_rounded,
                  size: 12,
                  color: verified ? kPrimaryGreen : Colors.orange.shade800,
                ),
                const SizedBox(width: 4),
                Text(
                  verified ? 'Verified' : 'Pending Verification',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: verified ? kPrimaryGreen : Colors.orange.shade800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // Extra bottom padding leaves room for the stats card to overlap the
  // header's lower edge.
  Widget _buildHeader(double topInset) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, topInset + 12, 20, 60),
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
              _buildProfileButton(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _greeting(),
                      style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.8)),
                    ),
                    Text(
                      _firstName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              _buildNotificationButton(),
            ],
          ),
          const SizedBox(height: 22),
          const Text(
            'Ready to serve today?',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.2,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 8),
          _buildStatusLine(),
        ],
      ),
    );
  }

  // ── Floating stats card ────────────────────────────────────────────

  static const double _statsCardMinHeight = 104;
  static const double _statsOverhang = 48; // how far the card hangs below the header

  Widget _buildStatsCard() {
    Widget divider() => Container(width: 1, margin: const EdgeInsets.symmetric(vertical: 6), color: _cardBorder);
    final completed = _allBookings.where((b) => b.status == 'completed').length;

    // The card sizes itself to its content (with a minimum height) instead
    // of a fixed height, and caps the system text scale, so large-font
    // settings can't push the stats past the card's edge.
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.15),
      ),
      child: Container(
        constraints: const BoxConstraints(minHeight: _statsCardMinHeight),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StatItem(
                icon: Icons.assignment_outlined,
                value: _loadingBookings ? '…' : '${_pendingBookings.length}',
                label: 'Requests',
              ),
              divider(),
              _StatItem(
                icon: Icons.calendar_today_outlined,
                value: _loadingBookings ? '…' : '${_todaysAcceptedCount()}',
                label: 'Today',
              ),
              divider(),
              _StatItem(
                icon: Icons.check_circle_outline_rounded,
                value: _loadingBookings ? '…' : '$completed',
                label: 'Completed',
              ),
              divider(),
              _StatItem(
                icon: Icons.star_outline_rounded,
                value: _loadingProfile || _loadingServiceRatings
                    ? '…'
                    : _serviceRating?.hasReviews == true
                    ? _serviceRating!.rating.toStringAsFixed(1)
                    : '—',
                label: 'Rating',
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Profile / verification notices ─────────────────────────────────

  Widget _noticeBox({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: child,
    );
  }

  Widget _buildCompleteProfileNotice() {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
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
      child: _noticeBox(
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
    );
  }

  Widget _buildPendingVerificationNotice() {
    return _noticeBox(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.hourglass_top_rounded, color: Colors.orange.shade800),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pending Verification',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.orange.shade900),
                ),
                const SizedBox(height: 2),
                Text(
                  "An admin is reviewing your documents. You'll be able to accept booking "
                      "requests as soon as your account is verified.",
                  style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Sections ───────────────────────────────────────────────────────

  Widget _sectionHeader(String title, {VoidCallback? onViewAll}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: kDarkText)),
        if (onViewAll != null)
          TextButton(
            onPressed: onViewAll,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('View All', style: TextStyle(color: kPrimaryGreen, fontWeight: FontWeight.w600)),
                SizedBox(width: 2),
                Icon(Icons.arrow_forward_ios_rounded, size: 12, color: kPrimaryGreen),
              ],
            ),
          ),
      ],
    );
  }

  BoxDecoration get _sectionDecoration => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: _cardBorder),
  );

  Widget _emptyState(IconData icon, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 16),
      decoration: _sectionDecoration,
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(color: kLightGreenBg, shape: BoxShape.circle),
            child: Icon(icon, size: 24, color: kPrimaryGreen),
          ),
          const SizedBox(height: 12),
          Text(message, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  /// "Job · Category" line with the price on the right, shared by the
  /// request cards and the schedule rows.
  Widget _jobLine(Booking b) {
    if (b.jobTitle == null && b.serviceCategory == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Flexible(
            child: Text(
              b.jobTitle != null && b.serviceCategory != null
                  ? '${b.jobTitle} · ${b.serviceCategory}'
                  : b.displayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
          if (b.hasPrice) ...[
            const SizedBox(width: 8),
            Text(
              b.priceLabel!,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kPrimaryGreen),
            ),
          ],
        ],
      ),
    );
  }

  Widget _addressLine(Booking b) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.location_on_outlined, size: 13, color: Colors.grey.shade600),
        const SizedBox(width: 4),
        Expanded(
          child: Text(b.address, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ),
      ],
    );
  }

  Widget _buildRequestCard(Booking b) {
    final isUpdating = _updatingBookingIds.contains(b.id);
    final verified = _profile?.isVerified == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: isUpdating ? null : () => _openBooking(b),
        child: Opacity(
          opacity: isUpdating ? 0.5 : 1,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: _sectionDecoration,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(b.customerName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                // The job requested and what it pays, so a provider can
                // judge an incoming request before accepting it.
                _jobLine(b),
                const SizedBox(height: 8),
                _addressLine(b),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: isUpdating ? null : () => _respondToBooking(b, 'rejected'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red.shade600,
                          side: BorderSide(color: Colors.red.shade200),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Decline'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        // Declining never needs verification — only accepting a
                        // job does, so that's the only action gated here.
                        onPressed: (isUpdating || !verified) ? null : () => _respondToBooking(b, 'accepted'),
                        style: FilledButton.styleFrom(
                          backgroundColor: kPrimaryGreen,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
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
                if (!verified) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.hourglass_top_rounded, size: 13, color: Colors.orange.shade800),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Verification required to accept new jobs.',
                          style: TextStyle(fontSize: 11, color: Colors.orange.shade800, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScheduleSection() {
    if (_acceptedBookings.isEmpty) {
      return _emptyState(Icons.event_available_outlined, 'No appointments scheduled for today.');
    }
    return Container(
      decoration: _sectionDecoration,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: List.generate(_acceptedBookings.length, (i) {
          final b = _acceptedBookings[i];
          return Column(
            children: [
              InkWell(
                onTap: () => _openBooking(b),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: kLightGreenBg,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: const Icon(Icons.handyman_outlined, size: 20, color: kPrimaryGreen),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(b.customerName,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                            _jobLine(b),
                            const SizedBox(height: 4),
                            _addressLine(b),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
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
              if (i != _acceptedBookings.length - 1) const Divider(height: 1, color: _cardBorder),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildActivitySection() {
    final items = _recentActivity;
    if (items.isEmpty) {
      return _emptyState(Icons.history_rounded, 'No recent activity yet.');
    }
    return Container(
      decoration: _sectionDecoration,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: List.generate(items.length, (i) {
          final b = items[i];
          final (IconData icon, Color color, String label) = switch (b.status) {
            'completed' => (Icons.check_circle_rounded, kPrimaryGreen, 'Completed'),
            'rejected' => (Icons.cancel_rounded, Colors.red.shade600, 'Declined'),
            _ => (Icons.remove_circle_rounded, Colors.grey.shade600, 'Cancelled'),
          };
          return Column(
            children: [
              InkWell(
                onTap: () => _openBooking(b),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Icon(icon, size: 26, color: color),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(b.customerName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                            const SizedBox(height: 2),
                            Text(b.displayTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(label,
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
                          const SizedBox(height: 2),
                          Text(_timeAgo(b.updatedAt),
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (i != items.length - 1) const Divider(height: 1, color: _cardBorder),
            ],
          );
        }),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final showCompleteNotice = !_loadingProfile && _profile != null && !_profile!.isComplete;
    final showPendingNotice =
        !_loadingProfile && _profile != null && _profile!.isComplete && !_profile!.isVerified;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Green header runs up under the status bar, so use light icons.
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: _pageBg,
        body: CustomScrollView(
          slivers: [
            // Gradient header with the stats card floating over its lower edge.
            SliverToBoxAdapter(
              child: Stack(
                clipBehavior: Clip.none,
                fit: StackFit.passthrough,
                children: [
                  _buildHeader(topInset),
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: -_statsOverhang,
                    child: _buildStatsCard(),
                  ),
                ],
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: _statsOverhang + 32)),

            // Complete-profile nudge — and, once the profile itself is
            // complete, a "Pending Verification" nudge instead. The two
            // are mutually exclusive on purpose: an admin can't verify an
            // incomplete submission, so a provider is always in exactly
            // one of these states until they're actually verified.
            if (showCompleteNotice)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: _buildCompleteProfileNotice(),
                ),
              )
            else if (showPendingNotice)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: _buildPendingVerificationNotice(),
                ),
              ),

            // New requests — pending bookings awaiting a response
            if (!_loadingBookings && _pendingBookings.isNotEmpty) ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                sliver: SliverToBoxAdapter(child: _sectionHeader('New Requests')),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                        (context, index) => _buildRequestCard(_pendingBookings[index]),
                    childCount: _pendingBookings.length,
                  ),
                ),
              ),
            ],

            // Today's schedule
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              sliver: SliverToBoxAdapter(
                child: _sectionHeader("Today's Schedule", onViewAll: _openAllBookings),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              sliver: SliverToBoxAdapter(child: _buildScheduleSection()),
            ),

            // Recent activity
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              sliver: SliverToBoxAdapter(
                child: _sectionHeader('Recent Activity', onViewAll: _openAllBookings),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              sliver: SliverToBoxAdapter(child: _buildActivitySection()),
            ),
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
            NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet_rounded, color: kPrimaryGreen), label: 'Earnings'),
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

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _StatItem({required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: kPrimaryGreen, size: 20),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(color: kDarkText, fontSize: 20, fontWeight: FontWeight.w800, height: 1.1),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 11, height: 1.2),
            ),
          ),
        ],
      ),
    );
  }
}