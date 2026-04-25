// lib/app.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gatekipa/core/theme/app_theme.dart';
import 'package:gatekipa/core/constants/routes.dart';
import 'package:gatekipa/features/auth/providers/auth_provider.dart';
import 'package:gatekipa/features/auth/screens/splash_screen.dart';
import 'package:gatekipa/features/auth/screens/onboarding_screen.dart';
import 'package:gatekipa/features/auth/screens/email_auth_screen.dart';
import 'package:gatekipa/features/auth/screens/phone_auth_screen.dart';
import 'package:gatekipa/features/auth/screens/otp_screen.dart';
import 'package:gatekipa/features/auth/screens/email_verify_pending_screen.dart';
import 'package:gatekipa/features/profile/screens/kyc_verification_screen.dart';
import 'package:gatekipa/features/dashboard/screens/dashboard_screen.dart';
import 'package:gatekipa/features/wallet/screens/wallet_screen.dart';
import 'package:gatekipa/features/wallet/screens/add_funds_screen.dart';
import 'package:gatekipa/features/cards/screens/cards_list_screen.dart';
import 'package:gatekipa/features/cards/screens/card_creation_screen.dart';
import 'package:gatekipa/features/cards/screens/card_detail_screen.dart';
import 'package:gatekipa/features/accounts/screens/account_detail_screen.dart';
import 'package:gatekipa/features/detect/screens/detection_setup_screen.dart';
import 'package:gatekipa/features/detect/screens/detected_subscriptions_screen.dart';
import 'package:gatekipa/features/notifications/screens/notification_center_screen.dart';
import 'package:gatekipa/features/notifications/screens/notification_detail_screen.dart';
import 'package:gatekipa/features/analytics/screens/analytics_hub_screen.dart';
import 'package:gatekipa/features/analytics/screens/efficiency_portfolio_screen.dart';
import 'package:gatekipa/features/analytics/screens/savings_deep_dive_screen.dart';
import 'package:gatekipa/features/profile/screens/profile_screen.dart';
import 'package:gatekipa/features/profile/screens/settings_screen.dart';
import 'package:gatekipa/features/accounts/screens/accounts_screen.dart';
import 'package:gatekipa/features/accounts/models/account_model.dart';
import 'package:gatekipa/features/team/screens/team_members_screen.dart';
import 'package:gatekipa/features/profile/screens/pin_management_screen.dart';
import 'package:gatekipa/features/profile/screens/biometrics_screen.dart';
import 'package:gatekipa/features/profile/screens/premium_upgrade_screen.dart';
import 'package:gatekipa/features/profile/screens/support_screen.dart';

import 'package:gatekipa/core/widgets/app_shell.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

class RouterNotifier extends ChangeNotifier {
  final Ref ref;
  RouterNotifier(this.ref) {
    ref.listen(
      authStateProvider,
      (_, __) => notifyListeners(),
    );
    ref.listen(
      userProfileProvider,
      (_, __) => notifyListeners(),
    );
  }
}

