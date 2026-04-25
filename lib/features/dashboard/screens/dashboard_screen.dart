// lib/features/dashboard/screens/dashboard_screen.dart
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:gatekipa/core/constants/routes.dart';
import 'package:gatekipa/core/theme/app_colors.dart';
import 'package:gatekipa/core/utils/currency_formatter.dart';
import 'package:gatekipa/core/utils/date_formatter.dart';
import 'package:gatekipa/core/widgets/gk_toast.dart';

import 'package:gatekipa/core/widgets/shimmer_loader.dart';
import 'package:gatekipa/features/accounts/providers/account_provider.dart';
import 'package:gatekipa/features/accounts/models/account_model.dart';
import 'package:gatekipa/features/auth/providers/auth_provider.dart';
import 'package:gatekipa/features/cards/models/virtual_card_model.dart';
import 'package:gatekipa/features/cards/providers/card_provider.dart';
import 'package:gatekipa/features/search/widgets/search_bar_widget.dart';
import 'package:gatekipa/features/wallet/models/wallet_model.dart';
import 'package:gatekipa/features/wallet/providers/wallet_provider.dart';
import 'package:gatekipa/features/notifications/providers/notification_provider.dart';
import 'package:gatekipa/core/widgets/gk_card_list_tile.dart';
import 'package:gatekipa/core/theme/app_spacing.dart';
import 'package:gatekipa/core/providers/system_state_provider.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with WidgetsBindingObserver {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Invalidate wallet + cards on every foreground resume so the UI always
  /// reflects authoritative Firestore state, not a stale in-memory snapshot.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(walletProvider);
      ref.invalidate(cardsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(userProfileProvider);
    final walletAsync = ref.watch(walletProvider);
    final cardsAsync = ref.watch(cardsProvider);
    final txAsync = ref.watch(transactionsProvider);
    final unreadCount = ref.watch(unreadNotifCountProvider);
    final sysState = ref.watch(systemStateProvider).valueOrNull ?? SystemState.normal;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          ref.invalidate(walletProvider);
          ref.invalidate(cardsProvider);
          ref.invalidate(transactionsProvider);
          ref.invalidate(userProfileProvider);
          ref.invalidate(unreadNotifCountProvider);
          await Future.delayed(const Duration(milliseconds: 800));
        },
        child: CustomScrollView(
          slivers: [
            // App bar
            SliverAppBar(
              backgroundColor: AppColors.surface,
              floating: true,
              pinned: false,
              leading: GestureDetector(
                onTap: () => context.push(Routes.profile),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: userAsync.when(
                        data: (user) => Text(
                          user?.displayName?.isNotEmpty == true
                              ? user!.displayName![0].toUpperCase()
                              : 'G',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,),
                        ),
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const Icon(Icons.person_rounded,
                            color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ),
              ),
              title: userAsync.when(
                data: (user) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _AccountSelectorWidget(),
                    if (user?.displayName != null)
                      Text(
                        'Hello, ${user!.displayName!.split(' ').first} 👋',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12,
                          color: AppColors.onSurfaceVariant,
                          fontWeight: FontWeight.w500,),
                      ),
                  ],
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
              actions: [
                // Notification bell
                Stack(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.notifications_outlined,
                          color: AppColors.onSurface),
                      onPressed: () => context.push(Routes.notifications),
                    ),
                    if (unreadCount > 0)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: const BoxDecoration(
                            color: AppColors.error,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              unreadCount > 9 ? '9+' : '$unreadCount',
                              style: const TextStyle(height: 1.2, fontFamily: 'Manrope', color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),

            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── System Mode Banner (hidden in NORMAL mode) ─────────────
                  if (!sysState.isOperational)
                    _SystemModeBanner(state: sysState),

                  // ── KYC Action Banner ──
                  if (userAsync.valueOrNull != null && userAsync.valueOrNull!.kycStatus != 'verified')
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, AppSpacing.lg),
                      child: InkWell(
                        onTap: () => context.push(Routes.kyc),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.primaryContainer.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.shield_outlined, color: AppColors.primary, size: 24),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Action Required: Verify Identity', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: AppColors.primary)),
                                    const SizedBox(height: 4),
                                    Text('Complete KYC to unlock card creation and full access.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.onSurfaceVariant)),
                                  ],
                                ),
                              ),
                              const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppColors.primary),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // Balance header
                  _BalanceSection(
                    walletAsync: walletAsync,
                    cardsAsync: cardsAsync,
                  ),
                  const SizedBox(height: AppSpacing.xxl),

                  // Global Fuzzy Search
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: DashboardSearchBarWidget(),
                  ),
                  const SizedBox(height: AppSpacing.xxl),

                  // Cards carousel
                  _SectionHeader(
                    title: 'My Cards',
                    actionLabel: 'See all',
                    onAction: () => context.go(Routes.cards),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _CardsCarousel(cardsAsync: cardsAsync),
                  const SizedBox(height: AppSpacing.xxl),

                  // Kill switch widget
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: _KillSwitchWidget(),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  // Recent Activity
                  _SectionHeader(
                    title: 'Recent Activity',
                    actionLabel: 'View all',
                    onAction: () => context.push(Routes.wallet),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _RecentActivity(txAsync: txAsync),
                  const SizedBox(height: 140),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── System Mode Banner ──────────────────────────────────────────────────────────
// Renders ONLY when system is not NORMAL. Has zero layout cost in steady-state
// because the parent conditionally includes it: `if (!sysState.isOperational)`.
class _SystemModeBanner extends StatelessWidget {
  final SystemState state;
  const _SystemModeBanner({required this.state});

  @override
  Widget build(BuildContext context) {
    final isLockdown = state.isLockedDown;
    final bgColor = isLockdown
        ? const Color(0xFF3B0A0A)
        : const Color(0xFF2D2000);
    final borderColor = isLockdown
        ? const Color(0xFFCF4444)
        : const Color(0xFFD4A017);
    final iconColor = isLockdown
        ? const Color(0xFFFF6B6B)
        : const Color(0xFFFFD166);
    final icon = isLockdown
        ? Icons.lock_rounded
        : Icons.warning_amber_rounded;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 1.2),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isLockdown ? 'System Lockdown' : 'System Degraded',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: iconColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    state.bannerMessage,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: iconColor.withValues(alpha: 0.75),
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  if (state.reason != null && state.reason!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      state.reason!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: iconColor.withValues(alpha: 0.55),
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Balance Section ─────────────────────────────────────────────────────────────
class _BalanceSection extends StatelessWidget {
  final AsyncValue<WalletModel?> walletAsync;
  final AsyncValue<List<VirtualCardModel>> cardsAsync;

  const _BalanceSection({required this.walletAsync, required this.cardsAsync});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, Color(0xFF004D2C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Vault Balance',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white60,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,),
              ),
              GestureDetector(
                onTap: () => context.push(Routes.addFunds),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.add_rounded,
                          color: Colors.white, size: 16),
                      const SizedBox(width: AppSpacing.xxs),
                      Text(
                        'Add Funds',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          walletAsync.when(
            data: (wallet) => Text(
              CurrencyFormatter.format(wallet?.balance ?? 0),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white,
                fontSize: 38,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,),
            ).animate().fadeIn().scale(
                  begin: const Offset(0.95, 0.95),
                  end: const Offset(1, 1),
                ),
            loading: () =>
                const ShimmerLoader(width: 200, height: 40, radius: 8),
            error: (_, __) => Text(
              CurrencyFormatter.format(0),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white,
                fontSize: 38,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Builder(
            builder: (context) {
              double exposure = 0;
              int protectedTxs = 0; 
              int activeCards = 0;
              
              if (cardsAsync.valueOrNull != null) {
                final cards = cardsAsync.valueOrNull!;
                activeCards = cards.length;
                for (final card in cards) {
                  exposure += card.balanceLimit;
                  if (card.isBlocked) protectedTxs += 1;
                }
              }

              return Row(
                children: [
                  Expanded(
                    child: _StatChip(
                      label: 'Detected',
                      value: '$activeCards active',
                      icon: Icons.radar_rounded,
                      onTap: () => _showDetectedDetails(
                          context, cardsAsync.valueOrNull ?? []),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: _StatChip(
                      label: 'Exposure',
                      value: CurrencyFormatter.format(exposure),
                      icon: Icons.account_balance_wallet_rounded,
                      onTap: () => _showExposureDetails(
                          context, cardsAsync.valueOrNull ?? [], exposure),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: _StatChip(
                      label: 'Protected',
                      value: '$protectedTxs blocked',
                      icon: Icons.shield_rounded,
                      onTap: () => _showProtectedDetails(
                          context, cardsAsync.valueOrNull ?? []),
                    ),
                  ),
                ],
              );
            }
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05, end: 0);
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;

  const _StatChip({
    required this.label,
    required this.value,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white60, size: 20),
              const SizedBox(height: AppSpacing.xs),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 16,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  height: 1.2,),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 11,
                  color: Colors.white54,
                  fontWeight: FontWeight.w500,),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showDetectedDetails(BuildContext context, List<VirtualCardModel> cards) {
  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => _DashboardStatSheet(
      title: 'Detected Limits',
      description: 'Gatekeeper has provisioned and is monitoring ${cards.length} virtual cards on this account.',
      icon: Icons.radar_rounded,
      cards: cards,
    ),
  );
}

void _showExposureDetails(BuildContext context, List<VirtualCardModel> cards, double totalExposure) {
  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => _DashboardStatSheet(
      title: 'Monthly Exposure',
      description: 'Your cards represent an active financial exposure of ${CurrencyFormatter.format(totalExposure)}.',
      icon: Icons.account_balance_wallet_rounded,
      cards: cards.where((c) => !c.isBlocked).toList(),
      highlightValue: CurrencyFormatter.format(totalExposure),
    ),
  );
}

void _showProtectedDetails(BuildContext context, List<VirtualCardModel> cards) {
  final blockedCards = cards.where((c) => c.isBlocked).toList();
  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => _DashboardStatSheet(
      title: 'Protection Active',
      description: 'Gatekeeper has actively blocked transactions on ${blockedCards.length} virtual cards, protecting you from unauthorized charges and breaches.',
      icon: Icons.shield_rounded,
      cards: blockedCards,
    ),
  );
}

class _DashboardStatSheet extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final List<VirtualCardModel> cards;
  final String? highlightValue;

  const _DashboardStatSheet({
    required this.title,
    required this.description,
    required this.icon,
    required this.cards,
    this.highlightValue,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      padding: const EdgeInsets.only(top: 24, left: 24, right: 24, bottom: 32),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(28),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(icon, color: AppColors.primary),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                )
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(description,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14, color: AppColors.onSurfaceVariant, height: 1.5)),
            if (highlightValue != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                highlightValue!,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            if (cards.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Column(
                children: cards.map((card) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GkCardListTile(
                    card: card,
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/home/cards/${card.id}');
                    },
                  ),
                )).toList(),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                icon: const Icon(Icons.credit_card_rounded),
                label: const Text('Manage Cards',
                    style: TextStyle(height: 1.2, fontFamily: 'Manrope', fontWeight: FontWeight.w700, fontSize: 16)),
                onPressed: () {
                  Navigator.pop(context);
                  context.go(Routes.cards);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Cards Carousel ──────────────────────────────────────────────────────────────
class _CardsCarousel extends ConsumerWidget {
  final AsyncValue<List<VirtualCardModel>> cardsAsync;
  const _CardsCarousel({required this.cardsAsync});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return cardsAsync.when(
      data: (cards) {
        if (cards.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _EmptyCardsPlaceholder(),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              for (var i = 0; i < cards.length && i < 3; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GkCardListTile(
                    card: cards[i],
                    onTap: () => context.push('/home/cards/${cards[i].id}'),
                  ).animate(delay: (i * 80).ms).fadeIn().slideY(begin: 0.1, end: 0),
                ),
            ],
          ),
        );
      },
      loading: () => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            for (var i = 0; i < 2; i++)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: ShimmerCard(height: 80),
              ),
          ],
        ),
      ),
      error: (_, __) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 24),
        child: Text('Failed to load cards'),
      ),
    );
  }
}


