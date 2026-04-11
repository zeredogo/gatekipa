// lib/features/cards/screens/card_creation_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/app_constants.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/gk_toast.dart';
import '../../accounts/providers/account_provider.dart';
import '../providers/card_provider.dart';

class CardCreationScreen extends ConsumerStatefulWidget {
  final Map<String, String>? prefillMerchant;
  final String? accountId;

  const CardCreationScreen({super.key, this.prefillMerchant, this.accountId});

  @override
  ConsumerState<CardCreationScreen> createState() => _CardCreationScreenState();
}

class _CardCreationScreenState extends ConsumerState<CardCreationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _cardNameCtrl = TextEditingController();
  final _fixedAmountCtrl = TextEditingController();
  final _maxChargesCtrl = TextEditingController();

  String _cardType = 'subscription';
  bool _nightLockdown = true;
  bool _instantBreachAlert = true;
  bool _isLoading = false;

  String? _selectedAccountId;

  // ── locked mode: accountId was passed from Account Detail ─────────────────
  bool get _isLocked => widget.accountId != null;

  @override
  void initState() {
    super.initState();
    _selectedAccountId = widget.accountId;

    if (widget.prefillMerchant != null) {
      _cardNameCtrl.text = widget.prefillMerchant!['name'] ?? '';
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isLocked && _selectedAccountId == null) {
        final activeAcc = ref.read(activeAccountProvider);
        if (activeAcc != null) {
          setState(() => _selectedAccountId = activeAcc.id);
        }
      }
    });
  }

  @override
  void dispose() {
    _cardNameCtrl.dispose();
    _fixedAmountCtrl.dispose();
    _maxChargesCtrl.dispose();
    super.dispose();
  }

  Future<void> _createCard() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedAccountId == null) {
      GkToast.show(context, message: 'Please select an account', type: ToastType.error);
      return;
    }

    setState(() => _isLoading = true);

    final cardName =
        _cardNameCtrl.text.trim().isNotEmpty ? _cardNameCtrl.text.trim() : 'New Virtual Card';

    final fixedAmt =
        double.tryParse(_fixedAmountCtrl.text.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
    final maxCharges = int.tryParse(_maxChargesCtrl.text.trim()) ?? 0;

    final accounts = ref.read(accountsStreamProvider).valueOrNull ?? [];
    final selectedAcc = accounts.where((a) => a.id == _selectedAccountId).firstOrNull;
    final derivedCategory = selectedAcc?.type ?? 'personal';

    final cardId = await ref.read(cardNotifierProvider.notifier).createCard(
          accountId: _selectedAccountId!,
          name: cardName,
          category: derivedCategory,
          isTrial: _cardType == 'trial',
          balanceLimit: fixedAmt > 0 ? fixedAmt : 50000,
        );

    if (cardId != null) {
      if (fixedAmt > 0) {
        await ref.read(cardNotifierProvider.notifier).createCardRule(
              cardId: cardId,
              type: 'spend',
              subType: 'max_per_txn',
              value: fixedAmt,
            );
      }
      if (maxCharges > 0) {
        await ref.read(cardNotifierProvider.notifier).createCardRule(
              cardId: cardId,
              type: 'count',
              subType: 'max_use_count',
              value: maxCharges,
            );
      }
      if (_nightLockdown) {
        await ref.read(cardNotifierProvider.notifier).createCardRule(
              cardId: cardId,
              type: 'time',
              subType: 'block_hours',
              value: '00:00-06:00',
            );
      }
      if (_instantBreachAlert) {
        await ref.read(cardNotifierProvider.notifier).createCardRule(
              cardId: cardId,
              type: 'behavior',
              subType: 'instant_breach_alert',
              value: true,
            );
            
        // Trigger a simulated notification test immediately so the user can verify the pipeline
        final user = ref.read(firebaseAuthProvider).currentUser;
        if (user != null) {
          await FirebaseFirestore.instance
              .collection(AppConstants.usersCollection)
              .doc(user.uid)
              .collection(AppConstants.notificationsCollection)
              .add({
            'title': 'Pipeline Active: Breach Alert',
            'body': 'Your instant breach alert for $cardName is now armed and listening.',
            'timestamp': FieldValue.serverTimestamp(),
            'isRead': false,
            'type': 'alert'
          });
        }
      }
    }

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (cardId != null) {
      GkToast.show(context, message: 'Card created successfully!', type: ToastType.success);
      context.pop();
    } else {
      GkToast.show(context, message: 'Failed to create card. Please try again.', type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsStreamProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(
          'Create Card',
          style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 20, color: AppColors.onSurface),
        ),
        backgroundColor: AppColors.surface,
        scrolledUnderElevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 140),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Account selector / locked banner ────────────────────────
              if (_isLocked) ...[
                // Wireframe ③ — Green locked banner
                accountsAsync.when(
                  data: (accounts) {
                    final acc = accounts.where((a) => a.id == widget.accountId).firstOrNull;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _FieldLabel('Account'),
                        const SizedBox(height: 8),
                        TextFormField(
                          initialValue: acc?.name ?? 'Loading...',
                          readOnly: true,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            filled: true,
                            fillColor: AppColors.surfaceContainerLowest,
                            suffixIcon: const Icon(Icons.lock_outline, size: 20),
                          ),
                          style: GoogleFonts.inter(fontSize: 15, color: AppColors.onSurfaceVariant),
                        ),
                      ],
                    );
                  },
                  loading: () => Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('Loading account...', style: GoogleFonts.inter(color: AppColors.primary)),
                  ),
                  error: (_, __) => const SizedBox.shrink(),
                ),
                const SizedBox(height: 24),
              ] else ...[
                // Wireframe ④ — Select Account dropdown
                const _FieldLabel('Select Account'),
                const SizedBox(height: 8),
                accountsAsync.when(
                  data: (accounts) {
                    if (accounts.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.outlineVariant),
                        ),
                        child: Text(
                          'No accounts found. Create an account first.',
                          style: GoogleFonts.inter(color: AppColors.onSurfaceVariant),
                        ),
                      );
                    }
                    final validId = accounts.any((a) => a.id == _selectedAccountId)
                        ? _selectedAccountId
                        : accounts.first.id;
                    if (validId != _selectedAccountId) {
                      WidgetsBinding.instance.addPostFrameCallback(
                          (_) => setState(() => _selectedAccountId = validId));
                    }
                    return InkWell(
                      onTap: () {
                        showModalBottomSheet(
                          context: context,
                          useRootNavigator: true,
                          backgroundColor: Colors.transparent,
                          isScrollControlled: true,
                          builder: (sheetContext) => Container(
                            margin: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(28),
                            ),
                            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.outlineVariant, borderRadius: BorderRadius.circular(2)))),
                                const SizedBox(height: 24),
                                Text('Select Account', style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w800)),
                                const SizedBox(height: 16),
                                ...accounts.map((acc) => ListTile(
                                  onTap: () {
                                    setState(() => _selectedAccountId = acc.id);
                                    Navigator.pop(sheetContext);
                                  },
                                  contentPadding: EdgeInsets.zero,
                                  leading: const CircleAvatar(
                                    backgroundColor: AppColors.primaryContainer,
                                    child: Icon(Icons.account_balance_wallet, color: AppColors.primary, size: 20),
                                  ),
                                  title: Text(acc.name, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                                  trailing: _selectedAccountId == acc.id ? const Icon(Icons.check_circle, color: AppColors.primary) : null,
                                )),
                              ],
                            ),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          filled: true,
                          fillColor: AppColors.surfaceContainerLowest,
                          prefixIcon: const Icon(Icons.account_balance_wallet_outlined, size: 20),
                          suffixIcon: const Icon(Icons.arrow_drop_down_rounded, size: 24),
                        ),
                        child: Text(
                          accounts.firstWhere((a) => a.id == validId, orElse: () => accounts.first).name,
                          style: GoogleFonts.inter(fontSize: 15),
                        ),
                      ),
                    );
                  },
                  loading: () => const SizedBox(height: 56, child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))),
                  error: (e, _) => Text('Error loading accounts', style: GoogleFonts.inter(color: AppColors.error)),
                ),
                const SizedBox(height: 24),
              ],

              // ── Card Name ───────────────────────────────────────────────
              const _FieldLabel('Card Name'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _cardNameCtrl,
                decoration: InputDecoration(
                  hintText: 'e.g. Hosting, Netflix, SaaS Tool',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  filled: true,
                  fillColor: AppColors.surfaceContainerLowest,
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Card name is required' : null,
              ),
              const SizedBox(height: 24),

              // ── Card Type — radio list ─────────────────────────────────
              const _FieldLabel('Card Type'),
              const SizedBox(height: 8),
              _CardTypeOption(
                value: 'subscription',
                selectedValue: _cardType,
                title: 'Subscription Card',
                subtitle: 'For recurring payments',
                onChanged: (v) => setState(() => _cardType = v!),
              ),
              const SizedBox(height: 8),
              _CardTypeOption(
                value: 'trial',
                selectedValue: _cardType,
                title: 'Trial Card',
                subtitle: 'One-time or limited use',
                onChanged: (v) => setState(() => _cardType = v!),
              ),
              const SizedBox(height: 8),
              _CardTypeOption(
                value: 'one_time',
                selectedValue: _cardType,
                title: 'One-Time Card',
                subtitle: 'Burner card for single use',
                onChanged: (v) => setState(() => _cardType = v!),
              ),
              const SizedBox(height: 28),

              // ── Rules ───────────────────────────────────────────────────
              const _FieldLabel('Rules'),
              const SizedBox(height: 12),

              // Fixed Amount
              _RuleRow(
                label: 'Fixed Amount',
                child: SizedBox(
                  width: 120,
                  child: TextFormField(
                    controller: _fixedAmountCtrl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.end,
                    decoration: InputDecoration(
                      prefixText: '₦ ',
                      isDense: true,
                      hintText: 'Enter amount',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ),
              const _Divider(),

              // Max Charges
              _RuleRow(
                label: 'Max Charges',
                child: SizedBox(
                  width: 80,
                  child: TextFormField(
                    controller: _maxChargesCtrl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.end,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '∞',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ),
              const _Divider(),

              // Night Lockdown
              _RuleRow(
                label: 'Night Lockdown',
                subtitle: 'Block 12:00 AM – 6:00 AM',
                child: Switch(
                  value: _nightLockdown,
                  onChanged: (v) => setState(() => _nightLockdown = v),
                ),
              ),
              const _Divider(),

              // Instant Breach Alert
              _RuleRow(
                label: 'Instant Breach Alert',
                subtitle: 'Push notification on breach',
                child: Switch(
                  value: _instantBreachAlert,
                  onChanged: (v) => setState(() => _instantBreachAlert = v),
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.of(context).padding.bottom + 16,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SizedBox(
          height: 56,
          child: FilledButton(
            onPressed: _isLoading ? null : _createCard,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
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
                      const Icon(Icons.credit_card_rounded, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        'Create Card',
                        style: GoogleFonts.manrope(
                            fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ── Card Type Radio Option ────────────────────────────────────────────────────
class _CardTypeOption extends StatelessWidget {
  final String value;
  final String selectedValue;
  final String title;
  final String subtitle;
  final ValueChanged<String?> onChanged;

  const _CardTypeOption({
    required this.value,
    required this.selectedValue,
    required this.title,
    required this.subtitle,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == selectedValue;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.06) : AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.outlineVariant.withValues(alpha: 0.6),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? AppColors.primary : AppColors.onSurfaceVariant,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: selected ? AppColors.primary : AppColors.onSurface,
                      )),
                  Text(subtitle,
                      style: GoogleFonts.inter(fontSize: 12, color: AppColors.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Rule Row ─────────────────────────────────────────────────────────────────
class _RuleRow extends StatelessWidget {
  final String label;
  final String? subtitle;
  final Widget child;

  const _RuleRow({required this.label, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.onSurface)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!,
                      style: GoogleFonts.inter(fontSize: 12, color: AppColors.onSurfaceVariant)),
                ],
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, color: Color(0x18000000));
}

// ── Field Label ───────────────────────────────────────────────────────────────
class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: GoogleFonts.inter(
          fontWeight: FontWeight.w700,
          fontSize: 13,
          color: AppColors.onSurfaceVariant,
          letterSpacing: 0.2,
        ),
      );
}
