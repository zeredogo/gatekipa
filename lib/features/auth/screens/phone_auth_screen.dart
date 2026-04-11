// lib/features/auth/screens/phone_auth_screen.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class PhoneAuthScreen extends ConsumerStatefulWidget {
  const PhoneAuthScreen({super.key});
  @override
  ConsumerState<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends ConsumerState<PhoneAuthScreen> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _biometricAvailable = false;
  bool _isBiometricLoading = false;

  @override
  void initState() {
    super.initState();
    _checkBiometricAvailability();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Shows the biometric button only when:
  /// 1. There is an active Firebase session (lock mode, not full sign-out)
  /// 2. The user had biometrics enabled before locking
  Future<void> _checkBiometricAvailability() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return; // Full sign-out → no biometric shortcut

    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('${user.uid}_use_biometrics') ?? false;
    if (!enabled) return;

    // Also verify hardware is actually available
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

  Future<void> _sendOtp() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final phone = '+234${_controller.text.replaceFirst(RegExp(r'^0'), '')}';

    ref.read(authNotifierProvider.notifier).sendOtp(
          phoneNumber: phone,
          onError: (msg) {
            setState(() => _isLoading = false);
            if (mounted) {
              GkToast.show(context,
                  message: msg, type: ToastType.error, title: 'OTP Error');
            }
          },
          onCodeSent: () {
            setState(() => _isLoading = false);
            if (mounted) {
              context.push(Routes.otp, extra: phone);
            }
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: const BackButton(color: AppColors.onSurface),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.phone_rounded,
                    color: AppColors.primary, size: 28),
              ).animate().scale(duration: 400.ms, curve: Curves.elasticOut),
              const SizedBox(height: 24),
              Text(
                'Enter your\nphone number',
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
                "We'll send a verification code. Standard rates may apply.",
                style: GoogleFonts.inter(
                  fontSize: 15,
                  color: AppColors.onSurfaceVariant,
                  height: 1.5,
                ),
              ).animate().fadeIn(delay: 200.ms),
              const SizedBox(height: 40),
              // Phone input
              TextFormField(
                controller: _controller,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(11),
                ],
                style: GoogleFonts.manrope(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
                decoration: InputDecoration(
                  prefixIcon: Container(
                    margin: const EdgeInsets.only(left: 12, right: 12),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '🇳🇬  +234',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface,
                      ),
                    ),
                  ),
                  prefixIconConstraints: const BoxConstraints(),
                  hintText: '08012345678',
                  hintStyle: const TextStyle(
                      color: AppColors.outline,
                      fontWeight: FontWeight.w500,
                      fontSize: 18),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                        color:
                            AppColors.outlineVariant.withValues(alpha: 0.3),
                        width: 1.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide:
                        const BorderSide(color: AppColors.primary, width: 2),
                  ),
                  filled: true,
                  fillColor: AppColors.surfaceBright,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 20),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) {
                    return 'Enter your phone number';
                  }
                  if (v.length < 10) return 'Enter a valid Nigerian number';
                  return null;
                },
              ).animate().fadeIn(delay: 300.ms),
              const SizedBox(height: 20),
              Center(
                child: Text(
                  'By continuing, you agree to our Terms of Service\nand Privacy Policy.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.outline,
                    height: 1.6,
                  ),
                ),
              ).animate().fadeIn(delay: 400.ms),
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
                onPressed: _isLoading ? null : _sendOtp,
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
                          const Icon(Icons.send_rounded, size: 18),
                          const SizedBox(width: 10),
                          Text(
                            'Send Verification Code',
                            style: GoogleFonts.manrope(
                                fontWeight: FontWeight.w800, fontSize: 15),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => context.pushReplacement(Routes.emailAuth),
              icon: const Icon(Icons.email_rounded, size: 20),
              label: Text(
                'Continue with Email instead',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
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