class _EmptyCardsPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.outlineVariant,
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        children: [
          const Icon(Icons.credit_card_off_rounded,
              color: AppColors.outline, size: 40),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'No virtual cards yet',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700,
              color: AppColors.onSurfaceVariant,),
          ),
          const SizedBox(height: 6),
          Text(
            'Create your first card to start controlling payments',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13,
              color: AppColors.outline,),
          ),
        ],
      ),
    );
  }
}

// ── Kill Switch ─────────────────────────────────────────────────────────────────
class _KillSwitchWidget extends ConsumerStatefulWidget {
  @override
  ConsumerState<_KillSwitchWidget> createState() => _KillSwitchWidgetState();
}

class _KillSwitchWidgetState extends ConsumerState<_KillSwitchWidget> {
  final _localAuth = LocalAuthentication();
  bool _activating = false;

  @override
  Widget build(BuildContext context) {
    final cardsAsync = ref.watch(cardsProvider);
    final activeCardCount = cardsAsync.valueOrNull?.where((c) => c.isActive).length ?? 0;

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.errorContainer.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.power_settings_new_rounded,
                color: AppColors.error, size: 26),
          ),
          title: Text(
            'Emergency Kill Switch',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700,
              fontSize: 15,
              color: AppColors.onSurface,),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 3.0),
            child: Text(
              activeCardCount > 0
                  ? '$activeCardCount active card${activeCardCount == 1 ? '' : 's'} — tap to block all'
                  : 'No active cards to block',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12,
                color: activeCardCount > 0 ? AppColors.error : AppColors.onSurfaceVariant,),
            ),
          ),
          iconColor: AppColors.outline,
          collapsedIconColor: AppColors.outline,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    onPressed: (_activating || activeCardCount == 0)
                        ? null
                        : () => _showKillSwitchDialog(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.error,
                      disabledBackgroundColor: AppColors.error.withValues(alpha: 0.4),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _activating
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5),
                          )
                        : Text(
                            activeCardCount > 0
                                ? 'Block All $activeCardCount Cards Now'
                                : 'No Active Cards',
                            style: const TextStyle(height: 1.2, fontFamily: 'Manrope', fontWeight: FontWeight.w800, fontSize: 14)),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      const Icon(Icons.security_rounded,
                          size: 16, color: AppColors.outline),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        'AUTOMATED GUARD RULES',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.outline,
                          letterSpacing: 1.2,),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const _GuardRulesWidget(),
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 200.ms);
  }

  Future<void> _showKillSwitchDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        icon: const Icon(Icons.warning_amber_rounded,
            color: AppColors.error, size: 40),
        title: Text('Activate Kill Switch?',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        content: Text(
          'All your active virtual cards will be blocked immediately. This action cannot be undone automatically.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Block All Cards'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    // Biometric gate
    try {
      final canAuth = await _localAuth.canCheckBiometrics;
      if (canAuth) {
        final authenticated = await _localAuth.authenticate(
          localizedReason: 'Confirm Kill Switch activation',
          options: const AuthenticationOptions(stickyAuth: true),
        );
        if (!authenticated) return;
      }
    } catch (e) {
      if (context.mounted) {
        GkToast.show(
          context,
          message: 'Biometric unavailable. Bypassing for emergency.',
          type: ToastType.warning,
        );
      }
      // Proceed even if biometrics throw an exception
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || !context.mounted) return;

    setState(() => _activating = true);
    final errorStr =
        await ref.read(cardNotifierProvider.notifier).activateKillSwitch(uid);
    if (!context.mounted) return;
    setState(() => _activating = false);
    GkToast.show(
      context,
      message: errorStr == null
          ? 'All cards blocked. Vault secured.'
          : 'Kill switch alert: $errorStr',
      type: errorStr == null ? ToastType.success : ToastType.error,
      title: errorStr == null ? '🛡️ Vault Secured' : 'Action Required',
    );
  }
}

