// lib/features/search/widgets/search_bar_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/app_colors.dart';
import '../../accounts/providers/account_provider.dart';
import '../providers/search_provider.dart';

class DashboardSearchBarWidget extends ConsumerWidget {
  const DashboardSearchBarWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(searchQueryProvider);
    final isSearching = query.isNotEmpty;
    final searchResultsAsync = ref.watch(searchResultsProvider);

    return Column(
      children: [
        TextField(
          onChanged: (val) => ref.read(searchQueryProvider.notifier).state = val,
          style: GoogleFonts.inter(fontSize: 15, color: AppColors.onSurface, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: 'Search cards or accounts...',
            hintStyle: GoogleFonts.inter(color: AppColors.outline, fontSize: 14),
            prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primary, size: 20)
                .animate(onPlay: (controller) => controller.repeat(reverse: true))
                .shimmer(duration: 2.seconds, blendMode: BlendMode.srcATop),
            suffixIcon: isSearching
                ? IconButton(
                    icon: const Icon(Icons.close_rounded, color: AppColors.outline, size: 18),
                    onPressed: () {
                      ref.read(searchQueryProvider.notifier).state = '';
                      FocusScope.of(context).unfocus();
                    },
                  )
                : null,
            filled: true,
            fillColor: AppColors.surfaceContainerLowest,
            contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 20),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide(color: AppColors.outlineVariant.withValues(alpha: 0.6), width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide(color: AppColors.outlineVariant.withValues(alpha: 0.6), width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
          ),
        ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.2, end: 0, curve: Curves.easeOutQuad),
        if (isSearching)
          Container(
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.5)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: searchResultsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2)),
              ),
              error: (_, __) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Search failed', style: GoogleFonts.inter(color: AppColors.onSurfaceVariant)),
              ),
              data: (results) {
                final allCards = results.cards;
                final allAccounts = results.accounts;
                final total = allCards.length + allAccounts.length;

                if (total == 0) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Column(
                        children: [
                          const Icon(Icons.search_off_rounded, color: AppColors.outline, size: 40)
                              .animate()
                              .scale(begin: const Offset(0.8, 0.8), curve: Curves.elasticOut),
                          const SizedBox(height: 12),
                          Text(
                            'No results found.',
                            style: GoogleFonts.inter(color: AppColors.onSurfaceVariant, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    // Cards results
                    ...allCards.asMap().entries.map((e) {
                      final card = e.value;
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.credit_card_rounded, color: AppColors.primary, size: 20),
                        ),
                        title: Text(card.name,
                            style: GoogleFonts.manrope(
                                color: AppColors.onSurface, fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: Text(card.isTrial ? 'Trial Card' : 'Virtual Card',
                            style: GoogleFonts.inter(color: AppColors.onSurfaceVariant, fontSize: 12)),
                        trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.outline, size: 20),
                        onTap: () {
                          ref.read(activeAccountIdProvider.notifier).setActiveAccount(card.accountId);
                          ref.read(searchQueryProvider.notifier).state = '';
                          FocusScope.of(context).unfocus();
                          context.push('/home/cards/${card.id}');
                        },
                      ).animate(delay: (e.key * 50).ms).fadeIn().slideX(begin: 0.05, end: 0);
                    }),
                    // Accounts results
                    ...allAccounts.asMap().entries.map((e) {
                      final account = e.value;
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.account_balance_rounded,
                              color: Color(0xFF6366F1), size: 20),
                        ),
                        title: Text(account.name,
                            style: GoogleFonts.manrope(
                                color: AppColors.onSurface, fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: Text(account.type[0].toUpperCase() + account.type.substring(1),
                            style: GoogleFonts.inter(color: AppColors.onSurfaceVariant, fontSize: 12)),
                        trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.outline, size: 20),
                        onTap: () {
                          ref.read(activeAccountIdProvider.notifier).setActiveAccount(account.id);
                          ref.read(searchQueryProvider.notifier).state = '';
                          FocusScope.of(context).unfocus();
                        },
                      ).animate(delay: (e.key * 50).ms).fadeIn().slideX(begin: 0.05, end: 0);
                    }),
                  ],
                );
              },
            ),
          ).animate().fadeIn(duration: 200.ms).slideY(begin: -0.05, end: 0),
      ],
    );
  }
}
