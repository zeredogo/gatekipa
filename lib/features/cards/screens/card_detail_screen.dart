// lib/features/cards/screens/card_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:gatekipa/core/theme/app_colors.dart';
import 'package:gatekipa/core/utils/date_formatter.dart';
import 'package:gatekipa/core/utils/currency_formatter.dart';
import 'package:gatekipa/core/widgets/gk_toast.dart';
import 'package:gatekipa/core/widgets/gk_virtual_card.dart';
import 'package:gatekipa/features/cards/models/virtual_card_model.dart';
import 'package:gatekipa/features/cards/providers/card_provider.dart';
import 'package:gatekipa/features/auth/providers/auth_provider.dart';
import 'package:gatekipa/core/theme/app_spacing.dart';
import 'package:gatekipa/core/widgets/transaction_status_widget.dart';
import 'package:gatekipa/features/wallet/providers/wallet_provider.dart';

class CardDetailScreen extends ConsumerWidget {
  final String cardId;
  const CardDetailScreen({super.key, required this.cardId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardsAsync = ref.watch(cardsProvider);
    final txAsync = ref.watch(transactionsProvider);
    final rulesAsync = ref.watch(cardRulesProvider(cardId));

    return cardsAsync.when(
      data: (cards) {
        final card = cards.where((c) => c.id == cardId).firstOrNull;
        if (card == null) {
          return const Scaffold(
            body: Center(child: Text('Card not found or deleted')),
          );
        }
        final rules = rulesAsync.valueOrNull ?? [];
        final primaryRule = rules.isNotEmpty ? rules.first : card.rule;
        return _CardDetailContent(card: card, txAsync: txAsync, rules: rules, primaryRule: primaryRule);
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Card not found')),
      ),
    );
  }
}

class _CardDetailContent extends ConsumerWidget {
  final VirtualCardModel card;
  final AsyncValue<List<TransactionModel>> txAsync;
  final List<CardRule> rules;
  final CardRule primaryRule;

  const _CardDetailContent({required this.card, required this.txAsync, required this.rules, required this.primaryRule});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardTxs = txAsync.when(
      data: (txs) => txs.where((t) => t.cardId == card.id).toList(),
      loading: () => <TransactionModel>[],
      error: (_, __) => <TransactionModel>[],
    );

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(
          card.displayName,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800,
            fontSize: 20,
            color: AppColors.primary,),
        ),
        leading: const BackButton(color: AppColors.onSurface),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: AppColors.outline),
            onSelected: (val) {
              if (val == 'rename') {
                showModalBottomSheet(
                  context: context,
                  useRootNavigator: true,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => _RenameCardSheet(card: card),
                );
              } else if (val == 'copy') {
                Clipboard.setData(
                    ClipboardData(text: '•••• •••• •••• ${card.last4}'));
                GkToast.show(context,
                    message: 'Card number copied', type: ToastType.info);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'copy',
                child: Row(children: [
                  const Icon(Icons.copy_rounded, size: 18, color: AppColors.outline),
                  const SizedBox(width: 10),
                  Text('Copy card number', style: Theme.of(context).textTheme.bodyMedium),
                ]),
              ),
              PopupMenuItem(
                value: 'rename',
                child: Row(children: [
                  const Icon(Icons.edit_rounded, size: 18, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Text('Rename Card', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600)),
                ]),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 140),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card visual
            Center(child: GkVirtualCard(card: card, showDetails: true))
                .animate()
                .fadeIn()
                .scale(
                    begin: const Offset(0.95, 0.95),
                    end: const Offset(1, 1),
                    duration: 400.ms),
            const SizedBox(height: 28),

            // Only show Usage, Kill Switch if card is provisioned
            if (card.bridgecardCardId != null && card.status != 'pending_issuance') ...[
              // Usage bar
              _UsageSection(card: card),
              const SizedBox(height: AppSpacing.lg),

              // Freeze toggle for this card
              _CardFreezeToggle(card: card, rules: rules),
              const SizedBox(height: AppSpacing.md),
            ],
            
            // Retry Provisioning for Ghost Cards
            if (card.status == 'pending_issuance' || card.bridgecardCardId == null) ...[
              _PendingProvisioningPanel(card: card),
              const SizedBox(height: AppSpacing.md),
            ],

            if (card.bridgecardCardId != null && card.status != 'pending_issuance') ...[
              // OTP fetcher
              _OtpActionPanel(card: card),
              const SizedBox(height: AppSpacing.lg),

              // Transactions for this card
              const _SectionHeader('Transaction History'),
              const SizedBox(height: AppSpacing.sm),
              if (cardTxs.isEmpty)
                _EmptyTxState()
              else
                ...cardTxs.asMap().entries.map((e) {
                  final tx = e.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _TxRow(tx: tx)
                        .animate(delay: (e.key * 60).ms)
                        .fadeIn()
                        .slideY(begin: 0.05, end: 0),
                  );
                }),
            ],
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

