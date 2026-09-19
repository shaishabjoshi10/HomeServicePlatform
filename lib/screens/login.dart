import 'package:flutter/material.dart';
import '../main.dart';
import '../services/auth_service.dart';
import 'customer_home.dart';
import 'serviceprovider_home.dart';
import 'signup.dart';
import '../widgets/app_logo.dart';

enum UserRole { customer, provider }

/// The app's single entry screen: branding, a side-by-side "I am a
/// Customer" / "I am a Service Provider" toggle, and the login form for
/// whichever role is currently selected. There is no separate role-
/// selection screen — picking a role and logging in both happen here.
class LoginPage extends StatefulWidget {
  /// Which role's option is highlighted (and whose form is shown) when the
  /// screen first appears. Defaults to [UserRole.customer]. Callers that
  /// already know the relevant role — e.g. returning here after signing up
  /// as a provider, or after a provider logs out — can pass it so the user
  /// doesn't have to reselect it.
  final UserRole? role;

  const LoginPage({super.key, this.role});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  late UserRole _selectedRole;

  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _submitted = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _selectedRole = widget.role ?? UserRole.customer;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Switches which role's login the form submits as. Also clears any
  /// error from the previous role's attempt and resets validation display,
  /// since a message like "Invalid password" belongs to the login attempt
  /// that produced it, not to whichever role is selected next.
  void _selectRole(UserRole role) {
    if (role == _selectedRole) return;
    setState(() {
      _selectedRole = role;
      _errorMessage = null;
      _submitted = false;
    });
  }

  String? _validateIdentifier(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter your email or phone number';

    final isEmailLike = v.contains('@');
    if (isEmailLike) {
      final emailRegex = RegExp(r'^[\w\.\-\+]+@[\w\-]+\.[a-zA-Z]{2,}$');
      if (!emailRegex.hasMatch(v)) return 'Enter a valid email address';
    } else {
      final digitsOnly = v.replaceAll(RegExp(r'[^0-9]'), '');
      if (digitsOnly.length < 7) return 'Enter a valid phone number';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Enter your password';
    if (v.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  Future<void> _handleLogin() async {
    setState(() {
      _errorMessage = null;
      _submitted = true;
    });

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final roleString = _selectedRole == UserRole.customer ? 'customer' : 'provider';

      final result = await AuthService.login(
        identifier: _emailController.text,
        password: _passwordController.text,
        role: roleString,
      );

      // TODO: persist result.accessToken securely (e.g. flutter_secure_storage)
      // so it can be attached as a Bearer token on future API calls.

      if (!mounted) return;

      if (_selectedRole == UserRole.customer) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => CustomerHomePage(
              userName: result.user.fullName,
              userEmail: result.user.email ?? result.user.phone ?? '',
              accessToken: result.accessToken,
            ),
          ),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ServiceProviderHomePage(
              providerName: result.user.fullName,
              accessToken: result.accessToken,
            ),
          ),
        );
      }
    } on AuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = 'Something went wrong. Please check your connection.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isProvider = _selectedRole == UserRole.provider;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 32),
              const AppLogo(size: 56),
              const SizedBox(height: 8),
              RichText(
                text: const TextSpan(
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
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
              const SizedBox(height: 32),
              Text(
                'Welcome',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: kDarkText),
              ),
              const SizedBox(height: 6),
              Text(
                'Select how you\'d like to continue',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 20),

              // Role toggle: the two options sit side by side so both are
              // visible at once, with the selected one clearly highlighted.
              // Choosing a role here simply swaps which login the form
              // below submits as — there's no separate screen to navigate
              // to.
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _RoleToggleCard(
                        icon: Icons.people_alt_rounded,
                        label: 'I am a Customer',
                        isSelected: _selectedRole == UserRole.customer,
                        onTap: () => _selectRole(UserRole.customer),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _RoleToggleCard(
                        icon: Icons.engineering_rounded,
                        label: 'I am a Service Provider',
                        isSelected: _selectedRole == UserRole.provider,
                        onTap: () => _selectRole(UserRole.provider),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Inline error banner — driven entirely by backend response
              if (_errorMessage != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline_rounded, color: Colors.red.shade400, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(fontSize: 13, color: Colors.red.shade700),
                        ),
                      ),
                    ],
                  ),
                ),

              // Keyed on the selected role so switching roles rebuilds the
              // form fresh — clearing any field-level validation styling
              // left over from the other role's attempt.
              Form(
                key: _formKey,
                autovalidateMode: _submitted ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isProvider
                          ? 'Login to continue as a Service Provider'
                          : 'Login to continue as a Customer',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Email or Phone Number',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: kDarkText),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      validator: _validateIdentifier,
                      decoration: InputDecoration(
                        hintText: 'Enter your email or phone number',
                        prefixIcon: const Icon(Icons.person_outline_rounded, color: kPrimaryGreen),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: kPrimaryGreen),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Password',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: kDarkText),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      validator: _validatePassword,
                      decoration: InputDecoration(
                        hintText: 'Enter your password',
                        prefixIcon: const Icon(Icons.lock_outline_rounded, color: kPrimaryGreen),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            color: Colors.grey.shade600,
                          ),
                          onPressed: () {
                            setState(() => _obscurePassword = !_obscurePassword);
                          },
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: kPrimaryGreen),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          // TODO: navigate to forgot password flow
                        },
                        child: const Text(
                          'Forgot Password?',
                          style: TextStyle(color: kPrimaryGreen, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _isLoading ? null : _handleLogin,
                        style: FilledButton.styleFrom(
                          backgroundColor: kPrimaryGreen,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                            : const Text('Login', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("Don't have an account? ", style: TextStyle(color: Colors.grey.shade600)),
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => SignupPage(role: _selectedRole)),
                            );
                          },
                          child: const Text(
                            'Sign Up',
                            style: TextStyle(color: kPrimaryGreen, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One half of the role toggle at the top of the login screen. Shows
/// filled/bordered in the app's green when selected, and a plain outline
/// otherwise, so the current choice is unambiguous even with both options
/// sitting side by side.
class _RoleToggleCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _RoleToggleCard({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? kLightGreenBg : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? kPrimaryGreen : Colors.grey.shade300,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: isSelected ? kPrimaryGreen : Colors.grey.shade500, size: 26),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? kPrimaryGreen : Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}