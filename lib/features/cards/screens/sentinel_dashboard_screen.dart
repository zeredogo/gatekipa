import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:gatekipa/core/theme/app_colors.dart';
import 'package:gatekipa/core/theme/app_spacing.dart';
import 'package:gatekipa/core/widgets/gk_toast.dart';
import 'package:gatekipa/features/auth/providers/auth_provider.dart';
import 'package:gatekipa/features/cards/models/virtual_card_model.dart';
import 'package:gatekipa/features/cards/providers/card_provider.dart';
import 'package:gatekipa/features/wallet/providers/wallet_provider.dart';

class SentinelDashboardScreen extends ConsumerStatefulWidget {
  final String? cardId;

  const SentinelDashboardScreen({super.key, this.cardId});

  @override
  ConsumerState<SentinelDashboardScreen> createState() => _SentinelDashboardScreenState();
}

class _SentinelDashboardScreenState extends ConsumerState<SentinelDashboardScreen> {
  bool _togglingSpendingLock = false;
  bool _togglingGeoFence = false;
  final Set<String> _togglingRules = {};

  Future<String?> _promptPin() async {
    final pinCtrl = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Enter PIN', style: TextStyle(color: AppColors.onSurface)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Security verification required.', style: TextStyle(color: AppColors.onSurfaceVariant)),
            const SizedBox(height: 16),
            TextField(
              controller: pinCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              style: const TextStyle(color: AppColors.onSurface),
              decoration: InputDecoration(
                hintText: '4-digit PIN',
                hintStyle: const TextStyle(color: AppColors.outline),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, pinCtrl.text.trim()),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleSpendingLock(bool lock) async {
    final pin = await _promptPin();
    if (pin == null || pin.isEmpty) return;

    setState(() => _togglingSpendingLock = true);
    try {
      final fn = FirebaseFunctions.instance.httpsCallable('toggleSpendingLock');
      await fn.call({'lock': lock, 'pin': pin});
      if (!mounted) return;
      GkToast.show(context, message: lock ? 'Spending Lock Enabled' : 'Spending Lock Disabled', type: lock ? ToastType.warning : ToastType.success);
    } catch (e) {
      if (!mounted) return;
      GkToast.show(context, message: 'Failed to update Spending Lock', type: ToastType.error);
    } finally {
      if (mounted) setState(() => _togglingSpendingLock = false);
    }
  }

  Future<void> _toggleGeoFence(bool active) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _togglingGeoFence = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({'geoFence': active});
      if (!mounted) return;
      GkToast.show(context, message: active ? 'Geo-Fencing Enabled' : 'Geo-Fencing Disabled', type: active ? ToastType.success : ToastType.info);
    } catch (e) {
      if (!mounted) return;
      GkToast.show(context, message: 'Failed to update Geo-Fencing', type: ToastType.error);
    } finally {
      if (mounted) setState(() => _togglingGeoFence = false);
    }
  }

  Future<void> _toggleCardRule(String subType, bool active, List<CardRule> rules) async {
    if (widget.cardId == null) {
      GkToast.show(context, message: 'Please select a card first to configure rules.', type: ToastType.warning);
      return;
    }
    
    setState(() => _togglingRules.add(subType));
    try {
      if (active) {
        // We use type "merchant_limit" broadly for our sentinel rules as per current DB architecture
        await ref.read(cardNotifierProvider.notifier).createCardRule(
          cardId: widget.cardId!,
          type: 'merchant_limit',
          subType: subType,
          value: true,
        );
      } else {
        final rule = rules.firstWhere((r) => r.subType == subType);
        await ref.read(cardNotifierProvider.notifier).deleteCardRule(ruleId: rule.id);
      }
    } catch (e) {
      if (mounted) GkToast.show(context, message: 'Failed to update rule', type: ToastType.error);
    } finally {
      if (mounted) setState(() => _togglingRules.remove(subType));
    }
  }

  Future<void> _addStrictLimitDialog() async {
    if (widget.cardId == null) {
      GkToast.show(context, message: 'Please select a card first to configure rules.', type: ToastType.warning);
      return;
    }

    final merchantCtrl = TextEditingController();
    final amountCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('New Strict Limit', style: TextStyle(color: AppColors.onSurface)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Block if amount changes for a merchant.', style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              controller: merchantCtrl,
              style: const TextStyle(color: AppColors.onSurface),
              decoration: const InputDecoration(hintText: 'Merchant Name (e.g. NETFLIX)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: AppColors.onSurface),
              decoration: const InputDecoration(hintText: 'Strict Amount Limit (₦)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _togglingRules.add('block_if_amount_changes'));
              try {
                await ref.read(cardNotifierProvider.notifier).createCardRule(
                  cardId: widget.cardId!,
                  type: 'merchant_limit',
                  subType: 'block_if_amount_changes',
                  value: double.parse(amountCtrl.text.trim()),
                );
              } catch (e) {
                if (mounted) GkToast.show(context, message: 'Failed to create limit', type: ToastType.error);
              } finally {
                if (mounted) setState(() => _togglingRules.remove('block_if_amount_changes'));
              }
            },
            child: const Text('Save Rule'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(userProfileProvider);
    final user = userAsync.valueOrNull;

    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Determine rules if a card is selected
    List<CardRule> cardRules = [];
    if (widget.cardId != null) {
      final rulesAsync = ref.watch(cardRulesProvider(widget.cardId!));
      cardRules = rulesAsync.valueOrNull ?? [];
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D), // Ultra-dark premium look
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Sentinel Command Center', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18)),
        leading: const BackButton(color: Colors.white),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 30),
                  
                  // Global System Controls
                  const Text('GLOBAL CONTROLS', style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                  const SizedBox(height: 10),
                  _buildToggleCard(
                    title: 'Global Spending Lock',
                    subtitle: 'Halt all outbound transactions instantly.',
                    value: user.spendingLock,
                    icon: Icons.lock_outline_rounded,
                    isLoading: _togglingSpendingLock,
                    onChanged: (val) => _toggleSpendingLock(val),
                  ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.1),

                  const SizedBox(height: 16),
                  _buildToggleCard(
                    title: 'Geo-Fencing',
                    subtitle: 'Block all non-NGN international transactions.',
                    value: user.geoFence,
                    icon: Icons.public_off_rounded,
                    isLoading: _togglingGeoFence,
                    onChanged: (val) => _toggleGeoFence(val),
                  ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1),

                  // Card Specific Rules
                  if (widget.cardId != null) ...[
                    const SizedBox(height: 30),
                    const Text('CARD SPECIFIC RULES', style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                    const SizedBox(height: 10),
                    
                    _buildToggleCard(
                      title: 'Night Lockdown',
                      subtitle: 'Auto-block charges between 12 AM and 6 AM.',
                      value: cardRules.any((r) => r.subType == 'night_lockdown'),
                      icon: Icons.nights_stay_outlined,
                      isLoading: _togglingRules.contains('night_lockdown'),
                      onChanged: (val) => _toggleCardRule('night_lockdown', val, cardRules),
                    ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.1),

                    const SizedBox(height: 16),
                    _buildToggleCard(
                      title: 'Instant Breach Alerts',
                      subtitle: 'Get an immediate push notification on blocks.',
                      value: cardRules.any((r) => r.subType == 'instant_breach_alert'),
                      icon: Icons.notifications_active_outlined,
                      isLoading: _togglingRules.contains('instant_breach_alert'),
                      onChanged: (val) => _toggleCardRule('instant_breach_alert', val, cardRules),
                    ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.1),

                    const SizedBox(height: 16),
                    _buildStrictLimitsSection(cardRules).animate().fadeIn(delay: 500.ms).slideY(begin: 0.1),
                  ],
                ],
              ),
            ),
          ),
          
          // Breach History
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
              child: Text('RECENT BREACHES', style: TextStyle(color: AppColors.error, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
            ),
          ),
          _buildBreachHistory(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary.withValues(alpha: 0.2), Colors.transparent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.security_rounded, color: AppColors.primary, size: 32),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sentinel Active', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                Text('AI-powered transaction guarding is monitoring your account.', style: TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleCard({
    required String title,
    required String subtitle,
    required bool value,
    required IconData icon,
    required bool isLoading,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: value ? AppColors.primary : Colors.transparent, width: 1.5),
      ),
      child: Row(
        children: [
          Icon(icon, color: value ? AppColors.primary : Colors.white54, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
          if (isLoading)
            const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
          else
            Switch(
              value: value,
              activeColor: AppColors.primary,
              onChanged: onChanged,
            ),
        ],
      ),
    );
  }

  Widget _buildStrictLimitsSection(List<CardRule> rules) {
    final strictRules = rules.where((r) => r.subType == 'block_if_amount_changes').toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.money_off_csred_rounded, color: Colors.white54, size: 24),
                  SizedBox(width: 12),
                  Text('Strict Subscription Limits', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                ],
              ),
              IconButton(
                onPressed: _addStrictLimitDialog,
                icon: const Icon(Icons.add_circle_outline, color: AppColors.primary),
              ),
            ],
          ),
          if (strictRules.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('No strict limits configured.', style: TextStyle(color: Colors.white30, fontSize: 13)),
            )
          else
            ...strictRules.map((rule) {
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Block any charge ≠ ₦${rule.value}', style: const TextStyle(color: Colors.white)),
                subtitle: const Text('If amount changes', style: TextStyle(color: Colors.white54, fontSize: 12)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: AppColors.error),
                  onPressed: () async {
                    setState(() => _togglingRules.add('block_if_amount_changes'));
                    await ref.read(cardNotifierProvider.notifier).deleteCardRule(ruleId: rule.id);
                    if (mounted) setState(() => _togglingRules.remove('block_if_amount_changes'));
                  },
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildBreachHistory() {
    final txAsync = ref.watch(unifiedLedgerProvider);
    
    return txAsync.when(
      data: (txs) {
        // Filter declined transactions
        final breaches = txs.where((t) => t.isDeclined && (widget.cardId == null || t.cardId == widget.cardId)).toList();
        
        if (breaches.isEmpty) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Text('No recent breaches detected.', style: TextStyle(color: Colors.white30)),
            ),
          );
        }

        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (ctx, index) {
              final tx = breaches[index];
              return ListTile(
                leading: CircleAvatar(backgroundColor: AppColors.error.withValues(alpha: 0.2), child: const Icon(Icons.block, color: AppColors.error, size: 18)),
                title: Text(tx.merchantName ?? 'Unknown Merchant', style: const TextStyle(color: Colors.white)),
                subtitle: Text(tx.declineReason ?? 'Blocked by Sentinel', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                trailing: Text('₦${tx.amount.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
              ).animate().fadeIn(delay: Duration(milliseconds: 100 * index)).slideX();
            },
            childCount: breaches.length > 5 ? 5 : breaches.length,
          ),
        );
      },
      loading: () => const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator())),
      error: (_, __) => const SliverToBoxAdapter(child: Text('Failed to load history', style: TextStyle(color: Colors.white30))),
    );
  }
}
