// lib/features/analytics/screens/analytics_hub_screen.dart
import 'package:flutter/material.dart';

import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:gatekipa/core/constants/app_constants.dart';
import 'package:gatekipa/core/constants/routes.dart';
import 'package:gatekipa/core/theme/app_colors.dart';
import 'package:gatekipa/core/widgets/gk_button.dart';
import 'package:gatekipa/features/auth/providers/auth_provider.dart';
import 'package:gatekipa/features/analytics/providers/analytics_provider.dart';
import 'package:gatekipa/features/profile/screens/premium_upgrade_screen.dart';
import 'package:gatekipa/core/theme/app_spacing.dart';

class AnalyticsHubScreen extends ConsumerWidget {
  const AnalyticsHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userProfileProvider);

    return userAsync.when(
      data: (user) {
        final isPremium = user?.planTier == 'premium';
        return Scaffold(
          backgroundColor: AppColors.surface,
          body: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async {
              ref.invalidate(analyticsProvider);
              ref.invalidate(userProfileProvider);
              await Future.delayed(const Duration(milliseconds: 800));
            },
            child: CustomScrollView(
              slivers: [
              SliverAppBar(
                backgroundColor: AppColors.surface,
                floating: true,
                title: Text(
                  'Insights',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                      fontSize: 22),
                ),
                actions: [
                  if (!isPremium)
                    Container(
                      margin: const EdgeInsets.only(right: 16),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                        ),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        '✦ PREMIUM',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 1,),
                      ),
                    ),
                ],
              ),
              SliverToBoxAdapter(
                child: isPremium
                    ? const _AnalyticsContent()
                    : const _PremiumGate(),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 140)),
            ],
          ),
          ),
        );
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) =>
          const Scaffold(body: Center(child: Text('Error loading profile'))),
    );
  }
}

// ── Premium Gate ────────────────────────────────────────────────────────────────
class _PremiumGate extends StatelessWidget {
  const _PremiumGate();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(36),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1a1a2e), Color(0xFF16213e)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              children: [
                const Icon(Icons.workspace_premium_rounded,
                    color: Color(0xFFFFD700), size: 56),
                const SizedBox(height: 20),
                Text(
                  'Sentinel Prime',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Unlock full insights: savings analytics, efficiency portfolio, and spending intelligence.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white60,
                    fontSize: 14,
                    height: 1.6,),
                ),
                const SizedBox(height: 28),
                // Feature list
                ...[
                  '₦ Savings deep-dive & projections',
                  'Efficiency portfolio score',
                  'Cost-per-use spending intelligence',
                  'Data-driven portfolio diagnostics',
                  'Vampire subscription detection',
                ].map((f) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_rounded,
                              color: Color(0xFFFFD700), size: 18),
                          const SizedBox(width: 10),
                          Text(
                            f,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70,
                              fontSize: 14,),
                          ),
                        ],
                      ),
                    )),
                const SizedBox(height: 28),
                GkButton(
                  label: 'Upgrade — ${AppConstants.premiumPriceLabel.replaceAll('/mo', '/month')}',
                  icon: Icons.workspace_premium_rounded,
                  onPressed: () {
                    Navigator.of(context, rootNavigator: true).push(
                      MaterialPageRoute(
                        builder: (_) => const PremiumUpgradeScreen(),
                      ),
                    );
                  },
                  width: double.infinity,
                ),
              ],
            ),
          ).animate().fadeIn().scale(
                begin: const Offset(0.95, 0.95),
                end: const Offset(1, 1),
                duration: 400.ms,
              ),

          // Blurred preview
          const SizedBox(height: 28),
          Text(
            'Preview (Premium)',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 18,
              fontWeight: FontWeight.w800,),
          ),
          const SizedBox(height: AppSpacing.sm),
          const ImageFiltered(
            imageFilter: ColorFilter.mode(
              Colors.white54,
              BlendMode.luminosity,
            ),
            child: _AnalyticsSavingsCard(blurred: true),
          ),
          const SizedBox(height: 140),
        ],
      ),
    );
  }
}

// ── Full Analytics Content ──────────────────────────────────────────────────────
class _AnalyticsContent extends ConsumerWidget {
  const _AnalyticsContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsAsync = ref.watch(analyticsProvider);

    return analyticsAsync.when(
      data: (analytics) {
              final projectedSavings = analytics.monthsActive > 0 
                  ? (analytics.recoveredCapital / analytics.monthsActive) * 12 
                  : 0.0;
              final fmtSavings = '₦${projectedSavings.toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (Match m) => "${m[1]},")}';
              final recommendation = analytics.chargesBlocked > 0 
                  ? 'Your Gatekeeper controls have actively blocked ${analytics.chargesBlocked} unwanted charges recently. Great job protecting your portfolio.'
                  : 'No unusual spending patterns detected across your active cards.';

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: analytics.txCount == 0
                    ? const _EmptyAnalyticsState()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _AnalyticsSavingsCard(
                            blurred: false,
                            totalSpend: analytics.totalSpend,
                            blockedCount: analytics.chargesBlocked,
                            txCount: analytics.txCount,
                          ),
                          const SizedBox(height: 40),
                          _MonthlyBarChart(
                            values: analytics.trendValues,
                            months: analytics.trendMonths,
                          ),
                          const SizedBox(height: 40),
                          _ProjectionCard(projectedAmount: fmtSavings),
                          const SizedBox(height: 40),
                          Text(
                            'Portfolio Diagnostics',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 18, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          _RecommendationCard(rec: recommendation),
                          const SizedBox(height: 40),
                          _FeatureCard(
                            title: 'Efficiency Portfolio',
                            subtitle: 'Analyze transaction reliability & velocity',
                            icon: Icons.analytics_rounded,
                            color: AppColors.secondary,
                            onTap: () => context.push(Routes.efficiencyPortfolio),
                          ).animate().fadeIn(delay: 100.ms),
                          const SizedBox(height: AppSpacing.lg),
                          _PremiumGradientCard(
                            title: 'Savings Deep Dive',
                            subtitle: 'Examine cost-per-use and subscription bloat',
                            icon: Icons.savings_rounded,
                            onTap: () => context.push(Routes.savingsDeepDive),
                          ).animate().fadeIn(delay: 200.ms),
                          const SizedBox(height: 140),
                        ],
                      ),
              );
      },
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(40.0),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (e, __) => Center(
        child: Padding(
          padding: const EdgeInsets.all(40.0),
          child: Text(
            'We encountered an issue preparing your insights.\nEnsure all accounts are synced.\n\n$e',
            textAlign: TextAlign.center,
            style: const TextStyle(height: 1.2, fontFamily: 'Manrope', color: Colors.redAccent, fontSize: 13),
          ),
        ),
      ),
    );
  }
}

