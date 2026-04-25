// lib/features/notifications/screens/notification_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:gatekipa/core/constants/routes.dart';
import 'package:gatekipa/core/theme/app_colors.dart';
import 'package:gatekipa/core/utils/date_formatter.dart';
import 'package:gatekipa/core/widgets/gk_button.dart';
import 'package:gatekipa/features/notifications/models/notification_model.dart';
import 'package:gatekipa/core/theme/app_spacing.dart';

class NotificationDetailScreen extends StatelessWidget {
  final String notifId;
  const NotificationDetailScreen({super.key, required this.notifId});

  NotificationModel? _getNotifFromRoute(BuildContext context) {
    final extra = GoRouterState.of(context).extra;
    return extra is NotificationModel ? extra : null;
  }

  @override
  Widget build(BuildContext context) {
    final notif = _getNotifFromRoute(context);

    if (notif == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Notification not found')),
      );
    }

    final isBlocked = notif.type == 'blocked';
    final meta = notif.metadata;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(
          'Notification Detail',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.primary),
        ),
        leading: const BackButton(color: AppColors.onSurface),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 140),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Type indicator
            if (isBlocked) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(24),
                  border:
                      Border.all(color: AppColors.error.withValues(alpha: 0.2)),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.block_rounded,
                          color: AppColors.error, size: 32),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Transaction Blocked',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800,
                        fontSize: 20,
                        color: AppColors.error,),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    if (meta != null && meta['amount'] != null)
                      Text(
                        '₦${meta['amount']}',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800,
                          fontSize: 36,
                          color: AppColors.onSurface,),
                      ),
                    if (meta != null && meta['merchant'] != null)
                      Text(
                        meta['merchant'],
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 16,
                          color: AppColors.onSurfaceVariant,),
                      ),
                  ],
                ),
              ).animate().fadeIn().scale(
                    begin: const Offset(0.95, 0.95),
                    end: const Offset(1, 1),
                    duration: 400.ms,
                  ),
              const SizedBox(height: AppSpacing.lg),
            ],

            // Notification body
            Text(
              notif.title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.onSurface,),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              notif.body,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 15,
                color: AppColors.onSurfaceVariant,
                height: 1.6,),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              DateFormatter.formatDateTime(notif.timestamp),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12,
                color: AppColors.outline,),
            ),

            if (meta != null && meta['ruleTriggered'] != null) ...[
              const SizedBox(height: AppSpacing.lg),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.15)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.gavel_rounded,
                        color: AppColors.primary, size: 20),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Rule Triggered',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600,
                              fontSize: 12,
                              color: AppColors.onSurfaceVariant,),
                          ),
                          Text(
                            meta['ruleTriggered'],
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: AppColors.primary,),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 36),

            if (isBlocked) ...[
              GkButton(
                label: 'Adjust Rule',
                icon: Icons.tune_rounded,
                variant: GkButtonVariant.secondary,
                onPressed: () => context.push(Routes.cards),
              ),
              const SizedBox(height: AppSpacing.sm),
              GkButton(
                label: 'Confirm Block',
                icon: Icons.check_rounded,
                onPressed: () => context.pop(),
              ),
            ] else ...[
              GkButton(
                label: 'Got it',
                onPressed: () => context.pop(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
