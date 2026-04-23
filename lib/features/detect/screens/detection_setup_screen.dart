// lib/features/detect/screens/detection_setup_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gatekeepeer/core/constants/routes.dart';
import 'package:gatekeepeer/core/theme/app_colors.dart';
import 'package:gatekeepeer/core/widgets/gk_button.dart';
import 'package:gatekeepeer/core/widgets/gk_toast.dart';
import 'package:gatekeepeer/features/detect/providers/detection_provider.dart';
import 'package:gatekeepeer/core/theme/app_spacing.dart';

class DetectionSetupScreen extends ConsumerWidget {
  const DetectionSetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scanState = ref.watch(detectionScanProvider);
    final isDetecting = scanState.isLoading;
    final progress = scanState.progress;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(
          'Subscription Detector',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800,
            color: AppColors.primary,),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined,
                color: AppColors.onSurface),
            onPressed: () => context.push(Routes.notifications),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          ref.invalidate(detectedSubscriptionsProvider);
          await Future.delayed(const Duration(milliseconds: 800));
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(left: 24, right: 24, top: 24, bottom: 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, Color(0xFF005027)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.radar_rounded,
                      color: Colors.white, size: 44),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Subscription\nVulnerability Scan',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      height: 1.2,),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Detect recurring charges before they become a problem.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70,
                      fontSize: 14,
                      height: 1.5,),
                  ),
                  const SizedBox(height: 20),
                  // Progress bar
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Scan Progress',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white60,
                              fontSize: 12,),
                          ),
                          Text(
                            '${(progress * 100).toStringAsFixed(0)}%',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(100),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 8,
                          backgroundColor: Colors.white.withAlpha(51),
                          valueColor:
                              const AlwaysStoppedAnimation(Colors.white),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ).animate().fadeIn().slideY(begin: 0.05, end: 0),
            const SizedBox(height: 28),

            // Connectors
            Text(
              'Connect Accounts',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 20,
                fontWeight: FontWeight.w800,),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Grant read-only access to scan for subscription patterns.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceVariant,
                fontSize: 14,),
            ),
            const SizedBox(height: AppSpacing.md),
            const _ConnectorCard(
              icon: Icons.mail_rounded,
              color: Color(0xFFEA4335),
              name: 'Gmail',
              sub: 'Email integration — coming soon',
            ).animate().fadeIn(delay: 100.ms),
            const SizedBox(height: 10),
            const _ConnectorCard(
              icon: Icons.mail_outline_rounded,
              color: Color(0xFF0078D4),
              name: 'Outlook',
              sub: 'Email integration — coming soon',
            ).animate().fadeIn(delay: 150.ms),
            const SizedBox(height: 10),
            const _ConnectorCard(
              icon: Icons.sms_rounded,
              color: Color(0xFF25D366),
              name: 'SMS / Bank Alerts',
              sub: 'SMS integration — coming soon',
            ).animate().fadeIn(delay: 200.ms),
            const SizedBox(height: 28),

            // Stats row — live from Firestore
            _LiveStatsRow().animate().fadeIn(delay: 250.ms),
            const SizedBox(height: AppSpacing.sm),

          ],
        ),
      ),
      ), // Close RefreshIndicator
      // ── Sticky dual-button bottom bar ──────────────────────────────────
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(
            24, 16, 24, MediaQuery.of(context).padding.bottom + 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GkButton(
              label: isDetecting ? 'Scanning...' : 'Run Full Scan',
              icon: Icons.search_rounded,
              isLoading: isDetecting,
              onPressed: () async {
                try {
                  // Pass empty messages list — real messages will come from
                  // SMS/email connectors once those integrations are built.
                  final count = await ref
                      .read(detectionScanProvider.notifier)
                      .runScan(messages: const []);
                  if (context.mounted) {
                    GkToast.show(context,
                        message: count > 0
                            ? '$count unprotected subscriptions found!'
                            : 'No new subscriptions detected.',
                        type: count > 0 ? ToastType.info : ToastType.success,
                        title: '\u{1F50D} Scan Complete');
                  }
                } catch (e) {
                  if (context.mounted) {
                    GkToast.show(context,
                        message: 'Scan failed. Check your connection.',
                        type: ToastType.error,
                        title: 'Scan Failed');
                  }
                }
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            GkButton(
              label: 'View Detected Subscriptions',
              variant: GkButtonVariant.secondary,
              icon: Icons.list_rounded,
              onPressed: () => context.push(Routes.detectedSubscriptions),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Live stats row reading from Firestore ─────────────────────────────────────
class _LiveStatsRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subs = ref.watch(detectedSubscriptionsProvider).valueOrNull ?? [];
    double totalExposure = 0;
    for (final s in subs) {
      final raw = s['amount'];
      if (raw is num) totalExposure += raw.toDouble(); // amounts already in ₦
    }
    final protectedCount = subs.where((s) => s['protected'] == true).length;

    return Row(
      children: [
        Expanded(
            child: _StatBox(
          value: '${subs.length}',
          label: 'Detected',
          icon: Icons.warning_amber_rounded,
          color: AppColors.error,
        )),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
            child: _StatBox(
          value: totalExposure > 0
              ? '₦${(totalExposure / 1000).toStringAsFixed(1)}K'
              : '₦0',
          label: 'Monthly Exposure',
          icon: Icons.money_off_rounded,
          color: const Color(0xFFFF6B35),
        )),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
            child: _StatBox(
          value: '$protectedCount',
          label: 'Protected',
          icon: Icons.shield_rounded,
          color: AppColors.tertiary,
        )),
      ],
    );
  }
}

class _ConnectorCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String name;
  final String sub;

  const _ConnectorCard({
    required this.icon,
    required this.color,
    required this.name,
    required this.sub,
  });

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
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 14)),
                Text(sub,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 11, color: AppColors.onSurfaceVariant)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.outlineVariant.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: Text(
              'Soon',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.onSurfaceVariant,),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  const _StatBox({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: AppSpacing.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800,
                fontSize: 20,
                color: color,),
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 11,
                color: AppColors.onSurfaceVariant,),
            ),
          ),
        ],
      ),
    );
  }
}