// ── Empty State ──────────────────────────────────────────────────────────────────
class _EmptyAnalyticsState extends StatelessWidget {
  const _EmptyAnalyticsState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.insights_rounded,
              size: 52,
              color: AppColors.primary,
            ),
          ).animate().scale(
                begin: const Offset(0.7, 0.7),
                end: const Offset(1, 1),
                duration: 500.ms,
                curve: Curves.elasticOut,
              ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'No data yet',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 22,
              fontWeight: FontWeight.w800,),
          ),
          const SizedBox(height: 10),
          Text(
            'Create virtual cards and start using them.\nYour spending intelligence will appear here.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14,
              color: AppColors.onSurfaceVariant,
              height: 1.6,),
          ),
        ],
      ),
    );
  }
}



class _RecommendationCard extends StatelessWidget {
  final String rec;
  const _RecommendationCard({required this.rec});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.secondary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.tips_and_updates_rounded, color: AppColors.secondary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Smart Insight',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13, fontWeight: FontWeight.w700)),
                Text(rec,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12,
                        color: AppColors.onSurfaceVariant,
                        height: 1.4)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.outline),
        ],
      ),
    );
  }
}

// ── Savings Hero Card ───────────────────────────────────────────────────────────
class _AnalyticsSavingsCard extends StatelessWidget {
  final bool blurred;
  final double totalSpend;
  final int blockedCount;
  final int txCount;

  const _AnalyticsSavingsCard({
    required this.blurred,
    this.totalSpend = 0.0,
    this.blockedCount = 0,
    this.txCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, Color(0xFF1B4D3E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Total Spend (This Month)',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white60, fontSize: 14)),
          const SizedBox(height: AppSpacing.xs),
          Text('₦${totalSpend.toStringAsFixed(0)}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white,
                fontSize: 40,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,)),
          const SizedBox(height: AppSpacing.xxs),
          Text('Tracked across all virtual cards',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.primaryFixed,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                  child: _StatPill(
                      label: 'Charges Blocked',
                      value: blockedCount.toString())),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                  child: _StatPill(
                      label: 'Transactions', value: txCount.toString())),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(delay: 100.ms);
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final String value;
  const _StatPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white54, fontSize: 11)),
          Text(value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

// ── Monthly Bar Chart ───────────────────────────────────────────────────────────
class _MonthlyBarChart extends StatelessWidget {
  final List<double> values;
  final List<String> months;

  const _MonthlyBarChart({required this.values, required this.months});

  @override
  Widget build(BuildContext context) {
    final maxData = values.isEmpty ? 0.0 : values.reduce((a, b) => a > b ? a : b);
    final computedMax = maxData <= 0 ? 1000.0 : maxData * 1.25; // Add 25% padding

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
          Text('Recent Activity Trend',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 160,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: computedMax,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, meta) {
                        final idx = v.toInt();
                        if (idx < 0 || idx >= months.length) {
                          return const SizedBox.shrink();
                        }
                        return Text(
                          months[idx],
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 11, color: AppColors.outline),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: values.asMap().entries.map((e) {
                  final isLast = e.key == values.length - 1;
                  return BarChartGroupData(
                    x: e.key,
                    barRods: [
                      BarChartRodData(
                        toY: e.value,
                        color:
                            isLast ? AppColors.primary : AppColors.primaryFixed,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(6)),
                        width: 20,
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 200.ms);
  }
}

// ── Projection Card ─────────────────────────────────────────────────────────────
class _ProjectionCard extends StatelessWidget {
  final String projectedAmount;

  const _ProjectionCard({required this.projectedAmount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.tertiaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.tertiary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.tertiary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.trending_up_rounded,
                color: AppColors.tertiary, size: 28),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Projected Annual Savings',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12, color: AppColors.onSurfaceVariant)),
                Text(projectedAmount,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppColors.tertiary)),
                Text('Based on last 90 days',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 11, color: AppColors.outline)),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 300.ms);
  }
}

// ── Actionable Cards ─────────────────────────────────────────────────────────────
class _PremiumGradientCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _PremiumGradientCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6A11CB), Color(0xFF2575FC)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6A11CB).withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            )
          ]
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.8)),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_rounded, color: Colors.white.withValues(alpha: 0.8)),
          ],
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _FeatureCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, fontSize: 16, color: color),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12, color: AppColors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, color: color, size: 16),
          ],
        ),
      ),
    );
  }
}
