// lib/features/auth/screens/kyc_screen.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:gatekeepeer/core/constants/routes.dart';
import 'package:gatekeepeer/core/theme/app_colors.dart';
import 'package:gatekeepeer/core/widgets/gk_button.dart';
import 'package:gatekeepeer/core/widgets/gk_toast.dart';
import 'package:gatekeepeer/core/theme/app_spacing.dart';

class KycScreen extends StatefulWidget {
  const KycScreen({super.key});
  @override
  State<KycScreen> createState() => _KycScreenState();
}

class _KycScreenState extends State<KycScreen> {
  bool _isLoading = false;

  Future<void> _save() async {
    setState(() => _isLoading = true);
    
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .update({'kycStatus': 'pending'});
      }
      if (!mounted) return;
      context.go(Routes.dashboard);
    } catch (e) {
      if (!mounted) return;
      GkToast.show(context, message: 'An error occurred', type: ToastType.error);
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