class _UsageSection extends StatelessWidget {
  final VirtualCardModel card;
  const _UsageSection({required this.card});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Spend Usage',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600,
                      color: AppColors.onSurfaceVariant)),
              Text(
                '${(card.usagePercent * 100).toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                  fontSize: 18,),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: LinearProgressIndicator(
              value: card.usagePercent,
              minHeight: 10,
              backgroundColor: AppColors.surfaceContainer,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${CurrencyFormatter.format(card.spentAmount)} spent',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12, color: AppColors.onSurfaceVariant),
              ),
              Text(
                '${CurrencyFormatter.format(card.balanceLimit)} limit',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12, color: AppColors.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: card.isBlocked ? null : () {
                showModalBottomSheet(
                  context: context,
                  useRootNavigator: true,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => _FundCardModal(card: card),
                );
              },
              icon: const Icon(Icons.account_balance_wallet_rounded, size: 20),
              label: const Text('Fund Card from Wallet', style: TextStyle(fontWeight: FontWeight.w700)),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryContainer,
                foregroundColor: AppColors.onPrimaryContainer,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Rule Summary Card UI Removed

// _RuleRow is no longer needed.

class _CardFreezeToggle extends ConsumerStatefulWidget {
  final VirtualCardModel card;
  final List<CardRule> rules;
  
  const _CardFreezeToggle({required this.card, required this.rules});

  @override
  ConsumerState<_CardFreezeToggle> createState() => _CardFreezeToggleState();
}

class _CardFreezeToggleState extends ConsumerState<_CardFreezeToggle> {
  bool _expanded = false;
  bool _toggling = false;
  final Set<String> _loadingRules = {};

  Future<void> _toggleCardStatus() async {
    if (_toggling) return;
    final status = widget.card.isFrozen ? 'active' : 'frozen';
    
    // BIOMETRIC CHALLENGE FOR DYNAMIC UNFREEZE
    if (status == 'active') {
      final LocalAuthentication auth = LocalAuthentication();
      try {
        final bool canCheck = await auth.canCheckBiometrics || await auth.isDeviceSupported();
        if (canCheck) {
          final bool didAuth = await auth.authenticate(
            localizedReason: 'Authenticate to unlock this card for purchases',
            options: const AuthenticationOptions(biometricOnly: false, stickyAuth: true),
          );
          if (!mounted) return;
          if (!didAuth) {
            GkToast.show(context, message: 'Authentication required to unlock card', type: ToastType.error);
            return;
          }
        }
      } catch (e) {
        debugPrint('Biometric error: $e');
      }
    }
    
    setState(() => _toggling = true);
    final success = await ref.read(cardNotifierProvider.notifier).updateCardStatus(
      cardId: widget.card.id,
      status: status,
    );
    if (mounted) {
      setState(() => _toggling = false);
      if (!success) {
        GkToast.show(context,
            message: 'Failed to update card status. Try again.',
            type: ToastType.error);
      }
    }
  }

  Future<void> _toggleRule(String subType, bool newValue) async {
    if (subType == 'block_if_amount_changes' || subType == 'night_lockdown' || subType == 'instant_breach_alert') {
      final user = ref.read(userProfileProvider).valueOrNull;
      if (user != null && !user.isSentinelPrime) {
         GkToast.show(context,
            message: '🚀 Sentinel Prime Required: Upgrade your plan to unlock advanced card protections.',
            type: ToastType.warning,
            duration: const Duration(seconds: 4));
         return;
      }
    }
    if (_loadingRules.contains(subType)) return;
    setState(() => _loadingRules.add(subType));
    final notifier = ref.read(cardNotifierProvider.notifier);
    final rules = ref.read(cardRulesProvider(widget.card.id)).valueOrNull ?? [];

    bool success;
    if (newValue) {
      success = await notifier.createCardRule(
        cardId: widget.card.id,
        type: subType == 'night_lockdown' ? 'time' : 'behavior',
        subType: subType,
        value: true,
      );
    } else {
      final existing = rules.where((r) => r.subType == subType).firstOrNull;
      if (existing != null) {
        success = await notifier.deleteCardRule(ruleId: existing.id);
      } else {
        success = true;
      }
    }
    if (mounted) {
      setState(() => _loadingRules.remove(subType));
      if (!success) {
        GkToast.show(context,
            message: 'Failed to update rule. Try again.',
            type: ToastType.error);
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userProfileProvider).valueOrNull;
    final isSentinel = user?.isSentinelPrime ?? false;

    return Container(
      decoration: BoxDecoration(
        color: widget.card.isFrozen
            ? AppColors.tertiaryContainer.withValues(alpha: 0.3)
            : AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: widget.card.isFrozen
              ? AppColors.tertiary.withValues(alpha: 0.3)
              : AppColors.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        children: [
          // Main freeze toggle header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(
                  widget.card.isFrozen ? Icons.ac_unit_rounded : Icons.credit_card_rounded,
                  color: widget.card.isFrozen ? AppColors.tertiary : AppColors.primary,
                  size: 24,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.card.isFrozen ? 'Card Frozen' : 'Freeze Card',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700,
                          fontSize: 15,),
                      ),
                      Text(
                        widget.card.isFrozen
                            ? 'Tap to unfreeze this card'
                            : 'Temporarily disable your card',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12,
                          color: AppColors.onSurfaceVariant,),
                      ),
                    ],
                  ),
                ),
                Switch(
                    value: widget.card.isFrozen,
                    activeThumbColor: AppColors.tertiary,
                    activeTrackColor: AppColors.tertiaryContainer,
                    thumbIcon: WidgetStateProperty.resolveWith<Icon?>((Set<WidgetState> states) {
                      if (states.contains(WidgetState.selected)) {
                        return const Icon(Icons.ac_unit_rounded, color: AppColors.tertiary);
                      }
                      return const Icon(Icons.close, color: AppColors.surface);
                    }),
                    onChanged: _toggling ? null : (_) => _toggleCardStatus(),
                  ),
                  if (_toggling)
                    const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.tertiary,
                      ),
                    ),
                IconButton(
                  icon: Icon(
                    _expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.outline,
                  ),
                  onPressed: () => setState(() => _expanded = !_expanded),
                ),
              ],
            ),
          ),
          
          if (_expanded) ...[
            const Divider(height: 1),
            // Guard rules below (dropdown style expanded)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Guard Rules',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: AppColors.onSurface,),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _buildSubToggle(
                    'Block if amount changes',
                    'Prevents sneaky subscription increases.',
                    widget.rules.any((r) => r.subType == 'block_if_amount_changes'),
                    'block_if_amount_changes',
                    (val) => _toggleRule('block_if_amount_changes', val),
                    isSentinel: isSentinel,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _buildSubToggle(
                    'Breach Alerts',
                    'Notify me instantly if a charge is blocked.',
                    widget.rules.any((r) => r.subType == 'instant_breach_alert'),
                    'instant_breach_alert',
                    (val) => _toggleRule('instant_breach_alert', val),
                    isSentinel: isSentinel,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _buildSubToggle(
                    'Night Lockdown',
                    'Automatically block transactions between 12 AM and 6 AM.',
                    widget.rules.any((r) => r.subType == 'night_lockdown'),
                    'night_lockdown',
                    (val) => _toggleRule('night_lockdown', val),
                    isSentinel: isSentinel,
                  ),
                ],
              ),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildSubToggle(
      String title, String subtitle, bool value, String subTypeKey, ValueChanged<bool> onChanged, {bool isSentinel = true}) {
    final isLoading = _loadingRules.contains(subTypeKey);
    final displayValue = value && isSentinel;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.w700)),
              Text(subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12, color: AppColors.onSurfaceVariant)),
            ],
          ),
        ),
        if (isLoading)
          const SizedBox(
            height: 24,
            width: 24,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.primary),
          )
        else
          Switch(
            value: displayValue,
            thumbIcon: WidgetStateProperty.resolveWith<Icon?>((Set<WidgetState> states) {
              if (states.contains(WidgetState.selected)) {
                return const Icon(Icons.check, color: AppColors.primary);
              }
              return const Icon(Icons.close, color: AppColors.surface);
            }),
            onChanged: onChanged,
          ),
      ],
    );
  }

}