class _GuardRulesWidget extends ConsumerWidget {
  const _GuardRulesWidget();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userProfileProvider);
    final cardsAsync = ref.watch(cardsProvider);
    
    // FIX: Night Lockdown and Geo-Fence are user-level settings (stored on the users doc) that
    // ruleEngine.js applies to ALL cards regardless of type. Gating on "has non-trial card"
    // blocked Sentinel Prime trial users from using these features entirely.
    // Correct gate: user must have at least one card (any type) AND be Sentinel Prime.
    final hasAnyCard = cardsAsync.valueOrNull?.isNotEmpty ?? false;

    return userAsync.when(
      data: (user) {
        if (user == null) return const SizedBox();
        return Column(
          children: [
            _RuleTile(
              icon: Icons.nights_stay_rounded,
              iconColor: Colors.indigo,
              title: 'Night Lockdown',
              sub: 'Block all charges 12 AM – 6 AM (WAT)',
              value: hasAnyCard && user.isSentinelPrime ? user.nightLockdown : false,
              onChanged: (v) async {
                if (!hasAnyCard) {
                  GkToast.show(context,
                      message: '🚀 Create a card first to unlock Night Lockdown.',
                      type: ToastType.warning,
                      duration: const Duration(seconds: 4));
                  return;
                }
                // FIX #1: Use isSentinelPrime — covers premium, business, AND active trial
                if (!user.isSentinelPrime) {
                  GkToast.show(context,
                      message: '🚀 Sentinel Prime Required: Upgrade your plan to unlock Night Lockdown.',
                      type: ToastType.warning,
                      duration: const Duration(seconds: 4));
                  return;
                }
                try {
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(user.uid)
                      .update({'nightLockdown': v});
                } catch (_) {
                  if (context.mounted) {
                    GkToast.show(context,
                        message: 'Failed to update Night Lockdown',
                        type: ToastType.error);
                  }
                }
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            _RuleTile(
              icon: Icons.location_on_rounded,
              iconColor: Colors.teal,
              title: 'Geo-Fence',
              sub: 'Block international charges',
              value: hasAnyCard && user.isSentinelPrime ? user.geoFence : false,
              onChanged: (v) async {
                if (!hasAnyCard) {
                  GkToast.show(context,
                      message: '🚀 Create a card first to unlock geo-fencing protections.',
                      type: ToastType.warning,
                      duration: const Duration(seconds: 4));
                  return;
                }
                // FIX #1: Use isSentinelPrime — covers premium, business, AND active trial
                if (!user.isSentinelPrime) {
                  GkToast.show(context,
                      message: '🚀 Sentinel Prime Required: Upgrade your plan to unlock advanced geo-fencing protections.',
                      type: ToastType.warning,
                      duration: const Duration(seconds: 4));
                  return;
                }
                try {
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(user.uid)
                      .update({'geoFence': v});
                } catch (_) {
                  if (context.mounted) {
                    GkToast.show(context,
                        message: 'Failed to update Geo-Fence',
                        type: ToastType.error);
                  }
                }
              },
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const SizedBox(),
    );
  }
}


class _RuleTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String sub;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _RuleTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.sub,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: iconColor, size: 22)
                .animate(onPlay: (controller) => controller.repeat(reverse: true))
                .shimmer(duration: 3.seconds, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, fontSize: 14)),
                Text(sub,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12, color: AppColors.onSurfaceVariant, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          Switch(
            value: value, 
            thumbIcon: WidgetStateProperty.resolveWith<Icon?>((Set<WidgetState> states) {
              if (states.contains(WidgetState.selected)) {
                return const Icon(Icons.check, color: AppColors.primary);
              }
              return const Icon(Icons.close, color: AppColors.surface);
            }),
            onChanged: onChanged,
          ),
        ],
      ),
    ).animate().fadeIn().slideY(begin: 0.1, end: 0, curve: Curves.easeOut);
  }
}