final routerNotifierProvider = Provider((ref) => RouterNotifier(ref));

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(routerNotifierProvider);
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: Routes.splash,
    refreshListenable: notifier,
    redirect: (context, state) {
      final user = FirebaseAuth.instance.currentUser;
      final isAuthRoute = [
        Routes.onboarding,
        Routes.emailAuth,
        Routes.phoneAuth,
        Routes.otp,
        Routes.emailVerifyPending,
        Routes.kyc,
      ].contains(state.fullPath);

      // Unauthenticated users: send to phone login (not intro slides)
      if (user == null && !isAuthRoute && state.fullPath != Routes.splash) {
        return Routes.phoneAuth;
      }

      // KYC guard has been removed from global routing so users can access the wallet.
      // Card issuance will be gated at the card creation screen instead.
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (ctx, state) => const SplashScreen(),
      ),
      GoRoute(
        path: Routes.onboarding,
        builder: (ctx, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: Routes.emailAuth,
        builder: (ctx, state) => const EmailAuthScreen(),
      ),
      GoRoute(
        path: Routes.phoneAuth,
        builder: (ctx, state) => const PhoneAuthScreen(),
      ),
      GoRoute(
        path: Routes.otp,
        builder: (ctx, state) => OtpScreen(
          phoneNumber: state.extra as String? ?? '',
        ),
      ),
      GoRoute(
        path: Routes.emailVerifyPending,
        builder: (ctx, state) => EmailVerifyPendingScreen(
          email: state.extra as String? ?? '',
        ),
      ),
      GoRoute(
        path: Routes.kyc,
        builder: (ctx, state) => const KycVerificationScreen(),
      ),
      GoRoute(
        path: Routes.profile,
        builder: (ctx, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: Routes.settings,
        builder: (ctx, state) => const SettingsScreen(),
      ),
      // ── Profile sub-screens (full-screen, outside ShellRoute) ────────────
      // These must live outside the ShellRoute so the bottom nav is hidden
      // and — critically — so they INHERIT the MaterialApp ThemeData.
      // Using raw Navigator.push(MaterialPageRoute(...)) bypasses GoRouter's
      // theme context and causes blank/dark screen rendering.
      GoRoute(
        path: Routes.pinManagement,
        builder: (ctx, state) => const PinManagementScreen(),
      ),
      GoRoute(
        path: Routes.biometrics,
        builder: (ctx, state) => const BiometricsScreen(),
      ),
      GoRoute(
        path: Routes.premiumUpgrade,
        builder: (ctx, state) => const PremiumUpgradeScreen(),
      ),
      GoRoute(
        path: Routes.support,
        builder: (ctx, state) => const SupportScreen(),
      ),
      // Shell route — 4-tab scaffold
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (ctx, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: Routes.wallet,
            builder: (ctx, state) => const WalletScreen(),
            routes: [
              GoRoute(
                path: 'add-funds',
                builder: (ctx, state) => const AddFundsScreen(),
              ),
            ],
          ),
          GoRoute(
            path: Routes.cards,
            builder: (ctx, state) => const CardsListScreen(),
            routes: [
              GoRoute(
                path: 'create',
                builder: (ctx, state) {
                  final e = state.extra;
                  return CardCreationScreen(
                    prefillMerchant: e is Map<String, String> ? e : null,
                    accountId: e is String ? e : null,
                  );
                },
              ),
              GoRoute(
                path: ':cardId',
                builder: (ctx, state) => CardDetailScreen(
                  cardId: state.pathParameters['cardId']!,
                ),
              ),
            ],
          ),

          GoRoute(
            path: Routes.detect,
            builder: (ctx, state) => const DetectionSetupScreen(),
            routes: [
              GoRoute(
                path: 'subscriptions',
                builder: (ctx, state) => const DetectedSubscriptionsScreen(),
              ),
            ],
          ),
          GoRoute(
            path: Routes.notifications,
            builder: (ctx, state) => const NotificationCenterScreen(),
            routes: [
              GoRoute(
                path: ':notifId',
                builder: (ctx, state) => NotificationDetailScreen(
                  notifId: state.pathParameters['notifId']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: Routes.insights,
            builder: (ctx, state) => const AnalyticsHubScreen(),
            routes: [
              GoRoute(
                path: 'efficiency',
                builder: (ctx, state) => const EfficiencyPortfolioScreen(),
              ),
              GoRoute(
                path: 'savings',
                builder: (ctx, state) => const SavingsDeepDiveScreen(),
              ),
            ],
          ),
          GoRoute(
            path: Routes.dashboard,
            builder: (ctx, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: Routes.accounts,
            builder: (ctx, state) => const AccountsScreen(),
            routes: [
              GoRoute(
                path: ':accountId',
                builder: (ctx, state) {
                  final account = state.extra as AccountModel;
                  return AccountDetailScreen(account: account);
                },
                routes: [
                  GoRoute(
                    path: 'team',
                    builder: (ctx, state) {
                      final account = state.extra as AccountModel;
                      return TeamMembersScreen(account: account);
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

class GatekipaApp extends ConsumerWidget {
  const GatekipaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return InactivityWrapper(
      child: MaterialApp.router(
        title: 'Gatekipa',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        routerConfig: router,
      ),
    );
  }
}

class InactivityWrapper extends ConsumerStatefulWidget {
  final Widget child;
  const InactivityWrapper({super.key, required this.child});

  @override
  ConsumerState<InactivityWrapper> createState() => _InactivityWrapperState();
}

class _InactivityWrapperState extends ConsumerState<InactivityWrapper> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _resetTimer();
  }

  void _resetTimer() {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 30), () {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Lock the app (forces biometrics or PIN on next launch)
        ref.read(authNotifierProvider.notifier).lockApp();
        // Route to splash to enforce the lock gate
        ref.read(routerProvider).go(Routes.splash);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _resetTimer,
      onPanDown: (_) => _resetTimer(),
      onPanUpdate: (_) => _resetTimer(),
      child: widget.child,
    );
  }
}
