// lib/features/wallet/screens/transaction_detail_screen.dart
//
// Full transaction receipt view. Navigated to by tapping any entry in the
// unified ledger feed. Surfaces all metadata a user needs to understand a
// transaction and, if necessary, dispute it.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gatekipa/core/theme/app_colors.dart';
import 'package:gatekipa/core/utils/currency_formatter.dart';
import 'package:gatekipa/core/utils/date_formatter.dart';
import 'package:gatekipa/core/widgets/gk_toast.dart';
import 'package:gatekipa/core/widgets/transaction_status_widget.dart';
import 'package:gatekipa/features/cards/providers/card_provider.dart'
    show TransactionModel;

class TransactionDetailScreen extends StatelessWidget {
  final TransactionModel tx;
  const TransactionDetailScreen({super.key, required this.tx});

  @override
  Widget build(BuildContext context) {
    final isCredit = tx.isCredit;
    final isPending = tx.isPending;

    final Color amountColor = tx.isDeclined
        ? AppColors.error
        : isCredit
            ? AppColors.tertiary
            : AppColors.onSurface;

    final IconData headerIcon = tx.isDeclined
        ? Icons.block_rounded
        : isPending
            ? Icons.hourglass_top_rounded
            : isCredit
                ? Icons.arrow_downward_rounded
                : Icons.arrow_upward_rounded;

    final Color headerBg = tx.isDeclined
        ? AppColors.error.withValues(alpha: 0.1)
        : isPending
            ? Colors.amber.withValues(alpha: 0.1)
            : isCredit
                ? AppColors.tertiary.withValues(alpha: 0.1)
                : AppColors.primaryContainer.withValues(alpha: 0.2);

    final Color headerIconColor = tx.isDeclined
        ? AppColors.error
        : isPending
            ? Colors.amber
            : isCredit
                ? AppColors.tertiary
                : AppColors.primary;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: const BackButton(color: AppColors.onSurface),
        title: Text(
          'Transaction Details',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.onSurface,
              ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 32),

            // ── Amount Hero ──────────────────────────────────────────────
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: headerBg,
                shape: BoxShape.circle,
              ),
              child: Icon(headerIcon, color: headerIconColor, size: 36),
            )
                .animate()
                .scale(begin: const Offset(0.7, 0.7), end: const Offset(1, 1),
                    duration: 350.ms, curve: Curves.easeOutBack),

            const SizedBox(height: 20),

            Text(
              '${isCredit ? '+' : tx.isDeclined ? '' : '-'}${CurrencyFormatter.format(tx.amount)}',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: amountColor,
                    letterSpacing: -1.5,
                  ),
            ).animate().fadeIn(delay: 100.ms),

            const SizedBox(height: 6),

            Text(
              tx.displayType,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.onSurfaceVariant,
                    fontSize: 14,
                  ),
            ),

            const SizedBox(height: 12),
            TransactionStatusBadge(status: tx.txnStatus),

            // ── Reserved Alert Banner ────────────────────────────────────
            if (tx.isPending && tx.status == 'reserved') ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.hourglass_top_rounded,
                        color: Colors.amber, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This is an authorization hold. Funds are reserved and will be '
                        'deducted if the merchant confirms the charge, or released if declined.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.amber.shade700,
                              fontSize: 12,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── Decline Reason Banner ────────────────────────────────────
            if (tx.isDeclined && tx.declineReason != null) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        color: AppColors.error, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        tx.declineReason!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.error,
                              fontSize: 12,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 32),

            // ── Detail Rows ──────────────────────────────────────────────
            _DetailCard(
              children: [
                _DetailRow(
                  label: 'Merchant / Description',
                  value: tx.merchantName,
                  bold: true,
                ),
                _DetailRow(
                  label: 'Date & Time',
                  value: DateFormatter.formatDateTime(tx.timestamp),
                ),
                _DetailRow(
                  label: 'Status',
                  value: _statusLabel(tx.status),
                ),
                _DetailRow(
                  label: 'Transaction Type',
                  value: tx.displayType,
                ),
                if (tx.providerReference != null)
                  _DetailRow(
                    label: 'Reference',
                    value: tx.providerReference!,
                    monospace: true,
                    copyable: true,
                    context: context,
                  ),
                _DetailRow(
                  label: 'Internal ID',
                  value: tx.id,
                  monospace: true,
                  copyable: true,
                  context: context,
                ),
              ],
            ).animate().fadeIn(delay: 150.ms).slideY(begin: 0.04, end: 0),

            const SizedBox(height: 24),

            // ── Report / Dispute Button ──────────────────────────────────
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 52), // FIX: Flexible height
              child: OutlinedButton.icon(
                onPressed: () => _showDisputeSheet(context),
                icon: const Icon(Icons.flag_outlined, size: 18),
                label: const Text(
                  'Report / Dispute This Transaction',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: BorderSide(
                      color: AppColors.error.withValues(alpha: 0.4)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ).animate().fadeIn(delay: 200.ms),
          ],
        ),
      ),
    );
  }

  String _statusLabel(String raw) {
    switch (raw.toLowerCase()) {
      case 'approved':
      case 'success':
      case 'settled':   return 'Completed';
      case 'declined':
      case 'failed':    return 'Declined';
      case 'reserved':  return 'Authorization Hold';
      case 'pending':   return 'Pending';
      case 'processing':return 'Processing';
      default:          return raw;
    }
  }

  void _showDisputeSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DisputeSheet(tx: tx),
    );
  }
}