// ── Recent Activity ─────────────────────────────────────────────────────────────
class _RecentActivity extends StatelessWidget {
  final AsyncValue<List<TransactionModel>> txAsync;
  const _RecentActivity({required this.txAsync});

  @override
  Widget build(BuildContext context) {
    return txAsync.when(
      data: (txs) {
        final recent = txs.take(5).toList();
        if (recent.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Center(
              child: Text(
                'No transactions yet',
                style: TextStyle(height: 1.2, fontFamily: 'Manrope', color: AppColors.outline),
              ),
            ),
          );
        }
        return Column(
          children: recent.asMap().entries.map((e) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              child: _TransactionTile(tx: e.value)
                  .animate(delay: (e.key * 60).ms)
                  .fadeIn()
                  .slideX(begin: 0.05, end: 0),
            );
          }).toList(),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 24),
        child: ShimmerTransactionList(),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final TransactionModel tx;
  const _TransactionTile({required this.tx});

  @override
  Widget build(BuildContext context) {
    final (iconBg, icon, statusColor) = tx.isApproved
        ? (
            AppColors.tertiaryContainer.withValues(alpha: 0.4),
            Icons.check_circle_rounded,
            AppColors.tertiary
          )
        : tx.isBlocked
            ? (
                AppColors.errorContainer.withValues(alpha: 0.4),
                Icons.block_rounded,
                AppColors.error
              )
            : (
                AppColors.secondaryContainer.withValues(alpha: 0.4),
                Icons.hourglass_empty_rounded,
                AppColors.secondary
              );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
              color: iconBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: statusColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.merchant,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600,
                    fontSize: 14,),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  tx.isBlocked
                      ? 'Blocked • ${tx.blockReason ?? 'Rule violation'}'
                      : DateFormatter.timeAgo(tx.timestamp),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12,
                    color: tx.isBlocked ? AppColors.error : AppColors.outline,),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(
            tx.isCredit
                ? '+${CurrencyFormatter.format(tx.amount)}'
                : '-${CurrencyFormatter.format(tx.amount)}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700,
              fontSize: 14,
              color: tx.isCredit ? AppColors.tertiary : AppColors.onSurface,),
          ),
        ],
      ),
    );
  }
}


