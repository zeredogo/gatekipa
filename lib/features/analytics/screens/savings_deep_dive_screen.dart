// lib/features/analytics/screens/savings_deep_dive_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:gatekeepeer/core/theme/app_colors.dart';
import 'package:gatekeepeer/features/analytics/providers/analytics_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gatekeepeer/core/theme/app_spacing.dart';

class SavingsDeepDiveScreen extends ConsumerWidget {
  const SavingsDeepDiveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsAsync = ref.watch(analyticsProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(
          'Savings Deep Dive',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.primary),
        ),
        leading: const BackButton(color: AppColors.onSurface),
      ),
      body: analyticsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
        data: (analytics) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 140),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hero recovered capital
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(28),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.primary, Color(0xFF005027)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.all(Radius.circular(24)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Recovered Capital',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white60, fontSize: 14)),
                      const SizedBox(height: AppSpacing.xs),
                      Text('₦${analytics.recoveredCapital.toStringAsFixed(0)}',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white,
                            fontSize: 44,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1,)),
                      const SizedBox(height: AppSpacing.xxs),
                      Text('Since you joined Gatekipa',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white54, fontSize: 13)),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: _MiniStat(
                                label: 'Charges Blocked',
                                value: '${analytics.chargesBlocked}',
                                icon: Icons.block_rounded),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: _MiniStat(
                                label: 'Trial Cards',
                                value: '${analytics.trialCardsCount}',
                                icon: Icons.credit_card_rounded),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: _MiniStat(
                                label: 'Months Active',
                                value: '${analytics.monthsActive}',
                                icon: Icons.calendar_month_rounded),
                          ),
                        ],
                      ),
                    ],
                  ),
                ).animate().fadeIn().slideY(begin: 0.05, end: 0),
                const SizedBox(height: AppSpacing.lg),

                // Trend chart
                Text('Activity Trend',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: AppSpacing.sm),
                _TrendChart(
                  values: analytics.trendValues,
                  months: analytics.trendMonths,
                ).animate().fadeIn(delay: 150.ms),
                const SizedBox(height: AppSpacing.lg),

                // Blocked trial cards
                Text('Blocked Trial Cards',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: AppSpacing.sm),
                ...analytics.blockedTrials.asMap().entries.map((e) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _BlockedTrialCard(trial: e.value)
                        .animate(delay: (e.key * 70).ms)
                        .fadeIn()
                        .slideX(begin: 0.05, end: 0),
                  );
                }),
                const SizedBox(height: AppSpacing.lg),

                // Protection score
                _ProtectionScoreCard(score: analytics.protectionScore),
                const SizedBox(height: AppSpacing.lg),

                // Milestones
                Text('Savings Milestones',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: AppSpacing.sm),
                ...analytics.milestones.asMap().entries.map((e) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _MilestoneRow(m: e.value)
                        .animate(delay: (e.key * 60).ms)
                        .fadeIn(),
                  );
                }),
                const SizedBox(height: 160),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _MiniStat(
      {required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white60, size: 18),
          const SizedBox(height: 6),
          Text(value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 18)),
          Text(label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white54, fontSize: 10)),
        ],
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  final List<double> values;
  final List<String> months;

  const _TrendChart({required this.values, required this.months});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, m) {
                  final idx = v.toInt();
                  if (idx < 0 || idx >= months.length) {
                    return const SizedBox.shrink();
                  }
                  return Text(months[idx],
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 10, color: AppColors.outline));
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: values
                  .asMap()
                  .entries
                  .map((e) => FlSpot(e.key.toDouble(), e.value))
                  .toList(),
              isCurved: true,
              color: AppColors.primary,
              barWidth: 3,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: AppColors.primary.withValues(alpha: 0.1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}



class _BlockedTrialCard extends StatelessWidget {
  final TrialData trial;
  const _BlockedTrialCard({required this.trial});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border:
            Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.tertiaryFixed.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.block_rounded,
                color: AppColors.tertiary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(trial.name,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 14)),
                Text(trial.date,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 11, color: AppColors.outline)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₦${trial.savedAmount.toStringAsFixed(0)}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800,
                  color: AppColors.tertiary,
                  fontSize: 15,),
              ),
              Text(
                trial.autoBlocked ? 'Auto-blocked' : 'Manual',
                style:
                    Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 10, color: AppColors.outline),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProtectionScoreCard extends StatelessWidget {
  final int score;
  const _ProtectionScoreCard({required this.score});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          const Icon(Icons.shield_rounded, color: AppColors.primary, size: 40),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Protection Score',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceVariant, fontSize: 12)),
                Text('$score/100',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary)),
                Text('Your vault is highly secured.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12, color: AppColors.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}



class _MilestoneRow extends StatelessWidget {
  final Milestone m;
  const _MilestoneRow({required this.m});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: m.achieved
            ? AppColors.tertiaryContainer.withValues(alpha: 0.2)
            : AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: m.achieved
              ? AppColors.tertiary.withValues(alpha: 0.3)
              : AppColors.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(
            m.achieved
                ? Icons.emoji_events_rounded
                : Icons.lock_outline_rounded,
            color: m.achieved ? const Color(0xFFFFD700) : AppColors.outline,
            size: 24,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, fontSize: 13)),
                Text(m.sub,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 11, color: AppColors.onSurfaceVariant)),
              ],
            ),
          ),
          if (m.achieved)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.tertiary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text('✓ Done',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.tertiary)),
            ),
        ],
      ),
    );
  }
}
