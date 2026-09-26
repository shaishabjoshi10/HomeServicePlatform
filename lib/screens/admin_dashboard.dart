import 'package:flutter/material.dart';

import '../main.dart';
import '../models/admin_models.dart';
import '../services/admin_service.dart';
import '../services/api_config.dart';
import 'admin_login.dart';
import 'admin_provider_detail.dart';

/// The Admin Dashboard's home screen: three tabs (Overview, Customers,
/// Providers) behind a bottom NavigationBar, each fetching its own data on
/// first view and via pull-to-refresh after that. Unlike the customer/
/// provider home pages' bottom navs (which mostly just push separate
/// pages), these tabs genuinely swap the body via an IndexedStack, since
/// there's real, different content — and its own search/filter state — to
/// keep alive in each one.
class AdminDashboardPage extends StatefulWidget {
  final String accessToken;
  final String adminEmail;

  const AdminDashboardPage({super.key, required this.accessToken, required this.adminEmail});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  int _tabIndex = 0;

  void _goToProvidersTab({String? verificationStatus}) {
    setState(() => _tabIndex = 2);
    if (verificationStatus != null) {
      _providersTabKey.currentState?.applyFilter(verificationStatus);
    }
  }

  final _providersTabKey = GlobalKey<_ProvidersTabState>();

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to sign in again to access the Admin Dashboard.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Log Out', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AdminLoginPage()),
            (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: kDarkText,
        foregroundColor: Colors.white,
        title: const Text('Admin Dashboard', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'Log out',
            onPressed: _confirmLogout,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tabIndex,
        children: [
          _OverviewTab(
            accessToken: widget.accessToken,
            adminEmail: widget.adminEmail,
            onViewPendingProviders: () => _goToProvidersTab(verificationStatus: 'pending'),
          ),
          _CustomersTab(accessToken: widget.accessToken),
          _ProvidersTab(key: _providersTabKey, accessToken: widget.accessToken),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard_rounded), label: 'Overview'),
          NavigationDestination(icon: Icon(Icons.people_alt_outlined), selectedIcon: Icon(Icons.people_alt_rounded), label: 'Customers'),
          NavigationDestination(icon: Icon(Icons.engineering_outlined), selectedIcon: Icon(Icons.engineering_rounded), label: 'Providers'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Overview tab
// ---------------------------------------------------------------------------

class _OverviewTab extends StatefulWidget {
  final String accessToken;
  final String adminEmail;
  final VoidCallback onViewPendingProviders;

  const _OverviewTab({required this.accessToken, required this.adminEmail, required this.onViewPendingProviders});

  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> {
  Future<AdminStats>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    // A block body, not `=> _future = ...`: an arrow body is that
    // assignment *expression*, which evaluates to the assigned Future
    // itself — making the closure implicitly return a Future, which
    // setState explicitly rejects ("callback argument returned a
    // Future"). The block body below returns void instead.
    setState(() {
      _future = AdminService.getStats(accessToken: widget.accessToken);
    });
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        _load();
        await _future;
      },
      child: FutureBuilder<AdminStats>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(message: _errorText(snapshot.error), onRetry: _load);
          }

          final stats = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Signed in as ${widget.adminEmail}', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
              const SizedBox(height: 16),
              GridView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                // A fixed mainAxisExtent (a set height in logical pixels)
                // rather than childAspectRatio: aspect ratio derives the
                // cell's height from its *width*, which shrinks on
                // narrower phones and under larger system font-scaling
                // settings — exactly what was overflowing the card's
                // content (icon box + value + label) here. A fixed height
                // stays generous regardless of screen width or text scale.
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  mainAxisExtent: 118,
                ),
                children: [
                  _StatCard(icon: Icons.people_alt_rounded, color: kPrimaryGreen, label: 'Customers', value: '${stats.totalCustomers}'),
                  _StatCard(icon: Icons.engineering_rounded, color: Colors.blue.shade600, label: 'Providers', value: '${stats.totalProviders}'),
                  _StatCard(icon: Icons.verified_rounded, color: Colors.green.shade600, label: 'Verified', value: '${stats.verifiedProviders}'),
                  _StatCard(icon: Icons.block_rounded, color: Colors.red.shade600, label: 'Rejected', value: '${stats.rejectedProviders}'),
                  _StatCard(icon: Icons.event_note_rounded, color: Colors.purple.shade400, label: 'Total Bookings', value: '${stats.totalBookings}'),
                  _StatCard(
                    icon: Icons.pending_actions_rounded,
                    color: Colors.orange.shade700,
                    label: 'Pending Review',
                    value: '${stats.pendingVerifications}',
                    highlighted: stats.pendingVerifications > 0,
                  ),
                ],
              ),
              if (stats.pendingVerifications > 0) ...[
                const SizedBox(height: 8),
                Card(
                  elevation: 0,
                  color: Colors.orange.shade50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.orange.shade200),
                  ),
                  child: ListTile(
                    onTap: widget.onViewPendingProviders,
                    leading: Icon(Icons.pending_actions_rounded, color: Colors.orange.shade700),
                    title: Text(
                      '${stats.pendingVerifications} provider${stats.pendingVerifications == 1 ? '' : 's'} awaiting review',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    subtitle: const Text('Tap to review their documents', style: TextStyle(fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final bool highlighted;

  const _StatCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: highlighted ? Border.all(color: color, width: 1.5) : Border.all(color: Colors.grey.shade200),
      ),
      // mainAxisSize.min + a fixed gap, not a Spacer: the icon box, value
      // and label now only ever take exactly the space their own content
      // needs, so even if a very large system font-scaling setting makes
      // that content taller than usual, this column still just fits
      // itself top-to-bottom instead of assuming it can stretch to fill
      // (and then overflowing) a fixed-height parent.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: kDarkText),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Customers tab
// ---------------------------------------------------------------------------

class _CustomersTab extends StatefulWidget {
  final String accessToken;
  const _CustomersTab({required this.accessToken});

  @override
  State<_CustomersTab> createState() => _CustomersTabState();
}

class _CustomersTabState extends State<_CustomersTab> {
  Future<List<AdminCustomer>>? _future;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _load() {
    setState(() {
      _future = AdminService.getCustomers(accessToken: widget.accessToken, query: _query);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: _SearchField(
            controller: _searchController,
            hint: 'Search by name, email or phone',
            onSubmitted: (v) {
              _query = v;
              _load();
            },
            onCleared: () {
              _query = '';
              _load();
            },
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              _load();
              await _future;
            },
            child: FutureBuilder<List<AdminCustomer>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _ErrorState(message: _errorText(snapshot.error), onRetry: _load);
                }

                final customers = snapshot.data!;
                if (customers.isEmpty) {
                  return _EmptyState(
                    icon: Icons.people_outline_rounded,
                    message: _query.isEmpty ? 'No customers yet.' : 'No customers match "$_query".',
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: customers.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _CustomerCard(customer: customers[i]),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _CustomerCard extends StatelessWidget {
  final AdminCustomer customer;
  const _CustomerCard({required this.customer});

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _Avatar(url: customer.profilePictureUrl, fallbackIcon: Icons.person_rounded, radius: 28),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(customer.fullName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                        Text('Customer', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 28),
              _DetailRow(icon: Icons.email_outlined, label: 'Email', value: customer.email ?? '—'),
              _DetailRow(icon: Icons.phone_outlined, label: 'Phone', value: customer.phone ?? '—'),
              _DetailRow(icon: Icons.location_on_outlined, label: 'Address', value: customer.address ?? 'Not set'),
              _DetailRow(icon: Icons.event_note_outlined, label: 'Total Bookings', value: '${customer.totalBookings}'),
              _DetailRow(icon: Icons.calendar_today_outlined, label: 'Joined', value: _formatDate(customer.createdAt)),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showDetail(context),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
          child: Row(
            children: [
              _Avatar(url: customer.profilePictureUrl, fallbackIcon: Icons.person_rounded, radius: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(customer.fullName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      customer.email ?? customer.phone ?? 'No contact info',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${customer.totalBookings}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kPrimaryGreen)),
                  Text('bookings', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Providers tab
// ---------------------------------------------------------------------------

class _ProvidersTab extends StatefulWidget {
  final String accessToken;
  const _ProvidersTab({super.key, required this.accessToken});

  @override
  State<_ProvidersTab> createState() => _ProvidersTabState();
}

class _ProvidersTabState extends State<_ProvidersTab> {
  Future<List<AdminProvider>>? _future;
  final _searchController = TextEditingController();
  String _query = '';
  String? _statusFilter; // null = All

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _load() {
    setState(() {
      _future = AdminService.getProviders(
        accessToken: widget.accessToken,
        query: _query,
        verificationStatus: _statusFilter,
      );
    });
  }

  /// Called by the parent dashboard (via GlobalKey) when the admin taps
  /// the "pending review" shortcut on the Overview tab.
  void applyFilter(String status) {
    setState(() => _statusFilter = status);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: _SearchField(
            controller: _searchController,
            hint: 'Search by name, email or service',
            onSubmitted: (v) {
              _query = v;
              _load();
            },
            onCleared: () {
              _query = '';
              _load();
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(label: 'All', selected: _statusFilter == null, onTap: () {
                  setState(() => _statusFilter = null);
                  _load();
                }),
                const SizedBox(width: 8),
                _FilterChip(label: 'Pending', selected: _statusFilter == 'pending', onTap: () {
                  setState(() => _statusFilter = 'pending');
                  _load();
                }),
                const SizedBox(width: 8),
                _FilterChip(label: 'Verified', selected: _statusFilter == 'verified', onTap: () {
                  setState(() => _statusFilter = 'verified');
                  _load();
                }),
                const SizedBox(width: 8),
                _FilterChip(label: 'Rejected', selected: _statusFilter == 'rejected', onTap: () {
                  setState(() => _statusFilter = 'rejected');
                  _load();
                }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              _load();
              await _future;
            },
            child: FutureBuilder<List<AdminProvider>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _ErrorState(message: _errorText(snapshot.error), onRetry: _load);
                }

                final providers = snapshot.data!;
                if (providers.isEmpty) {
                  return _EmptyState(
                    icon: Icons.engineering_outlined,
                    message: _query.isEmpty ? 'No providers match this filter.' : 'No providers match "$_query".',
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: providers.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _ProviderCard(
                    provider: providers[i],
                    onTap: () async {
                      final changed = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AdminProviderDetailPage(
                            accessToken: widget.accessToken,
                            providerId: providers[i].id,
                          ),
                        ),
                      );
                      if (changed == true) _load();
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _ProviderCard extends StatelessWidget {
  final AdminProvider provider;
  final VoidCallback onTap;
  const _ProviderCard({required this.provider, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
          child: Row(
            children: [
              _Avatar(url: provider.profilePictureUrl, fallbackIcon: Icons.engineering_rounded, radius: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(provider.fullName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      provider.serviceCategory ?? 'No service set',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    VerificationStatusChip(status: provider.verificationStatus),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared small widgets, reused by the provider detail page too.
// ---------------------------------------------------------------------------

class VerificationStatusChip extends StatelessWidget {
  final String status;
  const VerificationStatusChip({super.key, required this.status});

  Color get _color {
    switch (status) {
      case 'verified':
        return Colors.green.shade600;
      case 'rejected':
        return Colors.red.shade600;
      default:
        return Colors.orange.shade700;
    }
  }

  IconData get _icon {
    switch (status) {
      case 'verified':
        return Icons.verified_rounded;
      case 'rejected':
        return Icons.cancel_rounded;
      default:
        return Icons.pending_rounded;
    }
  }

  String get _label {
    switch (status) {
      case 'verified':
        return 'Verified';
      case 'rejected':
        return 'Rejected';
      default:
        return 'Pending Review';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: _color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: 12, color: _color),
          const SizedBox(width: 4),
          Text(_label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _color)),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? url;
  final IconData fallbackIcon;
  final double radius;
  const _Avatar({required this.url, required this.fallbackIcon, required this.radius});

  @override
  Widget build(BuildContext context) {
    if (url == null) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: kLightGreenBg,
        child: Icon(fallbackIcon, color: kPrimaryGreen, size: radius * 0.9),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: kLightGreenBg,
      backgroundImage: NetworkImage('$apiBaseUrl$url'),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onCleared;

  const _SearchField({required this.controller, required this.hint, required this.onSubmitted, required this.onCleared});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search_rounded, color: kDarkText),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            if (value.text.isEmpty) return const SizedBox.shrink();
            return IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: () {
                controller.clear();
                onCleared();
              },
            );
          },
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kDarkText)),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: kDarkText,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: selected ? Colors.white : kDarkText,
      ),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.grey.shade300)),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _DetailRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade500),
          const SizedBox(width: 10),
          SizedBox(width: 110, child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: kDarkText))),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 40, color: Colors.red.shade400),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }
}

String _formatDate(DateTime dt) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
}

String _errorText(Object? error) {
  if (error is AdminServiceException) return error.message;
  return 'Something went wrong. Please try again.';
}