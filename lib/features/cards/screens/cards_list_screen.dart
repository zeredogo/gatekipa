// lib/features/cards/screens/cards_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gatekeepeer/core/constants/routes.dart';
import 'package:gatekeepeer/core/theme/app_colors.dart';
import 'package:gatekeepeer/core/widgets/gk_virtual_card.dart';
import 'package:gatekeepeer/core/widgets/gk_card_list_tile.dart';
import 'package:gatekeepeer/core/widgets/shimmer_loader.dart';
import 'package:gatekeepeer/features/cards/models/virtual_card_model.dart';
import 'package:gatekeepeer/features/cards/providers/card_provider.dart';
import 'package:gatekeepeer/features/search/providers/search_provider.dart';
import 'package:gatekeepeer/features/search/screens/search_screen.dart';
import 'package:gatekeepeer/core/theme/app_spacing.dart';
import 'package:gatekeepeer/features/auth/providers/auth_provider.dart';
import 'package:gatekeepeer/core/widgets/gk_button.dart';

class CardsListScreen extends ConsumerStatefulWidget {
  const CardsListScreen({super.key});
  @override
  ConsumerState<CardsListScreen> createState() => _CardsListScreenState();
}

class _CardsListScreenState extends ConsumerState<CardsListScreen> {
  String _filter = 'all';
  VirtualCardModel? _selectedCard;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      ref.read(searchQueryProvider.notifier).state = _searchCtrl.text;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cardsAsync = ref.watch(cardsProvider);
    final isSearching = _searchCtrl.text.trim().isNotEmpty;
    final profileState = ref.watch(userProfileProvider);
    final isKycPending = profileState.valueOrNull?.kycStatus == 'pending';

