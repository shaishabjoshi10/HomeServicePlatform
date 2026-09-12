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
              _RoleCard(
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
              const SizedBox(height: 20),
              _RoleCard(
                icon: Icons.engineering_rounded,
                title: 'Service Provider Login',
                subtitle:
                'Manage bookings, grow your business and serve more customers.',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LoginPage(role: UserRole.provider),
                  ),
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