// ── Section Header ──────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _SectionHeader({required this.title, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.onSurface,),
              ),
            ],
          ),
          if (actionLabel != null)
            GestureDetector(
              onTap: onAction,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  actionLabel!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AccountSelectorWidget extends ConsumerWidget {
  const _AccountSelectorWidget();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(accountsStreamProvider);
    final activeAccount = ref.watch(activeAccountProvider);

    return accountsAsync.when(
      data: (accounts) {
        if (accounts.isEmpty) {
          return Text(
            'Creating Profile...',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,),
          );
        }

        final displayName = activeAccount != null
            ? '${activeAccount.name} Account'
            : (accounts.isNotEmpty
                ? '${accounts.first.name} Account'
                : 'My Account');

        return GestureDetector(
          onTap: () => _showAccountPicker(context, ref, accounts, activeAccount),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Dot indicator
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: AppColors.tertiary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  displayName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,),
                ),
                const SizedBox(width: AppSpacing.xxs),
                const Icon(
                  Icons.unfold_more_rounded,
                  color: AppColors.primary,
                  size: 16,
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
      ),
      error: (_, __) => Text(
        'Gatekipa',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 18,
          fontWeight: FontWeight.w800,
          color: AppColors.primary,),
      ),
    );
  }

  void _showAccountPicker(
    BuildContext context,
    WidgetRef ref,
    List<AccountModel> accounts,
    AccountModel? activeAccount,
  ) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => _AccountPickerSheet(
        accounts: accounts,
        activeAccount: activeAccount,
        onSelect: (account) {
          ref
              .read(activeAccountIdProvider.notifier)
              .setActiveAccount(account.id);
          Navigator.of(sheetCtx, rootNavigator: true).pop();
        },
      ),
    );
  }
}

