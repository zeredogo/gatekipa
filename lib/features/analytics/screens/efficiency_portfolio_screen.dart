// lib/features/analytics/screens/efficiency_portfolio_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gatekeepeer/core/theme/app_colors.dart';
import 'package:gatekeepeer/features/analytics/providers/analytics_provider.dart';
import 'package:gatekeepeer/core/theme/app_spacing.dart';

class EfficiencyPortfolioScreen extends ConsumerWidget {
  const EfficiencyPortfolioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsAsync = ref.watch(analyticsProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(
          'Efficiency Portfolio',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.primary),
        ),
        leading: const BackButton(color: AppColors.onSurface),
      ),
      body: analyticsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
        data: (analytics) {
          final vampireServices = analytics.topServices.where((s) => s.efficiency <= 40).toList();
          
          // Efficiency score: % of transactions that passed without block,
          // weighted so more blocked = lower score.
          final total = analytics.txCount;
          final blocked = analytics.chargesBlocked;
          final efficiencyScore = total == 0
              ? 100 // No data yet — assume perfect
              : ((total - blocked) / total * 100).round().clamp(0, 100);

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 140),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Efficiency score ring
                _EfficiencyRing(score: efficiencyScore),
                const SizedBox(height: 28),

                // Vampire subscriptions
                if (vampireServices.isNotEmpty) ...[
                  Text(
                    'Vampire Subscriptions',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'High cost, low usage — consider cancelling.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13, color: AppColors.onSurfaceVariant),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ...vampireServices.asMap().entries.map((e) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _CostPerUseCard(service: e.value)
                          .animate(delay: (e.key * 80).ms)
                          .fadeIn(),
                    );
                  }),
                  const SizedBox(height: AppSpacing.lg),
                ],

                // All subscriptions ranked
                Text(
                  'Cost-Per-Use Ranking',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: AppSpacing.sm),
                ...analytics.topServices.asMap().entries.map((e) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _CostPerUseCard(service: e.value)
                        .animate(delay: (e.key * 60).ms)
                        .fadeIn()
                        .slideY(begin: 0.05, end: 0),
                  );
                }),
                const SizedBox(height: 80),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _EfficiencyRing extends StatelessWidget {
  final int score;
  const _EfficiencyRing({required this.score});

  Color get _ringColor {
    if (score >= 80) return AppColors.tertiary;
    if (score >= 50) return const Color(0xFFFF6B35);
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        border:
            Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Text('Efficiency Score',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceVariant, fontSize: 14)),
          const SizedBox(height: 20),
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 160,
                height: 160,
                child: CircularProgressIndicator(
                  value: score / 100,
                  strokeWidth: 14,
                  backgroundColor: AppColors.surfaceContainer,
                  color: _ringColor,
                  strokeCap: StrokeCap.round,
                ),
              ),
              Column(
                children: [
                  Text(
                    '$score',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 48,
                      fontWeight: FontWeight.w800,
                      color: _ringColor,),
                  ),
                  Text(
                    'out of 100',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12, color: AppColors.outline),
                  ),
                ],
              ),
            ],
          ).animate().scale(
                begin: const Offset(0.8, 0.8),
                end: const Offset(1, 1),
                duration: 500.ms,
                curve: Curves.elasticOut,
              ),
          const SizedBox(height: 20),
          Text(
            score >= 80
                ? '🎯 Excellent — your subscriptions are well-optimised.'
                : score >= 50
                    ? '⚠️ Fair — some subscriptions have low usage.'
                    : '🚨 Poor — several vampire subscriptions detected.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13, color: AppColors.onSurfaceVariant, height: 1.5),
          ),
        ],
      ),
    );
  }
}



class _CostPerUseCard extends StatelessWidget {
  final ServiceItem service;
  const _CostPerUseCard({required this.service});

  Color get _effColor {
    if (service.efficiency >= 70) return AppColors.tertiary;
    if (service.efficiency >= 40) return const Color(0xFFFF6B35);
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: service.efficiency < 20
              ? AppColors.error.withValues(alpha: 0.3)
              : AppColors.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: service.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(service.icon, color: service.color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(service.name,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, fontSize: 14)),
                Text('${service.category} • ${service.usage}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 11, color: AppColors.onSurfaceVariant)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₦${service.cost.toStringAsFixed(0)}/mo',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _effColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  '${service.efficiency}% efficient',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _effColor),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
