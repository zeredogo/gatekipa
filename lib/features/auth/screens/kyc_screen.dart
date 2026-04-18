// lib/features/auth/screens/kyc_screen.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:gatekipa/core/constants/routes.dart';
import 'package:gatekipa/core/theme/app_colors.dart';
import 'package:gatekipa/core/widgets/gk_button.dart';
import 'package:gatekipa/core/widgets/gk_toast.dart';
import 'package:gatekipa/core/theme/app_spacing.dart';

class KycScreen extends StatefulWidget {
  const KycScreen({super.key});
  @override
  State<KycScreen> createState() => _KycScreenState();
}

class _KycScreenState extends State<KycScreen> {
  final _formKey = GlobalKey<FormState>();
  final _bvnCtrl = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _bvnCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('verifyBvn');
      await callable.call({'bvn': _bvnCtrl.text.trim()});

      if (!mounted) return;
      GkToast.show(context, message: 'Identity Verified Successfully!', type: ToastType.success);
      context.go(Routes.dashboard);
    } catch (e) {
      if (!mounted) return;
      GkToast.show(context, message: 'Identity Verification Failed', type: ToastType.error);
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
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.lg),
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
                Text(
                  'Bank Verification Number (BVN) *',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurfaceVariant,),
                ),
                const SizedBox(height: AppSpacing.xs),
                TextFormField(
                  controller: _bvnCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(11),
                  ],
                  decoration: InputDecoration(
                    hintText: 'e.g. 22212345678',
                    prefixIcon: const Icon(Icons.fingerprint_rounded),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: AppColors.outlineVariant.withValues(alpha: 0.3),
                        width: 1.5,
                      ),
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
                    if (v == null || v.trim().length != 11) {
                      return 'Please enter a valid 11-digit BVN';
                    }
                    return null;
                  },
                ).animate().fadeIn(delay: 150.ms),
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