class _TxRow extends StatelessWidget {
  final TransactionModel tx;
  const _TxRow({required this.tx});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: tx.isBlocked
                  ? AppColors.errorContainer.withValues(alpha: 0.3)
                  : AppColors.tertiaryFixed.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              tx.isBlocked ? Icons.block_rounded : Icons.check_rounded,
              size: 16,
              color: tx.isBlocked ? AppColors.error : AppColors.tertiary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tx.merchant,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(DateFormatter.formatDateTime(tx.timestamp),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 11, color: AppColors.outline)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '-\${CurrencyFormatter.format(tx.amount)}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: tx.isBlocked ? AppColors.error : AppColors.onSurface,),
              ),
              const SizedBox(height: 4),
              TransactionStatusBadge(status: tx.txnStatus),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 18,
        fontWeight: FontWeight.w800,
        color: AppColors.onSurface,),
    );
  }
}

class _EmptyTxState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Text(
          'No transactions for this card yet',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.outline, fontSize: 14),
        ),
      ),
    );
  }
}

// ── Rename Card Sheet ────────────────────────────────────────────────────────────
class _RenameCardSheet extends ConsumerStatefulWidget {
  final VirtualCardModel card;
  const _RenameCardSheet({required this.card});

  @override
  ConsumerState<_RenameCardSheet> createState() => _RenameCardSheetState();
}

