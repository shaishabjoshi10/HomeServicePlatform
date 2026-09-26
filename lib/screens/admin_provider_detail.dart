import 'package:flutter/material.dart';

import '../main.dart';
import '../models/admin_models.dart';
import '../services/admin_service.dart';
import '../services/api_config.dart';
import 'admin_dashboard.dart' show VerificationStatusChip;

/// Full profile + document review page for one provider. Where an admin
/// actually verifies or rejects an account, after looking at their
/// citizenship documents. Reachable only from the Providers tab of
/// [AdminDashboardPage].
class AdminProviderDetailPage extends StatefulWidget {
  final String accessToken;
  final String providerId;

  const AdminProviderDetailPage({super.key, required this.accessToken, required this.providerId});

  @override
  State<AdminProviderDetailPage> createState() => _AdminProviderDetailPageState();
}

class _AdminProviderDetailPageState extends State<AdminProviderDetailPage> {
  AdminProviderDetail? _detail;
  bool _loading = true;
  bool _updating = false;
  bool _changed = false; // did the verification status change while this page was open?
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final detail = await AdminService.getProviderDetail(
        accessToken: widget.accessToken,
        providerId: widget.providerId,
      );
      if (!mounted) return;
      setState(() => _detail = detail);
    } on AdminServiceException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmAndUpdate(String status) async {
    final isVerify = status == 'verified';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isVerify ? 'Verify this provider?' : 'Reject this provider?'),
        content: Text(
          isVerify
              ? 'They will be marked as verified and able to receive bookings.'
              : 'They will be marked as rejected. They can re-upload documents and be reviewed again.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: isVerify ? Colors.green.shade600 : Colors.red.shade600),
            onPressed: () => Navigator.pop(context, true),
            child: Text(isVerify ? 'Verify' : 'Reject'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _updating = true);
    try {
      final updated = await AdminService.updateProviderVerification(
        accessToken: widget.accessToken,
        providerId: widget.providerId,
        status: status,
      );
      if (!mounted) return;
      setState(() {
        _detail = updated;
        _changed = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isVerify ? 'Provider verified.' : 'Provider rejected.')),
      );
    } on AdminServiceException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red.shade600));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Something went wrong. Please try again.'), backgroundColor: Colors.red.shade600),
      );
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  void _openImage(String url, String title) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(title),
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: Image.network('$apiBaseUrl$url', fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // A plain custom back button (rather than PopScope's pop-interception)
    // so this doesn't depend on which Flutter version's pop-handling API
    // is available — it just always hands the list behind us whether a
    // verification decision was made, so it knows whether to refresh.
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: kDarkText,
        elevation: 0,
        title: const Text('Provider Review'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context, _changed),
        ),
      ),
      body: _buildBody(),
      bottomNavigationBar: _detail == null ? null : _buildActionBar(_detail!),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 40, color: Colors.red.shade400),
              const SizedBox(height: 12),
              Text(_errorMessage!, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700)),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final p = _detail!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          // Header card: avatar, name, service, status.
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: kLightGreenBg,
                  backgroundImage: p.profilePictureUrl != null ? NetworkImage('$apiBaseUrl${p.profilePictureUrl}') : null,
                  child: p.profilePictureUrl == null ? const Icon(Icons.engineering_rounded, color: kPrimaryGreen, size: 30) : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.fullName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(p.serviceCategory ?? 'No service set', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          VerificationStatusChip(status: p.verificationStatus),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: (p.availability ? kPrimaryGreen : Colors.grey).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              p.availability ? 'Available' : 'Unavailable',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: p.availability ? kPrimaryGreen : Colors.grey.shade700),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Booking stats.
          Row(
            children: [
              Expanded(child: _MiniStat(label: 'Total Bookings', value: '${p.totalBookings}')),
              const SizedBox(width: 10),
              Expanded(child: _MiniStat(label: 'Completed', value: '${p.completedBookings}')),
            ],
          ),
          const SizedBox(height: 12),

          _SectionCard(
            title: 'Contact & Personal Info',
            children: [
              _Row(icon: Icons.email_outlined, label: 'Email', value: p.email ?? '—'),
              _Row(icon: Icons.phone_outlined, label: 'Phone', value: p.phone ?? '—'),
              _Row(icon: Icons.alternate_email_rounded, label: 'Alt. Email', value: p.alternativeEmail ?? '—'),
              _Row(icon: Icons.phone_forwarded_outlined, label: 'Alt. Phone', value: p.alternativePhone ?? '—'),
              _Row(icon: Icons.cake_outlined, label: 'Date of Birth', value: p.dateOfBirth != null ? _formatDate(p.dateOfBirth!) : '—'),
              _Row(icon: Icons.location_city_outlined, label: 'City', value: p.city),
              _Row(icon: Icons.badge_outlined, label: 'Citizenship No.', value: p.citizenshipNumber ?? '—'),
              _Row(icon: Icons.calendar_today_outlined, label: 'Joined', value: _formatDate(p.createdAt)),
            ],
          ),
          const SizedBox(height: 12),

          if (p.experience != null || p.bio != null)
            _SectionCard(
              title: 'Professional Info',
              children: [
                if (p.experience != null) _Row(icon: Icons.work_outline_rounded, label: 'Experience', value: p.experience!),
                if (p.bio != null && p.bio!.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(p.bio!, style: const TextStyle(fontSize: 13, color: kDarkText)),
                  ),
              ],
            ),
          if (p.experience != null || p.bio != null) const SizedBox(height: 12),

          // Verification documents.
          _SectionCard(
            title: 'Verification Documents',
            children: [
              Row(
                children: [
                  Expanded(
                    child: _DocumentThumb(
                      label: 'Citizenship Front',
                      url: p.citizenshipFrontUrl,
                      onTap: p.citizenshipFrontUrl != null
                          ? () => _openImage(p.citizenshipFrontUrl!, 'Citizenship Front')
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DocumentThumb(
                      label: 'Citizenship Back',
                      url: p.citizenshipBackUrl,
                      onTap: p.citizenshipBackUrl != null
                          ? () => _openImage(p.citizenshipBackUrl!, 'Citizenship Back')
                          : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar(AdminProviderDetail p) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: (_updating || p.isRejected) ? null : () => _confirmAndUpdate('rejected'),
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Reject'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade600,
                  side: BorderSide(color: Colors.red.shade300),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: (_updating || p.isVerified) ? null : () => _confirmAndUpdate('verified'),
                icon: _updating
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_rounded, size: 18),
                label: const Text('Verify'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kDarkText)),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _Row({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade500),
          const SizedBox(width: 10),
          SizedBox(width: 120, child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: kDarkText))),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: kDarkText)),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}

class _DocumentThumb extends StatelessWidget {
  final String label;
  final String? url;
  final VoidCallback? onTap;
  const _DocumentThumb({required this.label, required this.url, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        const SizedBox(height: 6),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            height: 100,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: url == null
                ? Center(child: Icon(Icons.image_not_supported_outlined, color: Colors.grey.shade400))
                : ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network('$apiBaseUrl$url', fit: BoxFit.cover),
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                            child: const Icon(Icons.zoom_in_rounded, color: Colors.white, size: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

String _formatDate(DateTime dt) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
}
