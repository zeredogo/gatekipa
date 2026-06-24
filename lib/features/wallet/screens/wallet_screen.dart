// lib/features/wallet/screens/wallet_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gatekipa/core/constants/routes.dart';
import 'package:gatekipa/core/theme/app_colors.dart';
import 'package:gatekipa/core/utils/currency_formatter.dart';
import 'package:gatekipa/core/widgets/shimmer_loader.dart';
import 'package:gatekipa/features/wallet/providers/wallet_provider.dart';
import 'package:gatekipa/features/cards/providers/card_provider.dart'
    show TransactionModel;
import 'package:gatekipa/core/theme/app_spacing.dart';
import 'package:gatekipa/core/widgets/transaction_status_widget.dart';
import 'package:gatekipa/features/wallet/screens/transaction_detail_screen.dart';

// ── Filter enum ─────────────────────────────────────────────────────────────
enum _TxFilter { all, credits, debits, declined, pending }

class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  _TxFilter _filter = _TxFilter.all;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<TransactionModel> _applyFilters(List<TransactionModel> all) {
    var result = all;

    // Apply type filter
    switch (_filter) {
      case _TxFilter.credits:
        result = result.where((t) => t.isCredit).toList();
      case _TxFilter.debits:
        result = result.where((t) => !t.isCredit && !t.isDeclined && !t.isPending).toList();
      case _TxFilter.declined:
        result = result.where((t) => t.isDeclined).toList();
      case _TxFilter.pending:
        result = result.where((t) => t.isPending).toList();
      case _TxFilter.all:
        break;
    }

