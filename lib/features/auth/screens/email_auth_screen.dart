// lib/features/auth/screens/email_auth_screen.dart
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/gk_toast.dart';
import '../providers/auth_provider.dart';

class EmailAuthScreen extends ConsumerStatefulWidget {
  const EmailAuthScreen({super.key});

  @override
  ConsumerState<EmailAuthScreen> createState() => _EmailAuthScreenState();
}

class _EmailAuthScreenState extends ConsumerState<EmailAuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _biometricAvailable = false;
  bool _isBiometricLoading = false;

  @override
  void initState() {
    super.initState();
    _checkBiometricAvailability();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  /// Shows the biometric button only when:
  /// 1. There is an active Firebase session (lock mode, not full sign-out)
  /// 2. The user had biometrics enabled before locking
  Future<void> _checkBiometricAvailability() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('${user.uid}_use_biometrics') ?? false;
    if (!enabled) return;

    final localAuth = LocalAuthentication();
    final canCheck = await localAuth.canCheckBiometrics;
    final isSupported = await localAuth.isDeviceSupported();

    if (mounted) {
      setState(() => _biometricAvailable = canCheck || isSupported);
    }
  }

  Future<void> _authenticateWithBiometrics() async {
    setState(() => _isBiometricLoading = true);
    try {
      final localAuth = LocalAuthentication();
      final authenticated = await localAuth.authenticate(
        localizedReason: 'Verify your identity to unlock Gatekipa',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
      if (!mounted) return;
      if (authenticated) {
        context.go(Routes.dashboard);
      } else {
        GkToast.show(context,
            message: 'Biometric verification failed. Please try again.',
            type: ToastType.error);
      }
    } catch (e) {
      if (mounted) {
        GkToast.show(context,
            message: 'Biometrics unavailable. Please sign in manually.',
            type: ToastType.error);
        setState(() => _biometricAvailable = false);
      }
    } finally {
      if (mounted) setState(() => _isBiometricLoading = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    try {
      if (_isLogin) {
        await ref
            .read(authNotifierProvider.notifier)
            .signInWithEmail(email, password);

        if (!mounted) return;

        // Check email verified
        final user = FirebaseAuth.instance.currentUser;
        if (user != null && !user.emailVerified) {
          // Send a fresh verification email and redirect to pending screen
          await user.sendEmailVerification();
          if (mounted) {
            context.pushReplacement(Routes.emailVerifyPending,
                extra: email);
          }
          return;
        }
        if (mounted) context.go(Routes.dashboard);
      } else {
        // Sign Up
        await ref.read(authNotifierProvider.notifier).signUpWithEmail(
              email,
              password,
              firstName: _firstNameController.text.trim(),
              lastName: _lastNameController.text.trim(),
              address: _addressController.text.trim(),
            );

        if (!mounted) return;

        // Send verification email
        final user = FirebaseAuth.instance.currentUser;
        if (user != null && !user.emailVerified) {
          await user.sendEmailVerification();
        }

        if (mounted) {
          GkToast.show(context,
              message: 'Account created! Please verify your email.',
              type: ToastType.success);
          context.pushReplacement(Routes.emailVerifyPending, extra: email);
        }
      }
    } catch (e) {
      if (!mounted) return;
      String msg = e.toString();
      if (e is FirebaseAuthException) {
        msg = e.message ?? 'Authentication failed. Please try again.';
      } else {
        msg = msg.replaceAll(RegExp(r'\[.*?\]\s*'), '');
      }
      GkToast.show(
        context,
        message: msg,
        type: ToastType.error,
        title: 'Authentication Error',
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: isPassword && _obscurePassword,
      keyboardType: keyboardType,
      style: GoogleFonts.inter(
        fontSize: 16,
        color: AppColors.onSurface,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.inter(
          color: AppColors.outline,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        prefixIcon: Icon(icon, color: AppColors.primary.withValues(alpha: 0.7)),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: AppColors.outline,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
              color: AppColors.outlineVariant.withValues(alpha: 0.3),
              width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        filled: true,
        fillColor: AppColors.surfaceBright,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      ),
      validator: validator,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(color: AppColors.onSurface),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.email_rounded,
                    color: AppColors.primary, size: 28),
              ).animate().scale(duration: 400.ms, curve: Curves.elasticOut),
              const SizedBox(height: 24),
              Text(
                _isLogin ? 'Welcome Back' : 'Create Account',
                style: GoogleFonts.manrope(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: AppColors.onSurface,
                  height: 1.2,
                  letterSpacing: -0.5,
                ),
              ).animate().fadeIn(delay: 100.ms),
              const SizedBox(height: 12),
              Text(
                _isLogin
                    ? 'Sign in to access your secure vault.'
                    : 'Start protecting your subscriptions today.',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  color: AppColors.onSurfaceVariant,
                  height: 1.5,
                ),
              ).animate().fadeIn(delay: 200.ms),
              const SizedBox(height: 36),

              if (!_isLogin) ...[
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _firstNameController,
                        label: 'First Name',
                        icon: Icons.person_outline_rounded,
                        validator: (v) =>
                            (v == null || v.isEmpty) ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildTextField(
                        controller: _lastNameController,
                        label: 'Last Name',
                        icon: Icons.person_outline_rounded,
                        validator: (v) =>
                            (v == null || v.isEmpty) ? 'Required' : null,
                      ),
                    ),
                  ],
                ).animate().fadeIn(delay: 250.ms).slideX(begin: 0.05, end: 0),
                const SizedBox(height: 20),
                _buildTextField(
                  controller: _addressController,
                  label: 'Full Address',
                  icon: Icons.home_work_outlined,
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Enter your address' : null,
                ).animate().fadeIn(delay: 280.ms).slideX(begin: 0.05, end: 0),
                const SizedBox(height: 20),
              ],

              // Email Field
              _buildTextField(
                controller: _emailController,
                label: 'Email Address',
                icon: Icons.alternate_email_rounded,
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Enter your email';
                  if (!v.contains('@')) return 'Enter a valid email';
                  return null;
                },
              ).animate().fadeIn(delay: 300.ms).slideX(begin: 0.05, end: 0),
              const SizedBox(height: 20),

              // Password Field
              _buildTextField(
                controller: _passwordController,
                label: 'Password',
                icon: Icons.lock_outline_rounded,
                isPassword: true,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Enter your password';
                  if (v.length < 6) {
                    return 'Password must be at least 6 characters';
                  }
                  return null;
                },
              ).animate().fadeIn(delay: 400.ms).slideX(begin: 0.05, end: 0),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),

      // ── Sticky bottom action bar ────────────────────────────────────────
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(24, 16, 24, bottomPad + 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton(
                onPressed: _isLoading ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor:
                      AppColors.primary.withValues(alpha: 0.5),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isLogin
                                ? Icons.login_rounded
                                : Icons.person_add_rounded,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _isLogin ? 'Sign In' : 'Create Account',
                            style: GoogleFonts.manrope(
                                fontWeight: FontWeight.w800, fontSize: 16),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () {
                _formKey.currentState?.reset();
                setState(() {
                  _isLogin = !_isLogin;
                  _emailController.clear();
                  _passwordController.clear();
                  _firstNameController.clear();
                  _lastNameController.clear();
                  _addressController.clear();
                });
              },
              child: Text(
                _isLogin
                    ? "Don't have an account? Sign Up"
                    : 'Already have an account? Sign In',
                style: GoogleFonts.inter(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () => context.pushReplacement(Routes.phoneAuth),
              icon: const Icon(Icons.phone_rounded, size: 18),
              label: Text(
                'Use Phone Number instead',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.onSurfaceVariant,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              ),
            ),
            // ── Biometric quick-unlock (only shown in lock mode) ────────────
            if (_biometricAvailable) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Divider(height: 1),
              ),
              _BiometricUnlockButton(
                isLoading: _isBiometricLoading,
                onTap: _authenticateWithBiometrics,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Shared biometric unlock button ────────────────────────────────────────────
class _BiometricUnlockButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onTap;

  const _BiometricUnlockButton({required this.isLoading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final displayName = FirebaseAuth.instance.currentUser?.displayName;

    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.2),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    color: AppColors.primary, strokeWidth: 2),
              )
            else
              const Icon(Icons.fingerprint_rounded,
                  color: AppColors.primary, size: 26),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isLoading ? 'Verifying...' : 'Use Biometrics',
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                if (displayName != null && displayName.isNotEmpty)
                  Text(
                    'Continue as $displayName',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppColors.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.1, end: 0);
  }
}
