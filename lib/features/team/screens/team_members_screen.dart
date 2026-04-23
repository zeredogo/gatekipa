// lib/features/team/screens/team_members_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gatekeepeer/core/theme/app_colors.dart';
import 'package:gatekeepeer/core/widgets/gk_toast.dart';
import 'package:gatekeepeer/features/accounts/models/account_model.dart';
import 'package:gatekeepeer/features/accounts/providers/account_provider.dart';
import 'package:gatekeepeer/core/theme/app_spacing.dart';

final teamMembersProvider =
    StreamProvider.family<List<Map<String, dynamic>>, String>((ref, accountId) {
  return FirebaseFirestore.instance
      .collection('team_members')
      .where('account_id', isEqualTo: accountId)
      .snapshots()
      .map((snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
});

class TeamMembersScreen extends ConsumerWidget {
  final AccountModel account;
  const TeamMembersScreen({super.key, required this.account});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(teamMembersProvider(account.id));
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        titleSpacing: 24,
        backgroundColor: AppColors.surface,
        scrolledUnderElevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${account.name} Team',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800,
                  fontSize: 20,
                  color: AppColors.onSurface),
            ),
            Text(
              'Manage access and roles',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12, color: AppColors.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Material(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: () {
                  if (currentUid != account.ownerUserId) {
                    GkToast.show(context,
                        message:
                            'Only the account owner can invite members.',
                        type: ToastType.error);
                    return;
                  }
                  _showInviteSheet(context, ref);
                },
                borderRadius: BorderRadius.circular(12),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.person_add_rounded,
                      color: Colors.white, size: 20),
                ),
              ),
            ),
          ),
        ],
      ),
      body: membersAsync.when(
        data: (members) {
          // Owner is always the account owner
          final ownerMembers = members.where((m) => m['user_id'] == account.ownerUserId).toList();
          final admins = members
              .where((m) => m['role'] == 'admin' && m['user_id'] != account.ownerUserId)
              .toList();
          final viewers = members
              .where((m) => m['role'] == 'viewer' && m['user_id'] != account.ownerUserId)
              .toList();

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    24, 16, 24, MediaQuery.of(context).padding.bottom + 32),
                  children: [
                    // ── Owner ─────────────────────────────────────────────
                    const _SectionHeader('Owner'),
                    const SizedBox(height: 10),
                    if (ownerMembers.isEmpty)
                      // Owner may not be in team_members — show current user
                      _MemberTile(
                        name: 'You',
                        email: FirebaseAuth.instance.currentUser?.email,
                        role: 'owner',
                        isYou: true,
                        accountId: account.id,
                        userId: currentUid,
                        isOwner: currentUid == account.ownerUserId,
                      ).animate().fadeIn()
                    else
                      ...ownerMembers.map((m) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _MemberTile(
                              name: m['user_id'] == currentUid ? 'You' : (m['user_name'] ?? 'Owner'),
                              email: m['user_email'],
                              role: 'owner',
                              isYou: m['user_id'] == currentUid,
                              accountId: account.id,
                              userId: m['user_id'] ?? '',
                              isOwner: true,
                            ).animate().fadeIn(),
                          )),

                    const SizedBox(height: 20),

                    // ── Admins ────────────────────────────────────────────
                    if (admins.isNotEmpty) ...[
                      const _SectionHeader('Admins'),
                      const SizedBox(height: 10),
                      ...admins.asMap().entries.map((e) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _MemberTile(
                              name: e.value['user_id'] == currentUid
                                  ? 'You'
                                  : (e.value['user_name'] ?? 'Admin'),
                              email: e.value['user_email'],
                              role: 'admin',
                              isYou: e.value['user_id'] == currentUid,
                              accountId: account.id,
                              userId: e.value['user_id'] ?? '',
                              isOwner: currentUid == account.ownerUserId,
                              spendLimit: e.value['spend_limit'],
                            ).animate(delay: (e.key * 40).ms).fadeIn(),
                          )),
                      const SizedBox(height: 20),
                    ],

                    // ── Viewers ───────────────────────────────────────────
                    if (viewers.isNotEmpty) ...[
                      const _SectionHeader('Viewers'),
                      const SizedBox(height: 10),
                      ...viewers.asMap().entries.map((e) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _MemberTile(
                              name: e.value['user_id'] == currentUid
                                  ? 'You'
                                  : (e.value['user_name'] ?? 'Viewer'),
                              email: e.value['user_email'],
                              role: 'viewer',
                              isYou: e.value['user_id'] == currentUid,
                              accountId: account.id,
                              userId: e.value['user_id'] ?? '',
                              isOwner: currentUid == account.ownerUserId,
                              spendLimit: e.value['spend_limit'],
                            ).animate(delay: (e.key * 40).ms).fadeIn(),
                          )),
                    ],

                    if (admins.isEmpty && viewers.isEmpty && ownerMembers.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          child: Text('No team members yet.',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceVariant)),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => const Center(child: Text('Failed to load team members.')),
      ),
    );
  }

  void _showInviteSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _InviteMemberSheet(accountId: account.id),
    );
  }
}

// ── Section Header ─────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 16,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(100),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: AppColors.onSurface,
                  letterSpacing: 0.2),
            ),
          ],
        ),
      );
}

// ── Member Tile ───────────────────────────────────────────────────────────────
class _MemberTile extends StatelessWidget {
  final String name;
  final String? email;
  final String role; // owner / admin / viewer
  final bool isYou;
  final String accountId;
  final String userId;
  final bool isOwner; // Whether the current user is the account owner (can remove)
  final num? spendLimit;

