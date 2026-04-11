// lib/features/wallet/screens/wallet_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/shimmer_loader.dart';
import '../providers/wallet_provider.dart';
import '../../cards/providers/card_provider.dart'
    show transactionsProvider, TransactionModel;

class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walletAsync = ref.watch(walletProvider);
    final txAsync = ref.watch(transactionsProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          ref.invalidate(walletProvider);
          ref.invalidate(transactionsProvider);
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
                                style: GoogleFonts.inter(
                                  color:
                                      Colors.white.withValues(alpha: 0.8),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Balance
                          walletAsync.when(
                            data: (w) => Text(
                              CurrencyFormatter.format(w?.balance ?? 0),
                              style: GoogleFonts.manrope(
                                color: Colors.white,
                                fontSize: 40,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1.5,
                              ),
                            )
                                .animate()
                                .fadeIn()
                                .scale(
                                    begin: const Offset(0.95, 0.95),
                                    end: const Offset(1, 1)),
                            loading: () => const ShimmerLoader(
                                width: 180, height: 44, radius: 8),
                            error: (_, __) => Text(
                              '₦ 0.00',
                              style: GoogleFonts.manrope(
                                  color: Colors.white,
                                  fontSize: 40,
                                  fontWeight: FontWeight.w800),
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
                                  onTap: () =>
                                      context.push(Routes.addFunds),
                                  filled: true,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _WalletActionBtn(
                                  icon: Icons.arrow_outward_rounded,
                                  label: 'Withdraw',
                                  onTap: () => _showWithdrawComingSoon(context),
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
                style: GoogleFonts.manrope(
                    color: Colors.white, fontWeight: FontWeight.w800),
              ),
            ),

            // ── Section label ───────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'All Transactions',
                      style: GoogleFonts.manrope(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.onSurface,
                      ),
                    ),
                    walletAsync.when(
                      data: (w) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primaryContainer
                              .withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(
                          txAsync.valueOrNull?.length.toString() ?? '0',
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      loading: () => const SizedBox(),
                      error: (_, __) => const SizedBox(),
                    ),
                  ],
                ),
              ),
            ),

            // ── Transaction list ────────────────────────────────────────
            txAsync.when(
              data: (txs) {
                if (txs.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 48, 24, 0),
                      child: Column(
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainer,
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: const Icon(
                                Icons.receipt_long_rounded,
                                size: 32,
                                color: AppColors.outline),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No transactions yet',
                            style: GoogleFonts.manrope(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppColors.onSurface),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Fund your vault to get started',
                            style: GoogleFonts.inter(
                                fontSize: 14,
                                color: AppColors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
                      child: _TxCard(tx: txs[i])
                          .animate(delay: (i * 40).ms)
                          .fadeIn()
                          .slideY(begin: 0.04, end: 0),
                    ),
                    childCount: txs.length,
                  ),
                );
              },
              loading: () => const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: ShimmerTransactionList(itemCount: 6),
                ),
              ),
              error: (_, __) => const SliverToBoxAdapter(
                child: Center(child: Text('Failed to load transactions')),
              ),
            ),

            const SliverToBoxAdapter(
              child: SizedBox(height: 8),
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

void _showWithdrawComingSoon(BuildContext context) {
  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.arrow_outward_rounded,
                color: AppColors.primary, size: 32),
          ),
          const SizedBox(height: 20),
          Text(
            'Withdrawals Coming Soon',
            style: GoogleFonts.manrope(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'We\'re building a secure withdrawal flow. Funds remain safe in your vault and can be used directly via your virtual cards.',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppColors.onSurfaceVariant,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: () => Navigator.pop(sheetCtx),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: Text('Got it',
                  style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

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
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: filled ? AppColors.primary : Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TxCard extends StatelessWidget {
  final TransactionModel tx;
  const _TxCard({required this.tx});

  @override
  Widget build(BuildContext context) {
    final (iconBg, iconColor, statusIcon) = tx.isCredit
        ? (
            AppColors.tertiary.withValues(alpha: 0.1),
            AppColors.tertiary,
            Icons.arrow_downward_rounded
          )
        : tx.isBlocked
            ? (
                AppColors.error.withValues(alpha: 0.1),
                AppColors.error,
                Icons.block_rounded
              )
            : (
                AppColors.surfaceContainer,
                AppColors.onSurfaceVariant,
                Icons.arrow_upward_rounded
              );

    return Container(
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
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(statusIcon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          // Merchant + Date
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.merchant,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: AppColors.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  DateFormatter.formatDateTime(tx.timestamp),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.outline,
                  ),
                ),
              ],
            ),
          ),
          // Amount + status badge
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${tx.isCredit ? '+' : '-'}${CurrencyFormatter.format(tx.amount)}',
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: tx.isCredit
                      ? AppColors.tertiary
                      : tx.isBlocked
                          ? AppColors.error
                          : AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: tx.isApproved
                      ? AppColors.tertiary.withValues(alpha: 0.12)
                      : tx.isBlocked
                          ? AppColors.error.withValues(alpha: 0.1)
                          : AppColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  tx.status.toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: tx.isApproved
                        ? AppColors.tertiary
                        : tx.isBlocked
                            ? AppColors.error
                            : AppColors.outline,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
