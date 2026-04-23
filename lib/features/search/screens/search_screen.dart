// lib/features/search/screens/search_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gatekeepeer/core/theme/app_colors.dart';
import 'package:gatekeepeer/features/accounts/providers/account_provider.dart';
import 'package:gatekeepeer/features/search/providers/search_provider.dart';
import 'package:gatekeepeer/core/theme/app_spacing.dart';

class GlobalSearchView extends ConsumerWidget {
  final VoidCallback onClear;
  const GlobalSearchView({super.key, required this.onClear});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(searchQueryProvider);
    final isSearching = query.isNotEmpty;
    final resultsAsync = ref.watch(searchResultsProvider);

    return isSearching
        ? resultsAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator(color: AppColors.primary)),
            error: (_, __) => Center(
              child: Text('Search failed', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.outline)),
            ),
            data: (results) {
              final cards = results.cards;
              final accounts = results.accounts;

              if (cards.isEmpty && accounts.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.search_off_rounded, size: 52, color: AppColors.outline),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'No results for "$query"',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: AppColors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Try a different card name or account name.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13, color: AppColors.outline),
                      ),
                    ],
                  ).animate().fadeIn(duration: 300.ms),
                );
              }

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                children: [
                  // ── Cards section ─────────────────────────────
                  if (cards.isNotEmpty) ...[
                    const _SectionHeader('Cards'),
                    const SizedBox(height: AppSpacing.xs),
                    ...cards.asMap().entries.map((e) {
                      final card = e.value;
                      final accountsAsyncVal = ref.watch(accountsStreamProvider).valueOrNull ?? [];
                      final accountName = accountsAsyncVal
                              .where((a) => a.id == card.accountId)
                              .firstOrNull
                              ?.name ??
                          'Unknown Account';

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _SearchCardTile(
                          cardName: card.name,
                          accountName: accountName,
                          isBlocked: card.isBlocked,
                          onTap: () {
                            ref
                                .read(activeAccountIdProvider.notifier)
                                .setActiveAccount(card.accountId);
                            onClear();
                            context.push('/home/cards/${card.id}');
                          },
                        ).animate(delay: (e.key * 40).ms).fadeIn().slideX(begin: 0.04, end: 0),
                      );
                    }),
                    const SizedBox(height: AppSpacing.md),
                  ],

                  // ── Accounts section ──────────────────────────
                  if (accounts.isNotEmpty) ...[
                    const _SectionHeader('Accounts'),
                    const SizedBox(height: AppSpacing.xs),
                    ...accounts.asMap().entries.map((e) {
                      final account = e.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _SearchAccountTile(
                          name: account.name,
                          type: account.type,
                          onTap: () {
                            ref
                                .read(activeAccountIdProvider.notifier)
                                .setActiveAccount(account.id);
                            onClear();
                            context.push(
                              '/home/accounts/${account.id}',
                              extra: account,
                            );
                          },
                        ).animate(delay: ((cards.length + e.key) * 40).ms).fadeIn().slideX(begin: 0.04, end: 0),
                      );
                    }),
                  ],
                ],
              );
            },
          )
        // Empty state when no query typed yet
        : Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.manage_search_rounded, size: 60, color: AppColors.outline),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Search your cards & accounts',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.onSurfaceVariant),
                ),
                const SizedBox(height: 6),
                Text(
                  'Type a card name, account name, or keyword.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13, color: AppColors.outline),
                  textAlign: TextAlign.center,
                ),
              ],
            ).animate().fadeIn(duration: 400.ms),
          );
  }
}

// ── Section header ────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) => Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.onSurface),
      );
}

// ── Card search result tile ───────────────────────────────────────────────────
class _SearchCardTile extends StatelessWidget {
  final String cardName;
  final String accountName;
  final bool isBlocked;
  final VoidCallback onTap;

  const _SearchCardTile({
    required this.cardName,
    required this.accountName,
    required this.isBlocked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.credit_card_rounded, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(cardName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.onSurface)),
                  const SizedBox(height: 2),
                  Text(accountName,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12, color: AppColors.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (isBlocked)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('Blocked',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.error)),
              )
            else
              const Icon(Icons.chevron_right_rounded, color: AppColors.outline, size: 20),
          ],
        ),
      ),
    );
  }
}

// ── Account search result tile ────────────────────────────────────────────────
class _SearchAccountTile extends StatelessWidget {
  final String name;
  final String type;
  final VoidCallback onTap;

  const _SearchAccountTile({required this.name, required this.type, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                type == 'business' ? Icons.business_rounded : Icons.person_rounded,
                color: const Color(0xFF6366F1),
                size: 20,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.onSurface)),
                  const SizedBox(height: 2),
                  Text(type[0].toUpperCase() + type.substring(1),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12, color: AppColors.onSurfaceVariant)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.outline, size: 20),
          ],
        ),
      ),
    );
  }
}
