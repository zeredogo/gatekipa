// lib/features/cards/screens/card_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/gk_toast.dart';
import '../../../core/widgets/gk_virtual_card.dart';
import '../models/virtual_card_model.dart';
import '../providers/card_provider.dart';

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
        return _CardDetailContent(card: card, txAsync: txAsync, primaryRule: primaryRule);
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
  final CardRule primaryRule;

  const _CardDetailContent({required this.card, required this.txAsync, required this.primaryRule});

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
          style: GoogleFonts.manrope(
            fontWeight: FontWeight.w800,
            fontSize: 20,
            color: AppColors.primary,
          ),
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
                  Text('Copy card number', style: GoogleFonts.inter()),
                ]),
              ),
              PopupMenuItem(
                value: 'rename',
                child: Row(children: [
                  const Icon(Icons.edit_rounded, size: 18, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Text('Rename Card', style: GoogleFonts.inter(color: AppColors.primary, fontWeight: FontWeight.w600)),
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

            // Usage bar
            _UsageSection(card: card),
            const SizedBox(height: 24),

            // Rule toggles integrated into Kill switch below


            // Kill switch for this card
            _CardKillSwitch(card: card, primaryRule: primaryRule),
            const SizedBox(height: 24),

            // Transactions for this card
            const _SectionHeader('Transaction History'),
            const SizedBox(height: 12),
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
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurfaceVariant)),
              Text(
                '${(card.usagePercent * 100).toStringAsFixed(0)}%',
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: LinearProgressIndicator(
              value: card.usagePercent,
              minHeight: 10,
              backgroundColor: AppColors.surfaceContainer,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${CurrencyFormatter.format(card.spentAmount)} spent',
                style: GoogleFonts.inter(
                    fontSize: 12, color: AppColors.onSurfaceVariant),
              ),
              Text(
                '${CurrencyFormatter.format(card.balanceLimit)} limit',
                style: GoogleFonts.inter(
                    fontSize: 12, color: AppColors.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Rule Summary Card UI Removed

// _RuleRow is no longer needed.

class _CardKillSwitch extends ConsumerStatefulWidget {
  final VirtualCardModel card;
  final CardRule primaryRule;
  
  const _CardKillSwitch({required this.card, required this.primaryRule});

  @override
  ConsumerState<_CardKillSwitch> createState() => _CardKillSwitchState();
}

class _CardKillSwitchState extends ConsumerState<_CardKillSwitch> {
  bool _expanded = false;

  Future<void> _toggleRule(String subType, bool newValue) async {
    final notifier = ref.read(cardNotifierProvider.notifier);
    final rules = ref.read(cardRulesProvider(widget.card.id)).valueOrNull ?? [];

    if (newValue) {
      // Enable: create the rule on the backend
      await notifier.createCardRule(
        cardId: widget.card.id,
        type: subType == 'night_lockdown' ? 'time' : 'behavior',
        subType: subType,
        value: true,
      );
    } else {
      // Disable: delete the matching rule from Firestore
      final existing = rules.where((r) => r.subType == subType).firstOrNull;
      if (existing != null) {
        await notifier.deleteCardRule(ruleId: existing.id);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: widget.card.isBlocked
            ? AppColors.tertiaryContainer.withValues(alpha: 0.3)
            : AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: widget.card.isBlocked
              ? AppColors.tertiary.withValues(alpha: 0.3)
              : AppColors.error.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        children: [
          // Main kill switch header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(
                  widget.card.isBlocked ? Icons.lock_open_rounded : Icons.lock_rounded,
                  color: widget.card.isBlocked ? AppColors.tertiary : AppColors.error,
                  size: 24,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.card.isBlocked ? 'Card Blocked' : 'Emergency Kill Switch',
                        style: GoogleFonts.manrope(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        widget.card.isBlocked
                            ? 'Tap to unblock this card'
                            : 'Block all incoming charges',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: widget.card.isBlocked,
                  activeThumbColor: AppColors.error,
                  onChanged: (_) async {
                    final status = widget.card.isBlocked ? 'active' : 'blocked';
                    await ref.read(cardNotifierProvider.notifier).updateCardStatus(
                          cardId: widget.card.id,
                          status: status,
                        );
                  },
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
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildSubToggle(
                    'Block if amount changes',
                    'Prevents sneaky subscription increases.',
                    widget.primaryRule.blockIfAmountChanges,
                    (val) => _toggleRule('block_if_amount_changes', val),
                  ),
                  const SizedBox(height: 12),
                  _buildSubToggle(
                    'Breach Alerts',
                    'Notify me instantly if a charge is blocked.',
                    widget.primaryRule.instantBreachAlert,
                    (val) => _toggleRule('instant_breach_alert', val),
                  ),
                  const SizedBox(height: 12),
                  _buildSubToggle(
                    'Night Lockdown',
                    'Automatically block transactions between 12 AM and 6 AM.',
                    widget.primaryRule.nightLockdown,
                    (val) => _toggleRule('night_lockdown', val),
                  ),
                ],
              ),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildSubToggle(String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w700)),
              Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: AppColors.onSurfaceVariant)),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppColors.primary,
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
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tx.merchant,
                    style: GoogleFonts.inter(
                        fontSize: 13, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(DateFormatter.formatDateTime(tx.timestamp),
                    style: GoogleFonts.inter(
                        fontSize: 11, color: AppColors.outline)),
              ],
            ),
          ),
          Text(
            '-${CurrencyFormatter.format(tx.amount)}',
            style: GoogleFonts.manrope(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: tx.isBlocked ? AppColors.error : AppColors.onSurface,
            ),
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
      style: GoogleFonts.manrope(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: AppColors.onSurface,
      ),
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
          style: GoogleFonts.inter(color: AppColors.outline, fontSize: 14),
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
    setState(() => _loading = false);
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
                  style: GoogleFonts.manrope(
                      fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primary)),
              const SizedBox(height: 8),
              Text('Give your card a memorable name.',
                  style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurfaceVariant)),
              const SizedBox(height: 24),
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
              const SizedBox(height: 24),
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
                      : Text('Save Name',
                          style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 16)),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