class _RenameCardSheetState extends ConsumerState<_RenameCardSheet> {
  late final TextEditingController _ctrl;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.card.name);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final newName = _ctrl.text.trim();
    if (newName.isEmpty || newName == widget.card.name) {
      Navigator.pop(context);
      return;
    }
    setState(() => _loading = true);
    final success = await ref.read(cardNotifierProvider.notifier).renameCard(
          cardId: widget.card.id,
          newName: newName,
        );
    if (mounted) setState(() => _loading = false);
    if (mounted) {
      GkToast.show(context,
          message: success ? 'Card renamed successfully' : 'Failed to rename card',
          type: success ? ToastType.success : ToastType.error);
      if (success) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AppColors.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text('Rename Card',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primary)),
              const SizedBox(height: AppSpacing.xs),
              Text('Give your card a memorable name.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13, color: AppColors.onSurfaceVariant)),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Card Name',
                  hintText: 'e.g. Netflix, Office Supplies',
                  prefixIcon: const Icon(Icons.credit_card_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _loading ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _loading
                      ? const SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Save Name',
                          style: TextStyle(height: 1.2, fontFamily: 'Manrope', fontWeight: FontWeight.w700, fontSize: 16)),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Pending Provisioning Panel ────────────────────────────────────────────────
class _PendingProvisioningPanel extends ConsumerStatefulWidget {
  final VirtualCardModel card;
  const _PendingProvisioningPanel({required this.card});

  @override
  ConsumerState<_PendingProvisioningPanel> createState() => _PendingProvisioningPanelState();
}

class _PendingProvisioningPanelState extends ConsumerState<_PendingProvisioningPanel> {
  bool _isLoading = false;

  Future<String?> _collectCardPin() async {
    String pin = '';
    return await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            'Set Card PIN',
            style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Enter a 4-digit PIN to finalize activation of your card.',
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              TextFormField(
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: true,
                onChanged: (val) => pin = val,
                decoration: InputDecoration(
                  hintText: '****',
                  counterText: '',
                  filled: true,
                  fillColor: AppColors.surfaceContainerLowest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                style: const TextStyle(letterSpacing: 8, fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel', style: TextStyle(color: AppColors.outline)),
            ),
            TextButton(
              onPressed: () {
                if (pin.length == 4) {
                  Navigator.pop(ctx, pin);
                } else {
                  GkToast.show(ctx, message: 'PIN must be exactly 4 digits', type: ToastType.error);
                }
              },
              child: const Text('Activate', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _activateCard() async {
    final pin = await _collectCardPin();
    if (pin == null) return;

    setState(() => _isLoading = true);

    final success = await ref.read(cardNotifierProvider.notifier).createBridgecard(
      cardId: widget.card.id,
      pin: pin,
      cardCurrency: widget.card.currency,
    );

    if (mounted) {
      setState(() => _isLoading = false);
      if (success) {
        GkToast.show(context, message: 'Card activated successfully! 🎉', type: ToastType.success);
      } else {
        GkToast.show(context, message: 'Activation failed. Please try again or contact support.', type: ToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.errorContainer.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: AppColors.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Activation Incomplete',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.error,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Your card was registered but not fully activated. Tap below to set your PIN and provision your card.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _isLoading ? null : _activateCard,
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.rocket_launch_rounded, size: 20),
            label: Text(_isLoading ? 'Activating...' : 'Complete Activation',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Transaction OTP Action Panel ──────────────────────────────────────────────
class _OtpActionPanel extends StatelessWidget {
  final VirtualCardModel card;
  const _OtpActionPanel({required this.card});

  @override
  Widget build(BuildContext context) {
    if (card.bridgecardCardId == null) return const SizedBox.shrink();
    
    return FilledButton.icon(
      onPressed: () {
        showModalBottomSheet(
          context: context,
          useRootNavigator: true,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _TransactionOtpModal(card: card),
        );
      },
      icon: const Icon(Icons.password_rounded, size: 20),
      label: const Text('Get 3D Secure OTP', style: TextStyle(fontWeight: FontWeight.w700)),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primaryContainer,
        foregroundColor: AppColors.onPrimaryContainer,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

// ── Transaction OTP Input Modal ───────────────────────────────────────────────
class _TransactionOtpModal extends ConsumerStatefulWidget {
  final VirtualCardModel card;
  const _TransactionOtpModal({required this.card});

  @override
  ConsumerState<_TransactionOtpModal> createState() => _TransactionOtpModalState();
}

class _TransactionOtpModalState extends ConsumerState<_TransactionOtpModal> {
  final _amountCtrl = TextEditingController();
  bool _loading = false;
  String? _otp;
  String? _message;

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchOtp() async {
    final amountText = _amountCtrl.text.replaceAll(',', '').trim();
    if (amountText.isEmpty) {
      GkToast.show(context, message: 'Please enter the transaction amount', type: ToastType.error);
      return;
    }
    
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      GkToast.show(context, message: 'Invalid amount', type: ToastType.error);
      return;
    }

    setState(() {
      _loading = true;
      _otp = null;
      _message = null;
    });
    
    try {
      final fetchedOtp = await ref.read(cardNotifierProvider.notifier).getCardOtp(
        cardId: widget.card.id, 
        amountNgn: amount,
      );
      if (mounted) {
        setState(() {
          _loading = false;
          _otp = fetchedOtp;
          if (_otp == null) {
            _message = 'No pending OTP found for this exact amount.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _message = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AppColors.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text('Transaction Verification',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primary)),
              const SizedBox(height: AppSpacing.xs),
              Text('Westgate Stratagem requires the exact spending amount in Naira to authorize the OTP.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13, color: AppColors.onSurfaceVariant)),
              
              if (_otp != null) ...[
                const SizedBox(height: AppSpacing.xl),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                  decoration: BoxDecoration(
                    color: AppColors.tertiaryFixed.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.tertiary.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    children: [
                      Text('Your Secure OTP', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.tertiary, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text(
                        _otp!,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 32, letterSpacing: 10, fontWeight: FontWeight.w800, color: AppColors.tertiary),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                ),
              ] else ...[
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  controller: _amountCtrl,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Expected Checkout Amount (₦)',
                    hintText: 'e.g. 5000',
                    prefixIcon: const Icon(Icons.payments_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onSubmitted: (_) => _fetchOtp(),
                ),
                if (_message != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(_message!, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.error, fontSize: 13)),
                ],
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: _loading ? null : _fetchOtp,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _loading
                        ? const SizedBox(
                            height: 20, width: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Get OTP',
                            style: TextStyle(height: 1.2, fontFamily: 'Manrope', fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xs),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Fund Card Modal ─────────────────────────────────────────────────────────────
class _FundCardModal extends ConsumerStatefulWidget {
  final VirtualCardModel card;
  const _FundCardModal({required this.card});

  @override
  ConsumerState<_FundCardModal> createState() => _FundCardModalState();
}

class _FundCardModalState extends ConsumerState<_FundCardModal> {
  final _amountCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amountText = _amountCtrl.text.replaceAll(',', '').trim();
    if (amountText.isEmpty) {
      GkToast.show(context, message: 'Please enter an amount', type: ToastType.error);
      return;
    }
    
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      GkToast.show(context, message: 'Invalid amount', type: ToastType.error);
      return;
    }

    setState(() => _loading = true);
    
    // Dumb client: Send intent to backend, wait for response. No local limits checked.
    final idempotencyKey = 'fund_card_${widget.card.id}_${DateTime.now().millisecondsSinceEpoch}';
    final success = await ref.read(walletNotifierProvider.notifier).fundCard(
      cardId: widget.card.id,
      accountId: widget.card.accountId,
      amount: amount,
      idempotencyKey: idempotencyKey,
    );

    if (mounted) {
      setState(() => _loading = false);
      if (success) {
        GkToast.show(context, message: 'Card funded successfully', type: ToastType.success);
        Navigator.pop(context);
      } else {
        GkToast.show(context, message: 'Failed to fund card', type: ToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AppColors.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text('Fund Card',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primary)),
              const SizedBox(height: AppSpacing.xs),
              Text('Enter the amount to transfer from your wallet to this card.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13, color: AppColors.onSurfaceVariant)),
              const SizedBox(height: AppSpacing.xl),
              TextField(
                controller: _amountCtrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Amount (₦)',
                  hintText: 'e.g. 5000',
                  prefixIcon: const Icon(Icons.payments_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _loading ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _loading
                      ? const SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Confirm Funding',
                          style: TextStyle(height: 1.2, fontFamily: 'Manrope', fontWeight: FontWeight.w700, fontSize: 16)),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
          ),
        ),
    );
  }
}

