// lib/features/auth/screens/otp_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gatekipa/core/constants/routes.dart';
import 'package:gatekipa/core/theme/app_colors.dart';
import 'package:gatekipa/core/widgets/gk_toast.dart';
import 'package:gatekipa/features/auth/providers/auth_provider.dart';
import 'package:gatekipa/core/theme/app_spacing.dart';

class OtpScreen extends ConsumerStatefulWidget {
  final String phoneNumber;
  const OtpScreen({super.key, required this.phoneNumber});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  bool _isLoading = false;
  bool _isResending = false;

  // Resend countdown
  int _resendSeconds = 60;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
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

  @override
  void dispose() {
    _resendTimer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _otp => _controllers.map((c) => c.text).join();

  Future<void> _verify() async {
    final otp = _otp;
    if (otp.length != 6) {
      GkToast.show(context,
          message: 'Please enter the 6-digit code', type: ToastType.warning);
      return;
    }
    setState(() => _isLoading = true);
    final success =
        await ref.read(authNotifierProvider.notifier).verifyOtp(otp);
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (success) {
      final user = ref.read(authStateProvider).value;
      if (user?.displayName == null) {
        context.go(Routes.kyc);
      } else {
        context.go(Routes.dashboard);
      }
    } else {
      GkToast.show(context,
          message: 'Invalid code. Please try again.',
          type: ToastType.error,
          title: 'Verification Failed');
      // Clear boxes on failure
      for (final c in _controllers) {
        c.clear();
      }
      _focusNodes[0].requestFocus();
    }
  }

  Future<void> _resendOtp() async {
    if (_resendSeconds > 0) return;
    setState(() => _isResending = true);

    ref.read(authNotifierProvider.notifier).sendOtp(
          phoneNumber: widget.phoneNumber,
          onError: (msg) {
            if (mounted) {
              setState(() => _isResending = false);
              GkToast.show(context,
                  message: msg, type: ToastType.error, title: 'Resend Failed');
            }
          },
          onCodeSent: () {
            if (mounted) {
              setState(() => _isResending = false);
              for (final c in _controllers) {
                c.clear();
              }
              _focusNodes[0].requestFocus();
              _startResendTimer();
              GkToast.show(context,
                  message: 'New code sent to ${widget.phoneNumber}',
                  type: ToastType.success);
            }
          },
        );
  }

  /// Handle paste: fill all 6 boxes from clipboard
  Future<void> _handlePaste() async {
    final data = await Clipboard.getData('text/plain');
    final text = (data?.text ?? '').replaceAll(RegExp(r'\D'), '');
    if (text.length >= 6) {
      for (int i = 0; i < 6; i++) {
        _controllers[i].text = text[i];
      }
      setState(() {});
      _focusNodes[5].requestFocus();
      // Auto-submit after paste
      await Future.delayed(const Duration(milliseconds: 300));
      _verify();
    }
  }

  void _onDigitChanged(String val, int idx) {
    if (val.length > 1) {
      // Handle paste via keyboard (e.g. Android SMS autofill)
      final digits = val.replaceAll(RegExp(r'\D'), '');
      if (digits.length >= 6) {
        for (int i = 0; i < 6; i++) {
          _controllers[i].text = digits[i];
        }
        setState(() {});
        _focusNodes[5].requestFocus();
        Future.delayed(const Duration(milliseconds: 300), _verify);
        return;
      }
      // If 2 digits pasted in single box, keep last
      _controllers[idx].text = val[val.length - 1];
    }

    if (val.isNotEmpty && idx < 5) {
      _focusNodes[idx + 1].requestFocus();
    } else if (val.isEmpty && idx > 0) {
      _focusNodes[idx - 1].requestFocus();
    }
    setState(() {});

    // Auto-submit when all 6 digits filled
    if (_otp.length == 6) {
      Future.delayed(const Duration(milliseconds: 200), _verify);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final canResend = _resendSeconds == 0;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: const BackButton(color: AppColors.onSurface),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
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
              child: const Icon(Icons.sms_rounded,
                  color: AppColors.primary, size: 28),
            ).animate().scale(duration: 400.ms, curve: Curves.elasticOut),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Enter verification\ncode',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 32,
                fontWeight: FontWeight.w800,
                color: AppColors.onSurface,
                height: 1.2,
                letterSpacing: -0.5,),
            ).animate().fadeIn(delay: 100.ms),
            const SizedBox(height: AppSpacing.sm),
            RichText(
              text: TextSpan(
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 15,
                  color: AppColors.onSurfaceVariant,
                  height: 1.5,),
                children: [
                  const TextSpan(text: 'Code sent to '),
                  TextSpan(
                    text: widget.phoneNumber,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700,
                      color: AppColors.primary,),
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 200.ms),
            const SizedBox(height: 40),

            // ── OTP input boxes ──────────────────────────────────────────
            GestureDetector(
              onLongPress: _handlePaste,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(6, (i) {
                  final isFilled = _controllers[i].text.isNotEmpty;
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: i == 5 ? 0 : 8.0),
                      child: SizedBox(
                        height: 64,
                        child: TextFormField(
                          controller: _controllers[i],
                          focusNode: _focusNodes[i],
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          maxLength: 6, // Allow 6 for paste-in-box handling
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,),
                          decoration: InputDecoration(
                            counterText: '',
                            contentPadding: EdgeInsets.zero,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: isFilled
                                    ? AppColors.primary.withValues(alpha: 0.6)
                                    : AppColors.outlineVariant
                                        .withValues(alpha: 0.3),
                                width: isFilled ? 2 : 1.5,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                  color: AppColors.primary, width: 2.5),
                            ),
                            filled: true,
                            fillColor: isFilled
                                ? AppColors.primary.withValues(alpha: 0.04)
                                : AppColors.surfaceBright,
                          ),
                          onChanged: (val) => _onDigitChanged(val, i),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ).animate().fadeIn(delay: 300.ms),
            const SizedBox(height: AppSpacing.md),

            // Paste hint
            Center(
              child: TextButton.icon(
                onPressed: _handlePaste,
                icon: const Icon(Icons.content_paste_rounded,
                    size: 16, color: AppColors.outline),
                label: const Text(
                  'Paste code',
                  style: TextStyle(height: 1.2, fontFamily: 'Manrope', color: AppColors.outline,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,),
                ),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                ),
              ),
            ),
          ],
        ),
      ),

      // ── Sticky bottom action bar ──────────────────────────────────────
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
                onPressed: _isLoading ? null : _verify,
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
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.verified_rounded, size: 20),
                          SizedBox(width: 10),
                          Text(
                            'Verify & Continue',
                            style: TextStyle(height: 1.2, fontFamily: 'Manrope', fontWeight: FontWeight.w800, fontSize: 16),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "Didn't receive a code? ",
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14,
                    color: AppColors.onSurfaceVariant,),
                ),
                GestureDetector(
                  onTap: canResend ? _resendOtp : null,
                  child: _isResending
                      ? const SizedBox(
                          height: 14,
                          width: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.primary),
                        )
                      : Text(
                          canResend
                              ? 'Resend'
                              : 'Resend in ${_resendSeconds}s',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: canResend
                                ? AppColors.primary
                                : AppColors.outline,
                            decoration: canResend
                                ? TextDecoration.underline
                                : TextDecoration.none,),
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