    if (isKycPending) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          title: Text('Cards', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, fontSize: 22, color: AppColors.onSurface)),
          backgroundColor: AppColors.surface,
          scrolledUnderElevation: 0,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.shield_outlined, color: AppColors.primary, size: 36),
                ),
                const SizedBox(height: 24),
                Text(
                  'KYC Verification Required',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                Text(
                  'To ensure platform security, you must complete your identity verification before you can view or issue cards.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                GkButton(
                  label: 'Complete KYC',
                  icon: Icons.verified_user,
                  onPressed: () => context.push(Routes.kyc),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        scrolledUnderElevation: 0,
        titleSpacing: 24,
        title: Text(
          'My Cards',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800,
            fontSize: 22,
            color: AppColors.onSurface,),
        ),
        actions: [
          // Card count badge
          cardsAsync.when(
            data: (cards) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color:
                      AppColors.primaryContainer.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  '${cards.length} card${cards.length != 1 ? 's' : ''}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,),
                ),
              ),
            ),
            loading: () => const SizedBox(),
            error: (_, __) => const SizedBox(),
          ),
          // Add card button
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Material(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: () => context.push(Routes.cardCreation),
                borderRadius: BorderRadius.circular(12),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child:
                      Icon(Icons.add_rounded, color: Colors.white, size: 22),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Search bar ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
            child: TextField(
              controller: _searchCtrl,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 15, color: AppColors.onSurface),
              decoration: InputDecoration(
                hintText: 'Search cards or merchants...',
                hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.outline, fontSize: 15),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: AppColors.outline, size: 20),
                suffixIcon: isSearching
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded,
                            color: AppColors.outline, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          FocusScope.of(context).unfocus();
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppColors.surfaceVariant.withValues(alpha: 0.5),
                contentPadding: const EdgeInsets.symmetric(
                    vertical: 0, horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                      color:
                          AppColors.outlineVariant.withValues(alpha: 0.5)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                      color: AppColors.primary, width: 1.5),
                ),
              ),
            ),
          ),

          // ── Filter chips (hidden when searching) ──────────────────────
          if (!isSearching)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ['all', 'active', 'blocked', 'expired']
                      .map((f) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(
                                f[0].toUpperCase() + f.substring(1),
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13,
                                  fontWeight: FontWeight.w600,),
                              ),
                              selected: _filter == f,
                              onSelected: (_) =>
                                  setState(() => _filter = f),
                              selectedColor: AppColors.primary
                                  .withValues(alpha: 0.1),
                              checkmarkColor: AppColors.primary,
                              side: BorderSide(
                                color: _filter == f
                                    ? AppColors.primary
                                    : AppColors.outlineVariant,
                              ),
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(100)),
                            ),
                          ))
                      .toList(),
                ),
              ),
            ),

          // ── Cards list or Search ──────────────────────────────────────
          Expanded(
            child: isSearching
                ? GlobalSearchView(onClear: () {
                    _searchCtrl.clear();
                    FocusScope.of(context).unfocus();
                  })
                : RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: () async {
                      ref.invalidate(cardsProvider);
                      await Future.delayed(
                          const Duration(milliseconds: 500));
                    },
                    child: cardsAsync.when(
                      data: (cards) {
                        final filtered = _filter == 'all'
                            ? cards
                            : cards
                                .where((c) => c.status == _filter)
                                .toList();

                        if (filtered.isEmpty) {
                          return _EmptyState(filter: _filter);
                        }

                        return ListView.builder(
                          padding: const EdgeInsets.fromLTRB(
                              24, 4, 24, 140),
                          itemCount: filtered.length,
                          itemBuilder: (ctx, i) {
                            final card = filtered[i];
                            final isSelected =
                                _selectedCard?.id == card.id;
                            return Padding(
                              padding:
                                  const EdgeInsets.only(bottom: 12),
                              child: AnimatedContainer(
                                duration:
                                    const Duration(milliseconds: 200),
                                decoration: BoxDecoration(
                                  borderRadius:
                                      BorderRadius.circular(18),
                                  border: isSelected
                                      ? Border.all(
                                          color: AppColors.primary,
                                          width: 2)
                                      : null,
                                  boxShadow: isSelected
                                      ? [
                                          BoxShadow(
                                            color: AppColors.primary
                                                .withValues(alpha: 0.12),
                                            blurRadius: 16,
                                            offset: const Offset(0, 4),
                                          )
                                        ]
                                      : null,
                                ),
                                child: GkCardListTile(
                                  card: card,
                                  onTap: () {
                                    setState(() {
                                      _selectedCard =
                                          isSelected ? null : card;
                                    });
                                  },
                                ),
                              ),
                            ).animate(delay: (i * 45).ms).fadeIn().slideY(
                                begin: 0.06, end: 0);
                          },
                        );
                      },
                      loading: () => ListView.builder(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 140),
                        itemCount: 3,
                        itemBuilder: (_, __) => const Padding(
                          padding: EdgeInsets.only(bottom: 14),
                          child: ShimmerCard(height: 82),
                        ),
                      ),
                      error: (_, __) => Center(
                        child: Text(
                          'Failed to load cards.\nPull to refresh.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.outline, fontSize: 14),
                        ),
                      ),
                    ),
                  ),
          ),

          // ── Selected card preview panel ───────────────────────────────
          if (_selectedCard != null)
            Material(
              elevation: 20,
              color: AppColors.surface,
              shadowColor: Colors.black.withValues(alpha: 0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  24,
                  20,
                  24,
                  // Ensure the panel clears the system bottom nav bar
                  24 + MediaQuery.of(context).padding.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Drag handle
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.outlineVariant,
                          borderRadius: BorderRadius.circular(100),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Quick Preview',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800,
                              fontSize: 17,
                              color: AppColors.onSurface),
                        ),
                        Row(
                          children: [
                            TextButton(
                              onPressed: () => context.push(
                                  '/home/cards/${_selectedCard!.id}'),
                              child: const Text(
                                'View Details',
                                style: TextStyle(height: 1.2, fontFamily: 'Manrope', color: AppColors.primary,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded,
                                  color: AppColors.outline),
                              onPressed: () => setState(
                                  () => _selectedCard = null),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      height: 190,
                      child: Center(
                        child: GkVirtualCard(
                          card: _selectedCard!,
                          onTap: () => context.push(
                              '/home/cards/${_selectedCard!.id}'),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                  ],
                ),
              ).animate().slideY(begin: 1.0, end: 0).fadeIn(
                  duration: 250.ms, curve: Curves.easeOutCubic),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String filter;
  const _EmptyState({required this.filter});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(Icons.credit_card_off_rounded,
                    size: 36, color: AppColors.outline),
              ),
              const SizedBox(height: 20),
              Text(
                filter == 'all' ? 'No cards yet' : 'No $filter cards',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                filter == 'all'
                    ? 'Create your first virtual card to control\nsubscription payments'
                    : 'Try changing the filter above',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceVariant,
                    fontSize: 14,
                    height: 1.5),
                textAlign: TextAlign.center,
              ),
              if (filter == 'all') ...[
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  onPressed: () => context.push(Routes.cardCreation),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Create First Card'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(100)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
