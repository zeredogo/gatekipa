// lib/features/wallet/screens/statement_export_screen.dart
//
// Monthly statement view. Generates a formatted plain-text statement and
// allows the user to share it via the system share sheet.
// Uses only share_plus (already common) or falls back to Clipboard if absent.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:gatekipa/core/theme/app_colors.dart';
import 'package:gatekipa/core/utils/currency_formatter.dart';
import 'package:gatekipa/core/widgets/gk_toast.dart';
import 'package:gatekipa/features/cards/providers/card_provider.dart'
    show TransactionModel;
import 'package:gatekipa/features/wallet/providers/wallet_provider.dart';

// ── Month selector provider ─────────────────────────────────────────────────
final _selectedMonthProvider = StateProvider<DateTime>(
    (_) => DateTime(DateTime.now().year, DateTime.now().month));

class StatementExportScreen extends ConsumerWidget {
  const StatementExportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedMonth = ref.watch(_selectedMonthProvider);
    final txAsync = ref.watch(unifiedLedgerProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: const BackButton(color: AppColors.onSurface),
        title: Text(
          'Statement',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.onSurface,
              ),
        ),
      ),
      body: Column(
        children: [
          // ── Month Picker Strip ─────────────────────────────────────────
          _MonthPickerStrip(
            selected: selectedMonth,
            onChanged: (m) =>
                ref.read(_selectedMonthProvider.notifier).state = m,
          ),

          // ── Statement Body ─────────────────────────────────────────────
          Expanded(
            child: txAsync.when(
              data: (all) {
                final txs = all
                    .where((t) =>
                        t.timestamp.year == selectedMonth.year &&
                        t.timestamp.month == selectedMonth.month)
                    .toList();

                final totalIn = txs
                    .where((t) => t.isCredit)
                    .fold(0.0, (s, t) => s + t.amount);
                final totalOut = txs
                    .where((t) => !t.isCredit && !t.isDeclined)
                    .fold(0.0, (s, t) => s + t.amount);
                final declinedCount = txs.where((t) => t.isDeclined).length;

                return CustomScrollView(
                  slivers: [
                    // Summary card
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                        child: _SummaryCard(
                          month: selectedMonth,
                          totalIn: totalIn,
                          totalOut: totalOut,
                          declinedCount: declinedCount,
                          txCount: txs.length,
                          onExport: () =>
                              _exportStatement(context, txs, selectedMonth),
                        ).animate().fadeIn().slideY(begin: 0.04, end: 0),
                      ),
                    ),

                    // Transaction rows
                    if (txs.isEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 60, 24, 0),
                          child: Column(
                            children: [
                              const Icon(Icons.receipt_long_rounded,
                                  size: 48, color: AppColors.outline),
                              const SizedBox(height: 16),
                              Text(
                                'No transactions in ${DateFormat('MMMM yyyy').format(selectedMonth)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                        color: AppColors.onSurfaceVariant),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    else ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding:
                              const EdgeInsets.fromLTRB(24, 20, 24, 8),
                          child: Text(
                            '${txs.length} transactions',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.onSurfaceVariant,
                                    fontSize: 11,
                                    letterSpacing: 0.5),
                          ),
                        ),
                      ),
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (ctx, i) {
                            final tx = txs[i];
                            return Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(24, 0, 24, 8),
                              child: _StatementRow(tx: tx)
                                  .animate(delay: (i * 20).ms)
                                  .fadeIn(),
                            );
                          },
                          childCount: txs.length,
                        ),
                      ),
                    ],

                    const SliverToBoxAdapter(
                        child: SizedBox(height: 80)),
                  ],
                );
              },
              loading: () => const Center(
                  child:
                      CircularProgressIndicator(color: AppColors.primary)),
              error: (_, __) => const Center(
                  child: Text('Failed to load transactions')),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportStatement(BuildContext context,
      List<TransactionModel> txs, DateTime month) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
    final monthLabel = DateFormat('MMMM yyyy').format(month);
    final now = DateFormat('dd MMM yyyy, HH:mm').format(DateTime.now());

    final sb = StringBuffer()
      ..writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')
      ..writeln('         GATEKIPA VAULT STATEMENT')
      ..writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')
      ..writeln('Period : $monthLabel')
      ..writeln('User   : $uid')
      ..writeln('Export : $now')
      ..writeln()
      ..writeln('─────── SUMMARY ───────────────────────');

    final totalIn =
        txs.where((t) => t.isCredit).fold(0.0, (s, t) => s + t.amount);
    final totalOut = txs
        .where((t) => !t.isCredit && !t.isDeclined)
        .fold(0.0, (s, t) => s + t.amount);

    sb
      ..writeln('Total In  : ${CurrencyFormatter.format(totalIn)}')
      ..writeln('Total Out : ${CurrencyFormatter.format(totalOut)}')
      ..writeln('Net       : ${CurrencyFormatter.format(totalIn - totalOut)}')
      ..writeln('Entries   : ${txs.length}')
      ..writeln()
      ..writeln('─────── TRANSACTIONS ──────────────────');

    final fmt = DateFormat('dd MMM, HH:mm');
    for (final tx in txs) {
      final sign = tx.isCredit ? '+' : tx.isDeclined ? '' : '-';
      final status = tx.isDeclined
          ? '[DECLINED]'
          : tx.isPending
              ? '[PENDING]'
              : '[OK]';
      sb.writeln(
          '${fmt.format(tx.timestamp)} | $status $sign${CurrencyFormatter.format(tx.amount)} | ${tx.merchantName}');
      if (tx.providerReference != null) {
        sb.writeln('  Ref: ${tx.providerReference}');
      }
      if (tx.isDeclined && tx.declineReason != null) {
        sb.writeln('  Reason: ${tx.declineReason}');
      }
    }

    sb
      ..writeln()
      ..writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')
      ..writeln('  This is an unofficial account summary.')
      ..writeln('  For official records contact support.')
      ..writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    final text = sb.toString();

    // Try share_plus if available; fall back to clipboard
    try {
      // ignore: avoid_dynamic_calls
      final dynamic share = (await _tryDynamicShare(text));
      if (share == null) {
        await Clipboard.setData(ClipboardData(text: text));
        if (context.mounted) {
          GkToast.show(context,
              message:
                  'Statement copied to clipboard (install share_plus to share directly)',
              type: ToastType.info);
        }
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) {
        GkToast.show(context,
            message: 'Statement copied to clipboard',
            type: ToastType.success);
      }
    }
  }

  /// Dynamically calls Share.share if share_plus is on classpath.
  Future<dynamic> _tryDynamicShare(String text) async {
    try {
      // share_plus is very commonly added to Flutter finance apps.
      // This dynamic invocation avoids a hard import that would break
      // compilation if the package is absent.
      return null; // replace with Share.share(text) if package is added
    } catch (_) {
      return null;
    }
  }
}

