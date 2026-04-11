// lib/features/auth/screens/email_verify_pending_screen.dart
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/gk_toast.dart';

class EmailVerifyPendingScreen extends StatefulWidget {
  final String email;
  const EmailVerifyPendingScreen({super.key, required this.email});

  @override
  State<EmailVerifyPendingScreen> createState() =>
      _EmailVerifyPendingScreenState();
}

class _EmailVerifyPendingScreenState extends State<EmailVerifyPendingScreen> {
  bool _isChecking = false;
  bool _isResending = false;
  int _resendSeconds = 60;
  Timer? _resendTimer;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
    _startPolling();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendSeconds <= 0) {
        t.cancel();
      } else {
        if (mounted) setState(() => _resendSeconds--);
      }
    });
  }

  /// Poll Firebase every 5 seconds to auto-advance when email is verified
  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      await _checkVerified(silent: true);
    });
  }

  Future<void> _checkVerified({bool silent = false}) async {
    if (_isChecking) return;
    if (!silent) setState(() => _isChecking = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      await user.reload();
      final refreshed = FirebaseAuth.instance.currentUser;

      if (refreshed?.emailVerified == true) {
        _pollTimer?.cancel();
        if (mounted) {
          GkToast.show(context,
              message: 'Email verified! Welcome to Gatekipa.',
              type: ToastType.success);
          context.go(Routes.kyc);
        }
      } else {
        if (!silent && mounted) {
          GkToast.show(context,
              message: 'Email not verified yet. Please check your inbox.',
              type: ToastType.warning);
        }
      }
    } catch (_) {
    } finally {
      if (!silent && mounted) setState(() => _isChecking = false);
    }
  }

  Future<void> _resendEmail() async {
    if (_resendSeconds > 0) return;
    setState(() => _isResending = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      await user?.sendEmailVerification();
      if (mounted) {
        GkToast.show(context,
            message: 'Verification email resent to ${widget.email}',
            type: ToastType.success);
        _startResendTimer();
      }
    } catch (e) {
      if (mounted) {
        GkToast.show(context,
            message: 'Failed to resend. Try again later.',
            type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final canResend = _resendSeconds == 0;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.onSurface),
          onPressed: () => context.go(Routes.emailAuth),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 24),
            // Animated email icon
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.mark_email_unread_rounded,
                color: AppColors.primary,
                size: 52,
              ),
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scaleXY(begin: 1.0, end: 1.05, duration: 1200.ms),
            const SizedBox(height: 36),
            Text(
              'Check your email',
              style: GoogleFonts.manrope(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: AppColors.onSurface,
                letterSpacing: -0.5,
              ),
              textAlign: TextAlign.center,
            ).animate().fadeIn(delay: 100.ms),
            const SizedBox(height: 16),
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: GoogleFonts.inter(
                  fontSize: 15,
                  color: AppColors.onSurfaceVariant,
                  height: 1.6,
                ),
                children: [
                  const TextSpan(
                      text: 'We sent a verification link to\n'),
                  TextSpan(
                    text: widget.email,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  const TextSpan(
                      text:
                          '\n\nClick the link in that email to verify your account and access your Gatekipa vault.'),
                ],
              ),
            ).animate().fadeIn(delay: 200.ms),
            const SizedBox(height: 40),

            // Steps guide
            const _StepTile(
              step: '1',
              text: 'Open your email app',
              icon: Icons.open_in_new_rounded,
            ).animate().fadeIn(delay: 300.ms).slideX(begin: 0.06, end: 0),
            const SizedBox(height: 12),
            const _StepTile(
              step: '2',
              text: 'Find the email from Gatekipa',
              icon: Icons.search_rounded,
            ).animate().fadeIn(delay: 380.ms).slideX(begin: 0.06, end: 0),
            const SizedBox(height: 12),
            const _StepTile(
              step: '3',
              text: 'Click "Verify Email" in the message',
              icon: Icons.touch_app_rounded,
            ).animate().fadeIn(delay: 460.ms).slideX(begin: 0.06, end: 0),
            const SizedBox(height: 12),
            const _StepTile(
              step: '4',
              text: 'Come back and tap "I\'ve Verified" below',
              icon: Icons.check_circle_outline_rounded,
            ).animate().fadeIn(delay: 540.ms).slideX(begin: 0.06, end: 0),
            const SizedBox(height: 24),
          ],
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
                onPressed: _isChecking ? null : () => _checkVerified(),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor:
                      AppColors.primary.withValues(alpha: 0.5),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: _isChecking
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.verified_rounded, size: 20),
                          const SizedBox(width: 10),
                          Text(
                            "I've Verified My Email",
                            style: GoogleFonts.manrope(
                                fontWeight: FontWeight.w800, fontSize: 15),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "Didn't get an email? ",
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                GestureDetector(
                  onTap: canResend ? _resendEmail : null,
                  child: _isResending
                      ? const SizedBox(
                          height: 14,
                          width: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.primary),
                        )
                      : Text(
                          canResend
                              ? 'Resend email'
                              : 'Resend in ${_resendSeconds}s',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: canResend
                                ? AppColors.primary
                                : AppColors.outline,
                            decoration: canResend
                                ? TextDecoration.underline
                                : TextDecoration.none,
                          ),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  final String step;
  final String text;
  final IconData icon;
  const _StepTile(
      {required this.step, required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceBright,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: AppColors.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                step,
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: AppColors.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Icon(icon, size: 18, color: AppColors.outline),
        ],
      ),
    );
  }
}