    // Apply search
    if (_query.isNotEmpty) {
      result = result.where((t) {
        return t.merchantName.toLowerCase().contains(_query) ||
            t.displayType.toLowerCase().contains(_query) ||
            (t.providerReference?.toLowerCase().contains(_query) ?? false) ||
            (t.declineReason?.toLowerCase().contains(_query) ?? false);
      }).toList();
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final walletAsync = ref.watch(walletProvider);
    // ── Switch to unified ledger: shows top-ups, fees, card charges, declines ──
    final txAsync = ref.watch(unifiedLedgerProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          ref.invalidate(walletProvider);
          ref.invalidate(unifiedLedgerProvider);
          ref.invalidate(walletLedgerProvider);
          await Future.delayed(const Duration(milliseconds: 500));
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Collapsing Header ───────────────────────────────────────
            SliverAppBar(
              backgroundColor: AppColors.primary,
              expandedHeight: 260,
              pinned: true,
              elevation: 0,
              leading: const BackButton(color: Colors.white),
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.pin,
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.primary, Color(0xFF004D2C)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, kToolbarHeight + 10, 24, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Label row
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color:
                                      Colors.white.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                    Icons.account_balance_wallet_rounded,
                                    color: Colors.white,
                                    size: 18),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Vault Balance',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color:
                                      Colors.white.withValues(alpha: 0.8),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          // Balance
                          walletAsync.when(
                            data: (w) => FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                CurrencyFormatter.format(w?.balance ?? 0),
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white,
                                  fontSize: 32,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -1.0,),
                              ),
                            )
                                .animate()
                                .fadeIn()
                                .scale(
                                    begin: const Offset(0.95, 0.95),
                                    end: const Offset(1, 1)),
                            loading: () => const ShimmerLoader(
                                width: 180, height: 44, radius: 8),
                            error: (_, __) => FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '₦ 0.00',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white,
                                    fontSize: 32,
                                    fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                          const Spacer(),
                          // Action buttons
                          Row(
                            children: [
                              Expanded(
                                child: _WalletActionBtn(
                                  icon: Icons.add_rounded,
                                  label: 'Add Funds',
                                  onTap: () => context.push(Routes.addFunds),
                                  filled: true,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _WalletActionBtn(
                                  icon: Icons.receipt_long_rounded,
                                  label: 'Statement',
                                  onTap: () =>
                                      context.push(Routes.statement),
                                  filled: false,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              title: Text(
                'My Wallet',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
              ),
            ),

            // ── Monthly Spend Summary Strip ─────────────────────────────────
            Builder(builder: (ctx) {
              final allTxs = txAsync.valueOrNull ?? [];
              final now = DateTime.now();
              final thisMonth = allTxs.where((t) =>
                  t.timestamp.year == now.year &&
                  t.timestamp.month == now.month);
              final totalIn  = thisMonth.where((t) => t.isCredit)
                  .fold(0.0, (s, t) => s + t.amount);
              final totalOut = thisMonth.where((t) => !t.isCredit && !t.isDeclined)
                  .fold(0.0, (s, t) => s + t.amount);
              return SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                          color: AppColors.outlineVariant.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('In this month',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppColors.onSurfaceVariant, fontSize: 11)),
                              const SizedBox(height: 2),
                              Text(CurrencyFormatter.format(totalIn),
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.tertiary,
                                      fontSize: 15)),
                            ],
                          ),
                        ),
                        Container(
                            width: 1, height: 32,
                            color: AppColors.outlineVariant.withValues(alpha: 0.5)),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('Out this month',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppColors.onSurfaceVariant, fontSize: 11)),
                              const SizedBox(height: 2),
                              Text(CurrencyFormatter.format(totalOut),
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.onSurface,
                                      fontSize: 15)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),

            // ── Search + Filter Bar ────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header row: label + count badge
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'All Transactions',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.onSurface),
                        ),
                        Builder(builder: (_) {
                          final raw = txAsync.valueOrNull ?? [];
                          final filtered = _applyFilters(raw);
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.primaryContainer
                                  .withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Text(
                              '${filtered.length}',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary),
                            ),
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Search field
                    TextField(
                      controller: _searchCtrl,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Search merchant, type, reference…',
                        hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.outline, fontSize: 13),
                        prefixIcon: const Icon(Icons.search_rounded,
                            size: 20, color: AppColors.outline),
                        suffixIcon: _query.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close_rounded,
                                    size: 18, color: AppColors.outline),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  FocusScope.of(context).unfocus();
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: AppColors.surfaceContainerLowest,
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                              color: AppColors.outlineVariant
                                  .withValues(alpha: 0.4)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                              color: AppColors.outlineVariant
                                  .withValues(alpha: 0.4)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                              color: AppColors.primary, width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Filter chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _FilterChip(
                            label: 'All',
                            icon: Icons.format_list_bulleted_rounded,
                            selected: _filter == _TxFilter.all,
                            onTap: () => setState(() => _filter = _TxFilter.all),
                          ),
                          const SizedBox(width: 8),
                          _FilterChip(
                            label: 'Credits',
                            icon: Icons.arrow_downward_rounded,
                            selected: _filter == _TxFilter.credits,
                            color: AppColors.tertiary,
                            onTap: () => setState(() => _filter = _TxFilter.credits),
                          ),
                          const SizedBox(width: 8),
                          _FilterChip(
                            label: 'Debits',
                            icon: Icons.arrow_upward_rounded,
                            selected: _filter == _TxFilter.debits,
                            onTap: () => setState(() => _filter = _TxFilter.debits),
                          ),
                          const SizedBox(width: 8),
                          _FilterChip(
                            label: 'Declined',
                            icon: Icons.block_rounded,
                            selected: _filter == _TxFilter.declined,
                            color: AppColors.error,
                            onTap: () => setState(() => _filter = _TxFilter.declined),
                          ),
                          const SizedBox(width: 8),
                          _FilterChip(
                            label: 'Pending',
                            icon: Icons.hourglass_top_rounded,
                            selected: _filter == _TxFilter.pending,
                            color: Colors.amber,
                            onTap: () => setState(() => _filter = _TxFilter.pending),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),

            // ── Transaction list with date grouping + filter ───────────────
            txAsync.when(
              data: (rawTxs) {
                // Apply search + filter before building the list
                final txs = _applyFilters(rawTxs);

                if (txs.isEmpty) {
                  final isFiltered = _filter != _TxFilter.all || _query.isNotEmpty;
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 48, 24, 0),
                      child: Column(
                        children: [
                          Container(
                            width: 72, height: 72,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainer,
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: Icon(
                              isFiltered
                                  ? Icons.filter_list_off_rounded
                                  : Icons.receipt_long_rounded,
                              size: 32, color: AppColors.outline),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            isFiltered
                                ? 'No matching transactions'
                                : 'No transactions yet',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontSize: 18, fontWeight: FontWeight.w700,
                                    color: AppColors.onSurface)),
                          const SizedBox(height: 6),
                          Text(
                            isFiltered
                                ? 'Try a different search or filter'
                                : 'Fund your vault to get started',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontSize: 14,
                                    color: AppColors.onSurfaceVariant)),
                          if (isFiltered) ...[
                            const SizedBox(height: 16),
                            TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  _filter = _TxFilter.all;
                                  _searchCtrl.clear();
                                });
                              },
                              icon: const Icon(Icons.close_rounded, size: 16),
                              label: const Text('Clear filters'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }

                // Build date-grouped list
                final groups = _groupByDate(txs);
                final items = <_ListItem>[];
                for (final entry in groups.entries) {
                  items.add(_ListItem.header(entry.key));
                  for (final tx in entry.value) {
                    items.add(_ListItem.tx(tx));
                  }
                }

                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) {
                      final item = items[i];
                      if (item.isHeader) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                          child: Text(item.label!,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(fontWeight: FontWeight.w700,
                                      color: AppColors.onSurfaceVariant,
                                      fontSize: 11,
                                      letterSpacing: 0.5)),
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
                        child: _TxCard(tx: item.tx!)
                            .animate(delay: (i * 30).ms)
                            .fadeIn()
                            .slideY(begin: 0.04, end: 0),
                      );
                    },
                    childCount: items.length,
                  ),
                );
              },
              loading: () => const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: ShimmerTransactionList(itemCount: 6),
                ),
              ),
              error: (err, _) => SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    children: [
                      const Icon(Icons.wifi_off_rounded,
                          size: 40, color: AppColors.outline),
                      const SizedBox(height: 12),
                      Text('Could not load transactions',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: AppColors.onSurfaceVariant)),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () {
                          ref.invalidate(unifiedLedgerProvider);
                          ref.invalidate(walletLedgerProvider);
                        },
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('Retry'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primaryContainer,
                          foregroundColor: AppColors.onPrimaryContainer,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(
              child: SizedBox(height: AppSpacing.xs),
            ),
            // Dynamic bottom clearance: clears the shell nav bar + safe area
            SliverPadding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom + 100,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Coming soon wrapper removed

class _WalletActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;
  const _WalletActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.filled,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled
          ? Colors.white
          : Colors.white.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  color:
                      filled ? AppColors.primary : Colors.white,
                  size: 18),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: filled ? AppColors.primary : Colors.white,),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── List Item sealed type (header or transaction row) ───────────────────────
