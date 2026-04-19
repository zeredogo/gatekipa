// lib/features/accounts/screens/accounts_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/gk_toast.dart';
import '../../cards/providers/card_provider.dart';
import '../models/account_model.dart';
import '../providers/account_provider.dart';
import '../../auth/providers/auth_provider.dart';

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(accountsStreamProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        scrolledUnderElevation: 0,
        backgroundColor: AppColors.surface,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Accounts',
              style: GoogleFonts.manrope(
                fontWeight: FontWeight.w800,
                fontSize: 22,
                color: AppColors.onSurface,
              ),
            ),
            Text(
              'Your client profiles',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          ref.invalidate(accountsStreamProvider);
          await Future.delayed(const Duration(milliseconds: 500));
        },
        child: accountsAsync.when(
          data: (accounts) {
            if (accounts.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: 120),
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.account_balance_rounded, size: 64, color: AppColors.outline),
                        const SizedBox(height: 16),
                        Text(
                          'No accounts yet',
                          style: GoogleFonts.manrope(
                            fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap + Create Client Profile below to get started',
                          style: GoogleFonts.inter(color: AppColors.outline, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 160),
              itemCount: accounts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (ctx, i) {
                final account = accounts[i];
                return _AccountTile(
                  account: account,
                  onTap: () {
                    ref.read(activeAccountIdProvider.notifier).setActiveAccount(account.id);
                    context.push('/home/accounts/${account.id}', extra: account);
                  },
                  onRename: () => _showRenameSheet(context, ref, account),
                  onManageTeam: () {
                    final user = ref.read(userProfileProvider).valueOrNull;
                    if (user != null && user.planTier != 'business') {
                      GkToast.show(context, message: '🏢 Business Plan Required: Upgrade your plan to manage teams.', type: ToastType.warning, duration: const Duration(seconds: 4));
                      return;
                    }
                    context.push('/home/accounts/${account.id}/team', extra: account);
                  },
                  onDelete: () => _confirmDelete(context, ref, account),
                ).animate(delay: (i * 40).ms).fadeIn().slideY(begin: 0.05, end: 0);
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
          error: (e, _) => const Center(child: Text('Failed to load accounts.')),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 120),
        child: SizedBox(
          width: double.infinity,
          height: 54,
          child: FilledButton.icon(
            onPressed: () => _showCreateAccountSheet(context, ref),
            icon: const Icon(Icons.add_rounded),
            label: const Text(
              'Create Client Profile',
              style: TextStyle(height: 1.2, fontFamily: 'Manrope', fontWeight: FontWeight.w700, fontSize: 16),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ),
    );
  }

  void _showCreateAccountSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateAccountSheet(),
    );
  }

  void _showRenameSheet(BuildContext context, WidgetRef ref, AccountModel account) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RenameAccountSheet(account: account),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, AccountModel account) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.delete_forever_rounded, color: AppColors.error, size: 36),
        title: Text('Delete Account', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
        content: Text(
          'This will permanently delete "${account.name}" and all associated cards. This cannot be undone.',
          style: GoogleFonts.inter(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await ref.read(accountNotifierProvider.notifier).deleteAccount(accountId: account.id);
              if (context.mounted) {
                if (success) {
                  GkToast.show(context, message: 'Account deleted', type: ToastType.success);
                } else {
                  final forceConfirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx2) => AlertDialog(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 36),
                      title: Text('Active Cards Found', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
                      content: Text(
                        'This account has active virtual cards. Deleting will also block and remove all cards. Continue?',
                        style: GoogleFonts.inter(),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx2, false), child: const Text('Cancel')),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                          onPressed: () => Navigator.pop(ctx2, true),
                          child: const Text('Force Delete'),
                        ),
                      ],
                    ),
                  );
                  if (forceConfirmed == true && context.mounted) {
                    final forceSuccess = await ref.read(accountNotifierProvider.notifier)
                        .deleteAccount(accountId: account.id, confirmDelete: true);
                    if (context.mounted) {
                      GkToast.show(context,
                          message: forceSuccess ? 'Account and all cards deleted' : 'Failed to delete account',
                          type: forceSuccess ? ToastType.success : ToastType.error);
                    }
                  }
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ── Account Tile (wireframe ①) ─────────────────────────────────────────────────
class _AccountTile extends ConsumerWidget {
  final AccountModel account;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onManageTeam;
  final VoidCallback onDelete;