class _AccountPickerSheet extends StatelessWidget {
  final List<AccountModel> accounts;
  final AccountModel? activeAccount;
  final void Function(AccountModel) onSelect;

  const _AccountPickerSheet({
    required this.accounts,
    required this.activeAccount,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(28),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: AppColors.outlineVariant,
                borderRadius: BorderRadius.circular(100),
              ),
            ),
          ),

          Row(
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
                'Switch Account',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.onSurface,),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Tap an account to make it active',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13,
              color: AppColors.onSurfaceVariant,),
          ),
          const SizedBox(height: 20),

          // Account tiles
          ...accounts.asMap().entries.map((entry) {
            final i = entry.key;
            final account = entry.value;
            final isActive = account.id == activeAccount?.id;

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: isActive
                    ? AppColors.primary.withValues(alpha: 0.06)
                    : AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  onTap: () => onSelect(account),
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isActive
                            ? AppColors.primary.withValues(alpha: 0.4)
                            : AppColors.outlineVariant.withValues(alpha: 0.5),
                        width: isActive ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        // Account avatar
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: isActive
                                ? AppColors.primary
                                : AppColors.surfaceContainer,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Center(
                            child: Text(
                              account.name.isNotEmpty
                                  ? account.name[0].toUpperCase()
                                  : 'A',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: isActive
                                    ? Colors.white
                                    : AppColors.onSurfaceVariant,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),

                        // Name + type
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${account.name} Account',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: AppColors.onSurface,),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                isActive ? 'Currently Active' : 'Tap to switch',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12,
                                  color: isActive
                                      ? AppColors.primary
                                      : AppColors.onSurfaceVariant,
                                  fontWeight: isActive
                                      ? FontWeight.w600
                                      : FontWeight.w400,),
                              ),
                            ],
                          ),
                        ),

                        // Active check
                        if (isActive)
                          Container(
                            width: 28,
                            height: 28,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                          )
                        else
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: AppColors.outlineVariant, width: 1.5),
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ).animate(delay: (i * 50).ms).fadeIn().slideY(begin: 0.05, end: 0),
            );
          }),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}


