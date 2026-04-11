// lib/features/notifications/screens/notification_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/gk_button.dart';
import '../models/notification_model.dart';

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
          style: GoogleFonts.manrope(
              fontWeight: FontWeight.w800, color: AppColors.primary),
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
                    const SizedBox(height: 16),
                    Text(
                      'Transaction Blocked',
                      style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                        color: AppColors.error,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (meta != null && meta['amount'] != null)
                      Text(
                        '₦${meta['amount']}',
                        style: GoogleFonts.manrope(
                          fontWeight: FontWeight.w800,
                          fontSize: 36,
                          color: AppColors.onSurface,
                        ),
                      ),
                    if (meta != null && meta['merchant'] != null)
                      Text(
                        meta['merchant'],
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ).animate().fadeIn().scale(
                    begin: const Offset(0.95, 0.95),
                    end: const Offset(1, 1),
                    duration: 400.ms,
                  ),
              const SizedBox(height: 24),
            ],

            // Notification body
            Text(
              notif.title,
              style: GoogleFonts.manrope(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              notif.body,
              style: GoogleFonts.inter(
                fontSize: 15,
                color: AppColors.onSurfaceVariant,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              DateFormatter.formatDateTime(notif.timestamp),
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppColors.outline,
              ),
            ),

            if (meta != null && meta['ruleTriggered'] != null) ...[
              const SizedBox(height: 24),
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
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Rule Triggered',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            meta['ruleTriggered'],
                            style: GoogleFonts.manrope(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: AppColors.primary,
                            ),
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
              const SizedBox(height: 12),
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