  const _AccountTile({
    required this.account,
    required this.onTap,
    required this.onRename,
    required this.onManageTeam,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardCountAsync = ref.watch(cardCountProvider(account.id));

    return InkWell(
      onTap: onTap,
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
            // Avatar with first letter
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                account.name.isNotEmpty ? account.name[0].toUpperCase() : 'A',
                style: GoogleFonts.manrope(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(width: 14),
            // Account name + card count
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.name,
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: AppColors.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  cardCountAsync.when(
                    data: (count) => Text(
                      '$count card${count == 1 ? '' : 's'}',
                      style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurfaceVariant),
                    ),
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
            // Three-dot menu — exactly: Rename / Manage Team / Delete Account
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, color: AppColors.outline, size: 22),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              onSelected: (val) {
                if (val == 'rename') onRename();
                if (val == 'team') onManageTeam();
                if (val == 'delete') onDelete();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'rename',
                  child: Row(children: [
                    const Icon(Icons.edit_outlined, size: 18, color: AppColors.onSurface),
                    const SizedBox(width: 10),
                    Text('Rename', style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
                  ]),
                ),
                PopupMenuItem(
                  value: 'team',
                  child: Row(children: [
                    const Icon(Icons.group_outlined, size: 18, color: AppColors.onSurface),
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
          ],
        ),
      ),
    );
  }
}

// ── Create Account Sheet ────────────────────────────────────────────────────────
class _CreateAccountSheet extends ConsumerStatefulWidget {
  @override
  ConsumerState<_CreateAccountSheet> createState() => _CreateAccountSheetState();
}

class _CreateAccountSheetState extends ConsumerState<_CreateAccountSheet> {
  final _nameCtrl = TextEditingController();
  String _type = 'personal';
  bool _loading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _loading = true);
    final id = await ref.read(accountNotifierProvider.notifier).createAccount(
          name: _nameCtrl.text.trim(),
          type: _type,
        );
    setState(() => _loading = false);
    if (mounted) {
      if (id != null) {
        GkToast.show(context, message: 'Account created!', type: ToastType.success);
        Navigator.pop(context);
      } else {
        final e = ref.read(accountNotifierProvider).error; GkToast.show(context, message: 'Failed: $e', type: ToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(28),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AppColors.outlineVariant, borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text('Create Account',
                  style: GoogleFonts.manrope(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.onSurface)),
              const SizedBox(height: 20),
              TextField(
                controller: _nameCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Account Name',
                  hintText: 'e.g. Personal, Client A',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: ['personal', 'business'].map((t) {
                  final selected = _type == t;
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: t == 'personal' ? 8 : 0),
                      child: GestureDetector(
                        onTap: () => setState(() => _type = t),
                        child: AnimatedContainer(
                          duration: 200.ms,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: selected ? AppColors.primary.withValues(alpha: 0.1) : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: selected ? AppColors.primary : AppColors.outlineVariant),
                          ),
                          alignment: Alignment.center,
                          child: Text(t == 'personal' ? 'Individual' : 'Business',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                color: selected ? AppColors.primary : AppColors.onSurface,
                              )),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _loading ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _loading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Create Account', style: TextStyle(height: 1.2, fontFamily: 'Manrope', fontWeight: FontWeight.w700, fontSize: 16)),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Rename Account Sheet ────────────────────────────────────────────────────────
class _RenameAccountSheet extends ConsumerStatefulWidget {
  final AccountModel account;
  const _RenameAccountSheet({required this.account});

  @override
  ConsumerState<_RenameAccountSheet> createState() => _RenameAccountSheetState();
}

class _RenameAccountSheetState extends ConsumerState<_RenameAccountSheet> {
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

  Future<void> _submit() async {
    if (_ctrl.text.trim().isEmpty) return;
    setState(() => _loading = true);
    final success = await ref.read(accountNotifierProvider.notifier).renameAccount(
          accountId: widget.account.id,
          newName: _ctrl.text.trim(),
        );
    setState(() => _loading = false);
    if (mounted) {
      GkToast.show(context,
          message: success ? 'Account renamed' : 'Failed to rename',
          type: success ? ToastType.success : ToastType.error);
      if (success) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(28),
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
                onPressed: _loading ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _loading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Save', style: TextStyle(height: 1.2, fontFamily: 'Manrope', fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
