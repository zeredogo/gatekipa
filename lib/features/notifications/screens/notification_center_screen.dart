// lib/features/notifications/screens/notification_center_screen.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gatekeepeer/core/theme/app_colors.dart';
import 'package:gatekeepeer/core/utils/date_formatter.dart';
import 'package:gatekeepeer/features/notifications/models/notification_model.dart';
import 'package:gatekeepeer/features/notifications/providers/notification_provider.dart';
import 'package:gatekeepeer/core/theme/app_spacing.dart';

class NotificationCenterScreen extends ConsumerWidget {
  const NotificationCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(notifFilterProvider);
    final notifs = ref.watch(filteredNotificationsProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(
          'Notifications',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.primary),
        ),
        leading: const BackButton(color: AppColors.onSurface),
        actions: [
          TextButton(
            onPressed: () {
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid != null) {
                ref
                    .read(notificationNotifierProvider.notifier)
                    .markAllRead(uid);
              }
            },
            child: const Text(
              'Mark all read',
              style: TextStyle(height: 1.2, fontFamily: 'Manrope', color: AppColors.primary,
                fontWeight: FontWeight.w600,
                fontSize: 13,),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter chips
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterChip(
                      label: 'All', value: 'all', current: filter, ref: ref),
                  _FilterChip(
                      label: 'Breach Alert',
                      value: 'alert',
                      current: filter,
                      ref: ref),
                  _FilterChip(
                      label: 'Security',
                      value: 'blocked',
                      current: filter,
                      ref: ref),
                  _FilterChip(
                      label: 'Transactions',
                      value: 'transaction',
                      current: filter,
                      ref: ref),
                  _FilterChip(
                      label: 'System',
                      value: 'system',
                      current: filter,
                      ref: ref),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Notifications list
          Expanded(
            child: RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () async {
                ref.invalidate(notificationNotifierProvider);
                await Future.delayed(const Duration(milliseconds: 500));
              },
              child: notifs.isEmpty
                  ? _EmptyNotifState()
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 140),
                      itemCount: notifs.length,
                      itemBuilder: (ctx, i) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _NotifCard(notif: notifs[i])
                            .animate(delay: (i * 50).ms)
                            .fadeIn()
                            .slideY(begin: 0.03, end: 0),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final String value;
  final String current;
  final WidgetRef ref;

  const _FilterChip({
    required this.label,
    required this.value,
    required this.current,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = value == current;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13,
            fontWeight: FontWeight.w600,),
        ),
        selected: isSelected,
        onSelected: (_) => ref.read(notifFilterProvider.notifier).state = value,
        selectedColor: AppColors.primary.withValues(alpha: 0.1),
        checkmarkColor: AppColors.primary,
        side: BorderSide(
          color: isSelected ? AppColors.primary : AppColors.outlineVariant,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
      ),
    );
  }
}

class _NotifCard extends ConsumerWidget {
  final NotificationModel notif;
  const _NotifCard({required this.notif});

  Color get _borderColor => switch (notif.type) {
        'blocked' => AppColors.error,
        'alert' => const Color(0xFFE65100),
        'transaction' => AppColors.primary,
        'upcoming' => const Color(0xFFFF6B35),
        _ => AppColors.outline,
      };

  IconData get _icon => switch (notif.type) {
        'blocked' => Icons.block_rounded,
        'alert' => Icons.notifications_active_rounded,
        'transaction' => Icons.receipt_long_rounded,
        'upcoming' => Icons.schedule_rounded,
        _ => Icons.info_outline_rounded,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null && !notif.isRead) {
          ref
              .read(notificationNotifierProvider.notifier)
              .markAsRead(uid, notif.id);
        }
        context.push('/home/notifications/${notif.id}', extra: notif);
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: notif.isRead
              ? AppColors.surfaceContainerLowest
              : _borderColor.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(18),
          border: Border(
            left: BorderSide(color: _borderColor, width: 4),
            right: BorderSide(
                color: AppColors.outlineVariant.withValues(alpha: 0.3)),
            top: BorderSide(
                color: AppColors.outlineVariant.withValues(alpha: 0.3)),
            bottom: BorderSide(
                color: AppColors.outlineVariant.withValues(alpha: 0.3)),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _borderColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_icon, color: _borderColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notif.title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight:
                          notif.isRead ? FontWeight.w500 : FontWeight.w700,
                      fontSize: 14,),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    notif.body,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12,
                      color: AppColors.onSurfaceVariant,
                      height: 1.4,),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    DateFormatter.timeAgo(notif.timestamp),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 11,
                      color: AppColors.outline,),
                  ),
                ],
              ),
            ),
            if (!notif.isRead)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 4, left: 8),
                decoration: BoxDecoration(
                  color: _borderColor,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyNotifState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.notifications_none_rounded,
              size: 64, color: AppColors.outline),
          const SizedBox(height: AppSpacing.md),
          Text(
            'No notifications',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurfaceVariant,),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            "You're all caught up!",
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.outline, fontSize: 14),
          ),
        ],
      ),
      ),
    );
  }
}
