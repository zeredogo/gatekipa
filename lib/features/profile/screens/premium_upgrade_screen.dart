import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:gatekipa/core/theme/app_colors.dart';
import 'package:gatekipa/core/widgets/gk_button.dart';
import 'package:gatekipa/core/widgets/gk_toast.dart';
import 'package:gatekipa/features/auth/providers/auth_provider.dart';
import 'package:gatekipa/core/theme/app_spacing.dart';
import 'package:gatekipa/core/constants/routes.dart';

class PremiumUpgradeScreen extends ConsumerStatefulWidget {
  const PremiumUpgradeScreen({super.key});

  @override
  ConsumerState<PremiumUpgradeScreen> createState() => _PremiumUpgradeScreenState();
}

class _PremiumUpgradeScreenState extends ConsumerState<PremiumUpgradeScreen> {
  bool _isLoading = false;
  // FIX: Allow plan selection so Business Plan is also purchasable from the app.
  String _selectedPlan = 'premium'; // 'premium' | 'business'

  Future<void> _upgrade() async {
    final user = ref.read(userProfileProvider).valueOrNull;
    if (user == null) return;

    setState(() => _isLoading = true);
    try {
      // 1. Fetch the user's stored Transaction PIN
      const storage = FlutterSecureStorage();
      final secureKey = '${user.uid}_transaction_pin';
      final pin = await storage.read(key: secureKey);
      
      if (pin == null || pin.isEmpty) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        _showPinRequiredDialog();
        return;
      }

      // 2. Call the vault deduction endpoint
      final callable = FirebaseFunctions.instance.httpsCallable('purchasePlanFromVault');
      await callable.call({'plan': _selectedPlan, 'pin': pin});

      if (!mounted) return;
      GkToast.show(context, message: 'Welcome to ${_selectedPlan == 'business' ? 'Business Plan' : 'Sentinel Prime'}! 🎉', type: ToastType.success);
      context.pop();
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      String msg = e.message ?? 'Upgrade failed. Please try again.';
      final lowerMsg = msg.toLowerCase();
      
      if (lowerMsg.contains('pin') || lowerMsg.contains('transaction')) {
        msg = 'Transaction PIN error. Please check your PIN in Profile → Security.';
      } else if (lowerMsg.contains('insufficient') || lowerMsg.contains('funds')) {
        msg = 'Insufficient vault balance. Please fund your wallet and try again.';
      } else if (lowerMsg.contains('status code') || lowerMsg.contains('internal') || msg.length > 120) {
        msg = 'Something went wrong during the upgrade. Please try again or contact support.';
      }
      
      GkToast.show(context, message: msg, type: ToastType.error);
    } catch (e) {
      if (!mounted) return;
      GkToast.show(context, message: e.toString().contains('Exception:') ? e.toString().replaceAll('Exception: ', '') : 'Upgrade could not be completed. Please check your connection and try again.', type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showPinRequiredDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('PIN Required', style: TextStyle(color: Colors.white)),
        content: const Text(
          'You need a Transaction PIN to upgrade your account. Would you like to set one up now?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEAB308)),
            onPressed: () {
              Navigator.pop(ctx);
              context.push(Routes.pinManagement);
            },
            child: const Text('Set PIN', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(userProfileProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Dark slate bg for premium feel
      appBar: AppBar(
        title: Text(
          'Sentinel Prime',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,),
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

          if (user.isSentinelPrime) {
            return _buildActivePremiumView();
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.md),
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
                const SizedBox(height: AppSpacing.xxl),
                Text(
                  'Select Your Plan',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.2,),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Unlock the full power of Gatekipa. Choose the tier that fits your needs.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 15,
                    color: Colors.white70,
                    height: 1.5,),
                ),
                const SizedBox(height: AppSpacing.xl),
                // ── Plan selector cards ──────────────────────────────────────
                _buildPlanCard(
                  planKey: 'premium',
                  icon: Icons.star_rounded,
                  name: 'Sentinel Prime',
                  price: '₦ 1,999/mo',
                  features: ['3 Virtual Cards', 'Night Lockdown', 'Geo-Fence', 'Advanced Rules', 'Smart Alerts'],
                ),
                const SizedBox(height: AppSpacing.md),
                _buildPlanCard(
                  planKey: 'business',
                  icon: Icons.business_center_rounded,
                  name: 'Business Plan',
                  price: '₦ 5,000/mo',
                  features: ['5 Virtual Cards', 'All Sentinel Features', 'Team Management', 'Priority Support'],
                ),
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
          if (user == null || user.isSentinelPrime) return const SizedBox.shrink();
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
                   label: _selectedPlan == 'business'
                     ? 'Upgrade to Business — ₦ 5,000/mo'
                     : 'Upgrade to Sentinel Prime — ₦ 1,999/mo',
                   isLoading: _isLoading,
                   onPressed: _upgrade,
                 ),
                const SizedBox(height: 10),
                Text(
                  'Cancel anytime. No hidden fees.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13,
                    color: Colors.white54,),
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

  Widget _buildPlanCard({
    required String planKey,
    required IconData icon,
    required String name,
    required String price,
    required List<String> features,
  }) {
    final isSelected = _selectedPlan == planKey;
    return GestureDetector(
      onTap: () => setState(() => _selectedPlan = planKey),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFEAB308).withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFFEAB308) : Colors.white.withValues(alpha: 0.15),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFFEAB308).withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon,
                color: isSelected ? const Color(0xFFEAB308) : Colors.white54, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(name,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                      Text(price,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 13, fontWeight: FontWeight.w700,
                          color: isSelected ? const Color(0xFFEAB308) : Colors.white54)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...features.map((f) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(children: [
                      Icon(Icons.check_circle_rounded,
                        size: 14,
                        color: isSelected ? const Color(0xFFEAB308) : Colors.white38),
                      const SizedBox(width: 6),
                      Text(f, style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 12, color: Colors.white70)),
                    ]),
                  )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }



  Widget _buildActivePremiumView() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: AppSpacing.xxxl),
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
          const SizedBox(height: AppSpacing.xl),
          Text(
            'You are Sentinel Prime',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Colors.white,),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Your Gatekipa account is upgraded. You have zero limits on transactions and ultimate control.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 15,
              color: Colors.white70,
              height: 1.5,),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

