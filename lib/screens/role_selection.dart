import 'package:flutter/material.dart';
import '../main.dart';
import 'login.dart';
import 'signup.dart';

class RoleSelectionPage extends StatelessWidget {
  const RoleSelectionPage({super.key});

  void _showSignupRolePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _SignupRoleSheet(
        onPick: (role) {
          Navigator.pop(context); // close the sheet
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SignupPage(role: role)),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 40),
              Icon(Icons.home_repair_service_rounded,
                  color: kAccentGreen, size: 56),
              const SizedBox(height: 8),
              RichText(
                text: const TextSpan(
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                  children: [
                    TextSpan(text: 'Ghar', style: TextStyle(color: kDarkText)),
                    TextSpan(text: 'Sewa', style: TextStyle(color: kAccentGreen)),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Home Services, Simplified.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 48),
              Text(
                'Welcome',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: kDarkText,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose your login type to continue',
                style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 40),
              // Customer and Service Provider login sit side by side as two
              // equal-width cards rather than stacked, so both are visible
              // and selectable at a glance without scrolling past one to
              // reach the other. Each keeps its own icon, title, and short
              // description, with a gap and a border between them so the
              // two stay clearly separated even though they share a row.
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _LoginOptionCard(
                        icon: Icons.people_alt_rounded,
                        title: 'Customer Login',
                        subtitle: 'Book trusted home services quickly and easily.',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const LoginPage(role: UserRole.customer),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _LoginOptionCard(
                        icon: Icons.engineering_rounded,
                        title: 'Service Provider Login',
                        subtitle: 'Manage bookings and serve more customers.',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const LoginPage(role: UserRole.provider),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Don't have an account? ",
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  GestureDetector(
                    onTap: () => _showSignupRolePicker(context),
                    child: const Text(
                      'Sign Up',
                      style: TextStyle(
                        color: kPrimaryGreen,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet shown from the "Sign Up" link so the user can pick which
/// kind of account to create before landing on SignupPage.
class _SignupRoleSheet extends StatelessWidget {
  final ValueChanged<UserRole> onPick;

  const _SignupRoleSheet({required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            'Sign up as',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: kDarkText),
          ),
          const SizedBox(height: 16),
          _RoleCard(
            icon: Icons.people_alt_rounded,
            title: 'Customer',
            subtitle: 'Book trusted home services quickly and easily.',
            onTap: () => onPick(UserRole.customer),
          ),
          const SizedBox(height: 12),
          _RoleCard(
            icon: Icons.engineering_rounded,
            title: 'Service Provider',
            subtitle: 'Manage bookings and grow your business.',
            onTap: () => onPick(UserRole.provider),
          ),
        ],
      ),
    );
  }
}

/// A single login option shown side by side with the other role's, on the
/// welcome screen. Laid out vertically (icon above title above subtitle)
/// rather than in a row, since each card only gets half the screen's width
/// here — [_RoleCard]'s left-icon/right-chevron row layout is for the
/// full-width cards in the sign-up sheet instead.
class _LoginOptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _LoginOptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          // A visible border, on top of the shadow, keeps the two cards
          // reading as clearly separate options even when they sit right
          // next to each other in the same row.
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: kLightGreenBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: kPrimaryGreen, size: 28),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: kDarkText,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: kLightGreenBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: kPrimaryGreen, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: kDarkText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: kLightGreenBg,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.chevron_right_rounded,
                  color: kPrimaryGreen,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}