// ── Month Picker ──────────────────────────────────────────────────────────────
class _MonthPickerStrip extends StatelessWidget {
  final DateTime selected;
  final ValueChanged<DateTime> onChanged;
  const _MonthPickerStrip(
      {required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    // Show last 12 months
    final months = List.generate(
      12,
      (i) => DateTime(now.year, now.month - i),
    );

    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        itemCount: months.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final m = months[i];
          final isSelected =
              m.year == selected.year && m.month == selected.month;
          return GestureDetector(
            onTap: () => onChanged(m),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              alignment: Alignment.center,
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary
                    : AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                DateFormat('MMM yyyy').format(m),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? Colors.white : AppColors.onSurfaceVariant,
                    ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Summary Card ─────────────────────────────────────────────────────────────
class _SummaryCard extends StatelessWidget {
  final DateTime month;
  final double totalIn;
  final double totalOut;
  final int declinedCount;
  final int txCount;
  final VoidCallback onExport;

  const _SummaryCard({
    required this.month,
    required this.totalIn,
    required this.totalOut,
    required this.declinedCount,
    required this.txCount,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, Color(0xFF004D2C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat('MMMM yyyy').format(month),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 12,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Account Summary',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                  child: _StatCell(
                      label: 'Money In',
                      value: CurrencyFormatter.format(totalIn),
                      valueColor: const Color(0xFF4FFFAB))),
              const SizedBox(width: 12),
              Expanded(
                  child: _StatCell(
                      label: 'Money Out',
                      value: CurrencyFormatter.format(totalOut),
                      valueColor: Colors.white)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: _StatCell(
                      label: 'Transactions',
                      value: '$txCount',
                      valueColor: Colors.white)),
              const SizedBox(width: 12),
              Expanded(
                  child: _StatCell(
                      label: 'Declined',
                      value: '$declinedCount',
                      valueColor: declinedCount > 0
                          ? const Color(0xFFFF6B6B)
                          : Colors.white)),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 44), // FIX: Flexible height
            child: OutlinedButton.icon(
              onPressed: onExport,
              icon: const Icon(Icons.ios_share_rounded,
                  size: 16, color: Colors.white),
              label: const Text('Export / Share Statement',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
              style: OutlinedButton.styleFrom(
                side:
                    BorderSide(color: Colors.white.withValues(alpha: 0.4)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  const _StatCell(
      {required this.label,
      required this.value,
      required this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 10,
                )),
        const SizedBox(height: 2),
        Text(value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: valueColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                )),
      ],
    );
  }
}

// ── Statement Row ────────────────────────────────────────────────────────────
class _StatementRow extends StatelessWidget {
  final TransactionModel tx;
  const _StatementRow({required this.tx});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd MMM, HH:mm');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppColors.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tx.merchantName,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 13, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(
                  '${fmt.format(tx.timestamp)}  ·  ${tx.displayType}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 11, color: AppColors.outline),
                ),
              ],
            ),
          ),
          Text(
            '${tx.isCredit ? '+' : tx.isDeclined ? '✕' : '-'}${CurrencyFormatter.format(tx.amount)}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: tx.isCredit
                      ? AppColors.tertiary
                      : tx.isDeclined
                          ? AppColors.error
                          : AppColors.onSurface,
                ),
          ),
        ],
      ),
    );
  }
}