class _ListItem {
  final bool isHeader;
  final String? label;
  final TransactionModel? tx;
  const _ListItem._({required this.isHeader, this.label, this.tx});
  factory _ListItem.header(String label) =>
      _ListItem._(isHeader: true, label: label);
  factory _ListItem.tx(TransactionModel tx) =>
      _ListItem._(isHeader: false, tx: tx);
}

// ── Date grouping utility ───────────────────────────────────────────────
Map<String, List<TransactionModel>> _groupByDate(
    List<TransactionModel> txs) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final result = <String, List<TransactionModel>>{};

  for (final tx in txs) {
    final d = DateTime(tx.timestamp.year, tx.timestamp.month, tx.timestamp.day);
    final String label;
    if (d == today) {
      label = 'TODAY';
    } else if (d == yesterday) {
      label = 'YESTERDAY';
    } else {
      // e.g. "MAY 8" or "APR 30"
      final months = [
        'JAN','FEB','MAR','APR','MAY','JUN',
        'JUL','AUG','SEP','OCT','NOV','DEC'
      ];
      label = '${months[d.month - 1]} ${d.day}';
    }
    result.putIfAbsent(label, () => []).add(tx);
  }
  return result;
}

// ── Transaction Row Card ──────────────────────────────────────────────────
class _TxCard extends StatelessWidget {
  final TransactionModel tx;
  const _TxCard({required this.tx});

  @override
  Widget build(BuildContext context) {
    final IconData statusIcon;
    final Color iconBg;
    final Color iconColor;

    if (tx.isCredit) {
      statusIcon = Icons.arrow_downward_rounded;
      iconBg    = AppColors.tertiary.withValues(alpha: 0.1);
      iconColor = AppColors.tertiary;
    } else if (tx.isDeclined) {
      statusIcon = Icons.block_rounded;
      iconBg    = AppColors.error.withValues(alpha: 0.1);
      iconColor = AppColors.error;
    } else if (tx.isPending) {
      statusIcon = Icons.hourglass_top_rounded;
      iconBg    = Colors.amber.withValues(alpha: 0.1);
      iconColor = Colors.amber;
    } else {
      statusIcon = Icons.arrow_upward_rounded;
      iconBg    = AppColors.surfaceContainer;
      iconColor = AppColors.onSurfaceVariant;
    }

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TransactionDetailScreen(tx: tx),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(statusIcon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            // Merchant + type label / decline reason
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tx.merchant,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: AppColors.onSurface,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tx.isDeclined && tx.declineReason != null
                        ? tx.declineReason!
                        : tx.displayType,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: tx.isDeclined
                              ? AppColors.error.withValues(alpha: 0.8)
                              : AppColors.outline,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Amount + status badge
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${tx.isCredit ? '+' : tx.isDeclined ? '' : '-'}${CurrencyFormatter.format(tx.amount)}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: tx.isCredit
                            ? AppColors.tertiary
                            : tx.isDeclined
                                ? AppColors.error
                                : AppColors.onSurface,
                      ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                TransactionStatusBadge(status: tx.txnStatus),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Filter Chip Widget ────────────────────────────────────────────────────────
class _FilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  const _FilterChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = color ?? AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? activeColor.withValues(alpha: 0.1)
              : AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: selected
                ? activeColor.withValues(alpha: 0.5)
                : AppColors.outlineVariant.withValues(alpha: 0.4),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 13,
                color: selected ? activeColor : AppColors.onSurfaceVariant),
            const SizedBox(width: 5),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? activeColor
                        : AppColors.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
