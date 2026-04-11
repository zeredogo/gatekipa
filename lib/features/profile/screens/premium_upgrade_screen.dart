import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/gk_button.dart';
import '../../../core/widgets/gk_toast.dart';
import '../../auth/providers/auth_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PremiumUpgradeScreen extends ConsumerStatefulWidget {
  const PremiumUpgradeScreen({super.key});

  @override
  ConsumerState<PremiumUpgradeScreen> createState() => _PremiumUpgradeScreenState();
}

class _PremiumUpgradeScreenState extends ConsumerState<PremiumUpgradeScreen> {
  bool _isLoading = false;

  Future<void> _upgrade() async {
    setState(() => _isLoading = true);
    
    try {
      // Simulate payment gateway delay
      await Future.delayed(const Duration(seconds: 2));

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await ref.read(authNotifierProvider.notifier).updateProfile(
          uid: uid,
          data: {'isPremium': true},
        );
      } else {
        throw Exception("You must be logged in to upgrade.");
      }

      if (!mounted) return;
      GkToast.show(context, message: 'Welcome to Sentinel Prime!', type: ToastType.success);
      context.pop();
    } catch (e) {
      if (!mounted) return;
      GkToast.show(context, message: 'Failed to upgrade. Please try again.', type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(userProfileProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Dark slate bg for premium feel
      appBar: AppBar(
        title: Text(
          'Sentinel Prime',
          style: GoogleFonts.manrope(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          color: Colors.white,
          onPressed: () => context.pop(),
        ),
      ),
      body: userAsync.when(
        data: (user) {
          if (user == null) return const SizedBox.shrink();

          if (user.isPremium) {
            return _buildActivePremiumView();
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFEAB308), Color(0xFFD97706)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFEAB308).withValues(alpha: 0.3),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.star_rounded,
                      size: 64,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 48),
                Text(
                  'Upgrade to\nSentinel Prime',
                  style: GoogleFonts.manrope(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Unlock the full power of Gatekipa. Highest tier features, elite limits, and zero boundaries.',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    color: Colors.white70,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 48),
                _buildFeatureRow(Icons.card_membership_rounded, 'Unlimited Virtual Cards', 'Create infinite customizable cards.'),
                const SizedBox(height: 24),
                _buildFeatureRow(Icons.flight_takeoff_rounded, 'Worldwide Acceptance', 'No cross-border transaction fees.'),
                const SizedBox(height: 24),
                _buildFeatureRow(Icons.security_rounded, 'Advanced Geo-Fencing', 'Lock cards to specific countries / regions.'),
              ],
            ),
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (e, _) => const Center(child: Text('Failed to load data. Please pull to refresh.')),
      ),
      bottomNavigationBar: userAsync.when(
        data: (user) {
          if (user == null || user.isPremium) return const SizedBox.shrink();
          return Container(
            padding: EdgeInsets.fromLTRB(
                24, 16, 24, MediaQuery.of(context).padding.bottom + 16),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 20,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GkButton(
                  label: 'Upgrade for ₦2,000/mo',
                  isLoading: _isLoading,
                  onPressed: _upgrade,
                ),
                const SizedBox(height: 10),
                Text(
                  'Cancel anytime. No hidden fees.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.white54,
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const SizedBox.shrink(),
        error: (_, __) => const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildFeatureRow(IconData icon, String title, String subtitle) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: const Color(0xFFEAB308), size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActivePremiumView() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 64),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.star_rounded,
              size: 64,
              color: Color(0xFFEAB308),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'You are Sentinel Prime',
            style: GoogleFonts.manrope(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Your gatekipa account is upgraded. You have zero limits on transactions and ultimate control.',
            style: GoogleFonts.inter(
              fontSize: 15,
              color: Colors.white70,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
