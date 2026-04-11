// lib/core/widgets/app_shell.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../constants/routes.dart';

class AppShell extends StatefulWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;

  static const _tabs = [
    _TabItem(
      icon: Icons.home_rounded,
      label: 'Home',
      route: Routes.dashboard,
    ),
    _TabItem(
      icon: Icons.credit_card_rounded,
      label: 'Cards',
      route: Routes.cards,
    ),
    _TabItem(
      icon: Icons.radar_rounded,
      label: 'Detect',
      route: Routes.detect,
    ),
    _TabItem(
      icon: Icons.insights_rounded,
      label: 'Insights',
      route: Routes.insights,
    ),
    _TabItem(
      icon: Icons.manage_accounts_rounded,
      label: 'Accounts',
      route: Routes.accounts,
    ),
  ];

  String _locationToRoute(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    if (location.startsWith(Routes.insights)) return Routes.insights;
    if (location.startsWith(Routes.search)) return Routes.search;
    if (location.startsWith(Routes.detect) ||
        location.startsWith(Routes.notifications)) {
      return Routes.detect;
    }
    if (location.startsWith(Routes.cards)) return Routes.cards;
    if (location.startsWith(Routes.accounts)) return Routes.accounts;
    return Routes.dashboard;
  }

  @override
  Widget build(BuildContext context) {
    final currentRoute = _locationToRoute(context);
    _currentIndex = _tabs.indexWhere((t) => t.route == currentRoute);
    if (_currentIndex == -1) _currentIndex = 0;

    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          // If not on Home tab, go to Home instead of exiting app
          context.go(Routes.dashboard);
        }
      },
      child: Scaffold(
        body: widget.child,
        extendBody: true,
        bottomNavigationBar: _GkBottomNav(
          tabs: _tabs,
          currentIndex: _currentIndex,
          onTap: (i) {
            setState(() => _currentIndex = i);
            context.go(_tabs[i].route);
          },
        ),
      ),
    );
  }
}

class _TabItem {
  final IconData icon;
  final String label;
  final String route;
  const _TabItem(
      {required this.icon, required this.label, required this.route});
}

class _GkBottomNav extends StatelessWidget {
  final List<_TabItem> tabs;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _GkBottomNav({
    required this.tabs,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16.0, sigmaY: 16.0),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest.withValues(alpha: 0.75),
            boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(tabs.length, (i) {
              final isSelected = i == currentIndex;
              final tab = tabs[i];
              return Flexible(
                child: GestureDetector(
                  onTap: () => onTap(i),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: 300.ms,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 2, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary.withValues(alpha: 0.08)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          tab.icon,
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.outline,
                          size: 24,
                        ).animate(target: isSelected ? 1 : 0).scaleXY(
                              begin: 1,
                              end: 1.1,
                              duration: 200.ms,
                              curve: Curves.easeOut,
                            ),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            tab.label,
                            maxLines: 1,
                            softWrap: false,
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight:
                                  isSelected ? FontWeight.w700 : FontWeight.w500,
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.outline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    ),
      ),
    );
  }
}
