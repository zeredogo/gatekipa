// lib/features/auth/screens/kyc_screen.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:gatekipa/core/constants/routes.dart';
import 'package:gatekipa/core/theme/app_colors.dart';
import 'package:gatekipa/core/widgets/gk_button.dart';
import 'package:gatekipa/core/widgets/gk_toast.dart';
import 'package:gatekipa/core/theme/app_spacing.dart';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:gatekipa/features/wallet/widgets/otp_dialog.dart';

class KycScreen extends StatefulWidget {
  const KycScreen({super.key});
  @override
  State<KycScreen> createState() => _KycScreenState();
}

class _KycScreenState extends State<KycScreen> {
  bool _isLoading = false;
  final _bvnController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _bvnController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      
      final bvn = _bvnController.text.trim();

      // 1. Save BVN
      final verifyBvnCallable = FirebaseFunctions.instance.httpsCallable('verifyBvn');
      await verifyBvnCallable.call({'bvn': bvn});

      // 2. Initiate OTP
      final initiateCallable = FirebaseFunctions.instance.httpsCallable('initiateVaultVerification');
      final initiateResult = await initiateCallable.call();
      final identityId = initiateResult.data['identityId'] as String?;

      if (identityId == null) {
        throw Exception("Failed to initiate BVN verification. Please try again.");
      }

      if (!mounted) return;

      // 3. Prompt for OTP
      final phone = FirebaseAuth.instance.currentUser?.phoneNumber ?? 'your registered number';
      final otp = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => OtpDialog(phone: phone),
      );

      if (otp == null || otp.isEmpty) {
        if (!mounted) return;
        GkToast.show(context, message: 'Verification cancelled.', type: ToastType.warning);
        return;
      }

      // 4. Validate Identity
      setState(() => _isLoading = true);
      final validateCallable = FirebaseFunctions.instance.httpsCallable('validateIdentity');
      await validateCallable.call({
        'identityId': identityId,
        'otp': otp
      });

      if (!mounted) return;
      GkToast.show(context, message: 'Identity verified successfully!', type: ToastType.success);
      context.go(Routes.dashboard);

    } catch (e) {
      if (!mounted) return;
      String errorMsg = 'An error occurred';
      if (e is FirebaseFunctionsException) {
        errorMsg = e.message ?? errorMsg;
      } else {
        errorMsg = e.toString();
      }
      GkToast.show(context, message: errorMsg, type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Step 3 of 3',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          )),
                  Text('Identity',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.onSurfaceVariant,
                          )),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(100),
                child: const LinearProgressIndicator(
                  value: 0.85,
                  minHeight: 6,
                  backgroundColor: AppColors.surfaceContainer,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              // Header illustration
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, Color(0xFF1B4D3E)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.person_rounded,
                        color: Colors.white, size: 52),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Set up your identity',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'This helps us personalise your vault',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14,
                        color: Colors.white70,),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0),
              const SizedBox(height: 36),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surfaceBright,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 24),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Please ensure you use your exact legal name as it appears on your Government Issued ID.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.onSurface,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 150.ms),
              const SizedBox(height: 32),
              
              Form(
                key: _formKey,
                child: TextFormField(
                  controller: _bvnController,
                  keyboardType: TextInputType.number,
                  maxLength: 11,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 16,
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Bank Verification Number (BVN)',
                    labelStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.outline,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    prefixIcon: const Icon(Icons.numbers_rounded, color: AppColors.primary),
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
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'BVN is required';
                    if (v.trim().length != 11) return 'BVN must be 11 digits';
                    return null;
                  },
                ),
              ).animate().fadeIn(delay: 250.ms).slideX(begin: 0.05, end: 0),
              
              const SizedBox(height: AppSpacing.md),
                // Privacy note
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.1)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_outline_rounded,
                          color: AppColors.primary, size: 20),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'Your data is encrypted and never shared. Gatekipa uses your info only to personalise your vault.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12,
                            color: AppColors.onSurfaceVariant,
                            height: 1.5,),
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: 350.ms),
              ],
            ),
          ),
        ),
      // ── Sticky bottom action bar ──────────────────────────────────
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(
            24, 16, 24, MediaQuery.of(context).padding.bottom + 12),
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
            GkButton(
              label: 'Enter My Vault',
              icon: Icons.shield_rounded,
              isLoading: _isLoading,
              onPressed: _save,
            ),
            const SizedBox(height: AppSpacing.xs),
            TextButton(
              onPressed: () async {
                // Mark KYC as skipped so the router guard doesn't re-block.
                final uid = FirebaseAuth.instance.currentUser?.uid;
                if (uid != null) {
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .update({'kycStatus': 'skipped'});
                }
                // ignore: use_build_context_synchronously
                if (context.mounted) context.go(Routes.dashboard);
              },
              child: const Text(
                'Skip for now',
                style: TextStyle(height: 1.2, fontFamily: 'Manrope', color: AppColors.outline,
                  fontWeight: FontWeight.w600,),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
