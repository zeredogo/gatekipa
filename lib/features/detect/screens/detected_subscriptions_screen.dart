// lib/features/detect/screens/detected_subscriptions_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gatekipa/core/constants/routes.dart';
import 'package:gatekipa/core/theme/app_colors.dart';
import 'package:gatekipa/features/detect/providers/detection_provider.dart';
import 'package:gatekipa/core/theme/app_spacing.dart';

class DetectedSubscriptionsScreen extends ConsumerWidget {
  const DetectedSubscriptionsScreen({super.key});

  Color _hexToColor(String hexString) {
    var hexColor = hexString.replaceAll("#", "");
    if (hexColor.length == 6) {
      hexColor = "FF$hexColor";
    }
    if (hexColor.length == 8) {
      return Color(int.parse("0x$hexColor"));
    }
    return AppColors.primary;
  }

  IconData _stringToIcon(String? iconName) {
    switch (iconName) {
      case 'tv_rounded':
        return Icons.tv_rounded;
      case 'music_note_rounded':
        return Icons.music_note_rounded;
      case 'design_services_rounded':
        return Icons.design_services_rounded;
      case 'cloud_rounded':
        return Icons.cloud_rounded;
      case 'newspaper_rounded':
        return Icons.newspaper_rounded;
      case 'folder_rounded':
        return Icons.folder_rounded;
      case 'apple_rounded':
        return Icons.apple;
      case 'work_rounded':
        return Icons.work_rounded;
      default:
        return Icons.receipt_long_rounded;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscriptionsAsync = ref.watch(detectedSubscriptionsProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(
          'Detected Subscriptions',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.primary),
        ),
        leading: const BackButton(color: AppColors.onSurface),
        actions: [
          IconButton(
            icon: const Icon(Icons.radar_rounded, color: AppColors.primary),
            tooltip: 'Run New Scan',
            onPressed: () => context.push(Routes.detect),
          ),
        ],
      ),
      body: subscriptionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => const Center(child: Text('Failed to load data. Please pull to refresh.')),
        data: (subs) {
          if (subs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.shield_rounded, color: AppColors.outlineVariant, size: 60)
                      .animate()
                      .scale(delay: 200.ms, begin: const Offset(0.8, 0.8)),
                  const SizedBox(height: AppSpacing.md),
                  Text('No unprotected subscriptions found.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceVariant, fontSize: 14)),
                ],
              ),
            );
          }

          double parseAmount(dynamic rawAmount) {
            if (rawAmount == null) return 0.0;
            if (rawAmount is num) return rawAmount.toDouble();
            if (rawAmount is String) {
              final digitsOnly = rawAmount.replaceAll(RegExp(r'[^0-9]'), '');
              return (double.tryParse(digitsOnly) ?? 0.0); // Rough fallback
            }
            return 0.0;
          }

          final totalExposure = subs.fold<double>(
              0.0, (sum, sub) => sum + parseAmount(sub['amount']));

          return Column(
            children: [
              // Summary banner
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(18),
                  border:
                      Border.all(color: AppColors.error.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: AppColors.error, size: 24),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${subs.length} Unprotected Subscriptions',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: AppColors.error,),
                          ),
                          Text(
                            'Total exposure: ₦${totalExposure.toStringAsFixed(0)}/month',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12,
                              color: AppColors.onSurfaceVariant,),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn().slideY(begin: -0.2),
              // List
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    0,
                    24,
                    MediaQuery.of(context).padding.bottom + 24,
                  ),
                  itemCount: subs.length,
                  itemBuilder: (ctx, i) {
                    final data = subs[i];
                    final displayAmount = parseAmount(data['amount']);  // already in ₦
                    final color = _hexToColor(data['color_hex'] ?? '#000000');
                    final icon = _stringToIcon(data['icon']);

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _SubCard(
                        name: data['name'] ?? 'Unknown',
                        category: data['category'] ?? 'Service',
                        amount: displayAmount,
                        cycle: data['cycle'] ?? 'monthly',
                        color: color,
                        icon: icon,
                      )
                          .animate(delay: (i * 70).ms)
                          .fadeIn()
                          .slideX(begin: 0.05, end: 0),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SubCard extends StatelessWidget {
  final String name;
  final String category;
  final double amount;
  final String cycle;
  final Color color;
  final IconData icon;

  const _SubCard({
    required this.name,
    required this.category,
    required this.amount,
    required this.cycle,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, fontSize: 15)),
                    Text(
                      category,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12, color: AppColors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₦${amount.toStringAsFixed(0)}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: AppColors.error,),
                  ),
                  Text(
                    '/ $cycle',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 11, color: AppColors.outline),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // Status row
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppColors.error,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'UNPROTECTED',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.error,
                        letterSpacing: 0.5,),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Protect CTA
              GestureDetector(
                onTap: () => context.push(
                  Routes.cardCreation,
                  extra: {'name': name, 'category': category},
                ),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    '🛡️  Protect',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,),
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
