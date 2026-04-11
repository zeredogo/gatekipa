// lib/features/accounts/screens/account_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/gk_toast.dart';
import '../../cards/models/virtual_card_model.dart';
import '../../cards/providers/card_provider.dart';
import '../models/account_model.dart';
import '../providers/account_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../team/screens/team_members_screen.dart';

class AccountDetailScreen extends ConsumerWidget {
  final AccountModel account;

  const AccountDetailScreen({super.key, required this.account});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardsAsync = ref.watch(accountCardsProvider(account.id));
    final txAsync = ref.watch(accountTransactionsProvider(account.id));

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        titleSpacing: 0,
        backgroundColor: AppColors.surface,
        scrolledUnderElevation: 0,
        title: Text(
          account.name,
          style: GoogleFonts.manrope(
            fontWeight: FontWeight.w800,
            fontSize: 20,
            color: AppColors.onSurface,
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: AppColors.outline),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onSelected: (val) {
              if (val == 'rename') _showRenameSheet(context, ref);
              if (val == 'team') context.push('/home/accounts/${account.id}/team', extra: account);
              if (val == 'delete') _confirmDelete(context, ref);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'rename',
                child: Row(children: [
                  const Icon(Icons.edit_outlined, size: 18),
                  const SizedBox(width: 10),
                  Text('Rename', style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
                ]),
              ),
              PopupMenuItem(
                value: 'team',
                child: Row(children: [
                  const Icon(Icons.group_outlined, size: 18),
                  const SizedBox(width: 10),
                  Text('Manage Team', style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
                ]),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(children: [
                  const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.error),
                  const SizedBox(width: 10),
                  Text('Delete Account',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w500, color: AppColors.error)),
                ]),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          ref.invalidate(accountCardsProvider(account.id));
          await Future.delayed(const Duration(milliseconds: 400));
        },
        child: cardsAsync.when(
          data: (cards) {
            final activeCount = cards.where((c) => c.isActive).length;
            final totalSpend = txAsync.valueOrNull?.fold<double>(0, (s, t) => s + t.amount) ?? 0;

            return ListView(
              padding: EdgeInsets.fromLTRB(
                16, 16, 16, MediaQuery.of(context).padding.bottom + 32),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            'Cards',
                            style: GoogleFonts.manrope(
                              fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.onSurface,
                            ),
                          ),
                        ),
                        Text(
                          'Cards for this client',
                          style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurfaceVariant),
                        ),
                      ],
                    ),
                    if (account.ownerUserId == ref.read(firebaseAuthProvider).currentUser?.uid)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primaryContainer,
                          foregroundColor: AppColors.onPrimaryContainer,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                        ),
                        onPressed: () {
                          Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
                            builder: (_) => TeamMembersScreen(account: account),
                          ));
                        },
                        icon: const Icon(Icons.group_add_rounded, size: 18),
                        label: Text(
                          'Manage Team',
                          style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Card list ──────────────────────────────────────────────
                if (cards.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    child: Center(
                      child: Text(
                        'No cards yet. Create one below.',
                        style: GoogleFonts.inter(color: AppColors.onSurfaceVariant, fontSize: 14),
                      ),
                    ),
                  )
                else
                  ...cards.asMap().entries.map((e) {
                    final card = e.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _CardListTile(card: card)
                          .animate(delay: (e.key * 40).ms)
                          .fadeIn()
                          .slideY(begin: 0.04, end: 0),
                    );
                  }),

                const SizedBox(height: 16),

                // ── Create New Card button ─────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: () => context.push('/home/cards/create', extra: account.id),
                    icon: const Icon(Icons.add_rounded),
                    label: Text(
                      '+ Create New Card',
                      style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // ── Summary ────────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Summary',
                        style: GoogleFonts.manrope(
                          fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _SummaryItem(
                              label: 'Total Spend',
                              value: '₦${_fmt(totalSpend)}',
                              icon: Icons.trending_up_rounded,
                              iconColor: const Color(0xFF6366F1),
                            ),
                          ),
                          Container(width: 1, height: 40, color: AppColors.outlineVariant.withValues(alpha: 0.5)),
                          Expanded(
                            child: _SummaryItem(
                              label: 'Active Cards',
                              value: '$activeCount',
                              icon: Icons.credit_card_rounded,
                              iconColor: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
          error: (e, _) => const Center(child: Text('Failed to load cards.')),
        ),
      ),
    );
  }

  String _fmt(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toStringAsFixed(0);
  }

  void _showRenameSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RenameSheet(account: account),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.delete_forever_rounded, color: AppColors.error, size: 36),
        title: Text('Delete Account', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
        content: Text(
          'Permanently delete "${account.name}" and all its cards?',
          style: GoogleFonts.inter(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await ref
                  .read(accountNotifierProvider.notifier)
                  .deleteAccount(accountId: account.id, confirmDelete: true);
              if (context.mounted) {
                GkToast.show(context,
                    message: success ? 'Account deleted' : 'Failed to delete',
                    type: success ? ToastType.success : ToastType.error);
                if (success) context.pop();
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ── Card list tile (wireframe ②) ──────────────────────────────────────────────
class _CardListTile extends StatelessWidget {
  final VirtualCardModel card;
  const _CardListTile({required this.card});

  @override
  Widget build(BuildContext context) {
    final statusColor = card.isActive
        ? const Color(0xFF2E7A4A)
        : card.isBlocked
            ? AppColors.error
            : AppColors.onSurfaceVariant;
    final statusBg = card.isActive
        ? const Color(0xFFE2F4E8)
        : card.isBlocked
            ? AppColors.error.withValues(alpha: 0.1)
            : AppColors.surfaceContainerHigh;
    final statusLabel = card.isActive ? 'Active' : card.isBlocked ? 'Blocked' : card.status;

    return InkWell(
      onTap: () => context.push('/home/cards/${card.id}'),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            // Card icon square
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.credit_card_rounded, color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.name,
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '•••• ${card.last4 ?? '****'}',
                    style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            // Status badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                statusLabel[0].toUpperCase() + statusLabel.substring(1),
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: statusColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Summary item ──────────────────────────────────────────────────────────────
class _SummaryItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;

  const _SummaryItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 6),
              Text(label, style: GoogleFonts.inter(fontSize: 12, color: AppColors.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.manrope(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.onSurface),
          ),
        ],
      ),
    );
  }
}

// ── Rename Sheet ──────────────────────────────────────────────────────────────
class _RenameSheet extends ConsumerStatefulWidget {
  final AccountModel account;
  const _RenameSheet({required this.account});

  @override
  ConsumerState<_RenameSheet> createState() => _RenameSheetState();
}

class _RenameSheetState extends ConsumerState<_RenameSheet> {
  late final TextEditingController _ctrl;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.account.name);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
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
            Text('Rename Account',
                style: GoogleFonts.manrope(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.onSurface)),
            const SizedBox(height: 20),
            TextField(
              controller: _ctrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Account Name',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _loading
                    ? null
                    : () async {
                        if (_ctrl.text.trim().isEmpty) return;
                        setState(() => _loading = true);
                        final ok = await ref
                            .read(accountNotifierProvider.notifier)
                            .renameAccount(accountId: widget.account.id, newName: _ctrl.text.trim());
                        setState(() => _loading = false);
                        if (!context.mounted) return;
                        GkToast.show(context,
                            message: ok ? 'Renamed successfully' : 'Failed to rename',
                            type: ok ? ToastType.success : ToastType.error);
                        if (ok) Navigator.pop(context);
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _loading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text('Save', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