  const _MemberTile({
    required this.name,
    this.email,
    required this.role,
    required this.isYou,
    required this.accountId,
    required this.userId,
    required this.isOwner,
    this.spendLimit,
  });

  Color get _badgeColor {
    switch (role) {
      case 'owner':
        return AppColors.primary;
      case 'admin':
        return const Color(0xFF6366F1);
      default:
        return AppColors.onSurfaceVariant;
    }
  }

  Color get _badgeBg {
    switch (role) {
      case 'owner':
        return AppColors.primary.withValues(alpha: 0.1);
      case 'admin':
        return const Color(0xFF6366F1).withValues(alpha: 0.1);
      default:
        return AppColors.surfaceContainerHigh;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: AppColors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _badgeBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : 'U',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: _badgeColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 18),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      name,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.onSurface),
                    ),
                    if (isYou) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.outlineVariant.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('You',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.onSurfaceVariant)),
                      ),
                    ],
                  ],
                ),
                if (email != null && email!.isNotEmpty)
                  Text(email!, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 11, color: AppColors.onSurfaceVariant)),
              ],
            ),
          ),
          // Role badge & Spend Limit
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: _badgeBg, borderRadius: BorderRadius.circular(8)),
                child: Text(
                  role[0].toUpperCase() + role.substring(1),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12, fontWeight: FontWeight.w700, color: _badgeColor),
                ),
              ),
              if (spendLimit != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Limit: ₦${spendLimit!.toStringAsFixed(0)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.onSurfaceVariant, fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ]
            ],
          ),
          // Remove button (only for non-owner members and if current user is owner/admin)
          if (role != 'owner' && isOwner) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => _confirmRemove(context),
              child: const Icon(Icons.remove_circle_outline_rounded, color: AppColors.error, size: 20),
            ),
          ],
        ],
      ),
    );
  }

  void _confirmRemove(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Remove Member', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        content: Text('Remove $name from this account?', style: Theme.of(context).textTheme.bodyMedium),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await FirebaseFunctions.instance.httpsCallable('removeTeamMember').call({
                  'account_id': accountId,
                  'target_user_id': userId,
                });
                if (context.mounted) {
                  GkToast.show(context, message: 'Member removed', type: ToastType.success);
                }
              } catch (e) {
                if (context.mounted) {
                  GkToast.show(context, message: 'Permission denied', type: ToastType.error);
                }
              }
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}

// ── Invite Member Sheet (wireframe ⑥ panel) ────────────────────────────────────
class _InviteMemberSheet extends ConsumerStatefulWidget {
  final String accountId;
  const _InviteMemberSheet({required this.accountId});

  @override
  ConsumerState<_InviteMemberSheet> createState() => _InviteMemberSheetState();
}

class _InviteMemberSheetState extends ConsumerState<_InviteMemberSheet> {
  final _emailCtrl = TextEditingController();
  final _limitCtrl = TextEditingController();
  String _role = 'viewer';
  bool _loading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _limitCtrl.dispose();
    super.dispose();
  }

  bool get _isValidEmail {
    final email = _emailCtrl.text.trim();
    return email.isNotEmpty && RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(email);
  }

  Future<void> _submit() async {
    if (!_isValidEmail) {
      GkToast.show(context, message: 'Enter a valid email address', type: ToastType.error);
      return;
    }
    setState(() => _loading = true);

    final limitVal = double.tryParse(_limitCtrl.text.replaceAll(',', ''));

    final error = await ref.read(accountNotifierProvider.notifier).inviteTeamMember(
          accountId: widget.accountId,
          targetUserId: _emailCtrl.text.trim().toLowerCase(),
          role: _role,
          spendLimit: limitVal,
        );

    setState(() => _loading = false);
    if (mounted) {
      if (error == null) {
        GkToast.show(context, message: 'Invitation sent!', type: ToastType.success);
        Navigator.pop(context);
      } else {
        GkToast.show(context, message: error, type: ToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(color: AppColors.outlineVariant, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text('Invite Member',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.onSurface)),
            const SizedBox(height: 6),
            Text('Enter their email and assign a role.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13, color: AppColors.onSurfaceVariant)),
            const SizedBox(height: 20),

            // Email field
            TextField(
              controller: _emailCtrl,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Email',
                hintText: 'name@example.com',
                prefixIcon: const Icon(Icons.email_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Role selection — two card options
            Text('Role',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.onSurfaceVariant)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _RoleCard(
                  role: 'admin',
                  title: 'Admin',
                  description: 'Can manage cards, rules and team',
                  selected: _role == 'admin',
                  onTap: () => setState(() => _role = 'admin'),
                )),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: _RoleCard(
                  role: 'viewer',
                  title: 'Viewer',
                  description: 'Can view cards and transactions',
                  selected: _role == 'viewer',
                  onTap: () => setState(() => _role = 'viewer'),
                )),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            
            // Spend Limit
            Text('Monthly Spend Limit (Optional)',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.onSurfaceVariant)),
            const SizedBox(height: 10),
            TextField(
              controller: _limitCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Amount (NGN)',
                hintText: 'e.g. 50000',
                prefixIcon: const Icon(Icons.money_off_csred_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: (_loading || !_isValidEmail) ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _loading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Send Invite', style: TextStyle(height: 1.2, fontFamily: 'Manrope', fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String role;
  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.role,
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.06) : AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.outlineVariant.withValues(alpha: 0.6),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: selected ? AppColors.primary : AppColors.onSurface,)),
            const SizedBox(height: AppSpacing.xxs),
            Text(description,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 11, color: AppColors.onSurfaceVariant, height: 1.3)),
          ],
        ),
      ),
    );
  }
}