// ── Detail Card Container ─────────────────────────────────────────────────────

class _DetailCard extends StatelessWidget {
  final List<Widget> children;
  const _DetailCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: AppColors.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: children
            .asMap()
            .entries
            .map((e) => Column(
                  children: [
                    e.value,
                    if (e.key < children.length - 1)
                      Divider(
                          height: 1,
                          color: AppColors.outlineVariant
                              .withValues(alpha: 0.3)),
                  ],
                ))
            .toList(),
      ),
    );
  }
}

// ── Single Detail Row ─────────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final bool monospace;
  final bool copyable;
  final BuildContext? context;

  const _DetailRow({
    required this.label,
    required this.value,
    this.bold = false,
    this.monospace = false,
    this.copyable = false,
    this.context,
  });

  @override
  Widget build(BuildContext outerCtx) {
    final ctx = context ?? outerCtx;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                    fontSize: 12,
                  ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: GestureDetector(
              onLongPress: copyable
                  ? () {
                      Clipboard.setData(ClipboardData(text: value));
                      GkToast.show(ctx,
                          message: 'Copied to clipboard',
                          type: ToastType.info);
                    }
                  : null,
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                      fontWeight:
                          bold ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 13,
                      color: AppColors.onSurface,
                      fontFamily: monospace ? 'monospace' : null,
                    ),
              ),
            ),
          ),
          if (copyable) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: value));
                GkToast.show(ctx,
                    message: 'Copied', type: ToastType.info);
              },
              child: const Icon(Icons.copy_rounded,
                  size: 14, color: AppColors.outline),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Dispute Bottom Sheet ──────────────────────────────────────────────────────

class _DisputeSheet extends ConsumerStatefulWidget {
  final TransactionModel tx;
  const _DisputeSheet({required this.tx});

  @override
  ConsumerState<_DisputeSheet> createState() => _DisputeSheetState();
}

class _DisputeSheetState extends ConsumerState<_DisputeSheet> {
  final _ctrl = TextEditingController();
  String _reason = 'Unauthorized charge';
  bool _submitting = false;

  static const _reasons = [
    'Unauthorized charge',
    'Duplicate transaction',
    'Incorrect amount',
    'Service not received',
    'Other',
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);

    try {
      // Write dispute to Firestore — admin portal monitors disputes collection
      await FirebaseFirestore.instance
          .collection('disputes')
          .add({
        'transaction_id':    widget.tx.id,
        'card_id':           widget.tx.cardId,
        'user_id':           widget.tx.userId,
        'amount':            widget.tx.amount,
        'merchant':          widget.tx.merchantName,
        'reason':            _reason,
        'description':       _ctrl.text.trim(),
        'status':            'open',
        'provider_reference':widget.tx.providerReference,
        'created_at':        FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop(context);
        GkToast.show(context,
            message: 'Dispute submitted. Our team will review within 48h.',
            type: ToastType.success);
      }
    } catch (e) {
      if (mounted) {
        GkToast.show(context,
            message: 'Failed to submit dispute. Please try again.',
            type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('Report Transaction',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.error)),
            const SizedBox(height: 4),
            Text(
              '${widget.tx.merchantName} · ${CurrencyFormatter.format(widget.tx.amount)}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 13, color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: 20),

            // Reason selector
            Text('Reason',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _reasons.map((r) {
                final sel = r == _reason;
                return GestureDetector(
                  onTap: () => setState(() => _reason = r),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel
                          ? AppColors.error.withValues(alpha: 0.1)
                          : AppColors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(
                        color: sel
                            ? AppColors.error.withValues(alpha: 0.4)
                            : AppColors.outlineVariant
                                .withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(r,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: sel
                                  ? AppColors.error
                                  : AppColors.onSurfaceVariant,
                            )),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 16),
            TextField(
              controller: _ctrl,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Additional details (optional)…',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14)),
                filled: true,
                fillColor: AppColors.surfaceContainerLowest,
              ),
            ),

            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 52), // FIX: Flexible height
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.error,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('Submit Dispute',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

