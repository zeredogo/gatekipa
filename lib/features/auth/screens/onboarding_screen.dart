// lib/features/auth/screens/onboarding_screen.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gatekeepeer/core/constants/routes.dart';
import 'package:gatekeepeer/core/theme/app_colors.dart';
import 'package:gatekeepeer/core/widgets/gk_button.dart';
import 'package:gatekeepeer/core/theme/app_spacing.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  static const _pages = [
    _OnboardingPage(
      icon: Icons.block_rounded,
      gradientStart: Color(0xFF003629),
      gradientEnd: Color(0xFF1B4D3E),
      tag: 'PROBLEM',
      headline: 'Stop getting\nsilently charged',
      sub:
          'Subscriptions auto-renew without warning. Gatekipa gives you the power to say when — and when not — to pay.',
      step: 1,
    ),
    _OnboardingPage(
      icon: Icons.credit_card_rounded,
      gradientStart: Color(0xFF1a1a2e),
      gradientEnd: Color(0xFF16213e),
      tag: 'SOLUTION',
      headline: 'Virtual cards with\nprogrammable rules',
      sub:
          'Create one-time or limited cards. Define max charges, spending caps, and expiry windows. Your card, your rules.',
      step: 2,
    ),
    _OnboardingPage(
      icon: Icons.shield_rounded,
      gradientStart: Color(0xFF003629),
      gradientEnd: Color(0xFF005027),
      tag: 'CONTROL',
      headline: 'Automatic\nbreach detection',
      sub:
          'Your Gatekipa watches every charge. Rule violations trigger instant blocks and real-time notifications.',
      step: 3,
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      _goToLogin();
    }
  }

  Future<void> _goToLogin() async {
    // Mark that this device has completed onboarding —
    // future cold-starts will skip these slides.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_onboarded', true);
    if (!mounted) return;
    context.push(Routes.emailAuth);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Skip button
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: TextButton(
                  onPressed: () => _goToLogin(),
                  child: const Text(
                    'Sign In',
                    style: TextStyle(height: 1.2, fontFamily: 'Manrope', color: AppColors.outline,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,),
                  ),
                ),
              ),
            ),
            // Page view
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (ctx, i) => _OnboardingPageWidget(page: _pages[i]),
              ),
            ),
            // Indicator + button
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _pages.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: i == _currentPage ? 24 : 8,
                        height: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: i == _currentPage
                              ? AppColors.primary
                              : AppColors.outlineVariant,
                          borderRadius: BorderRadius.circular(100),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  GkButton(
                    label: _currentPage == _pages.length - 1
                        ? 'Create My Vault'
                        : 'Continue',
                    icon: Icons.arrow_forward_rounded,
                    onPressed: _nextPage,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPage {
  final IconData icon;
  final Color gradientStart;
  final Color gradientEnd;
  final String tag;
  final String headline;
  final String sub;
  final int step;

  const _OnboardingPage({
    required this.icon,
    required this.gradientStart,
    required this.gradientEnd,
    required this.tag,
    required this.headline,
    required this.sub,
    required this.step,
  });
}

class _OnboardingPageWidget extends StatelessWidget {
  final _OnboardingPage page;
  const _OnboardingPageWidget({required this.page});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Flat, Premium Physical Credit Card (De-AI'd)
          Container(
            height: 220,
            width: double.infinity,
            decoration: BoxDecoration(
                // Using a subtle physical metallic gradient rather than a bright radial glow
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(page.gradientEnd, Colors.black, 0.4)!,
                    Color.lerp(page.gradientStart, Colors.black, 0.6)!,
                    Color.lerp(page.gradientEnd, Colors.black, 0.8)!,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                  width: 1,
                ),
                boxShadow: [
                  // Grounded physical drop shadow, very tight and dark
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 16,
                    spreadRadius: -4,
                    offset: const Offset(0, 12),
                  )
                ]),
            child: Stack(
              children: [
                // Card Content (No foil pattern or glassmorphism shine)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.contactless_outlined,
                              color: Colors.white70, size: 28),
                          Text(
                            'GATEKEEPEER',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              letterSpacing: 3,),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '**** **** **** 4092',
                            style: GoogleFonts.spaceMono(
                              // Monospace for numbers
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('VALID THRU',
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 8,
                                          color: Colors.white54,
                                          fontWeight: FontWeight.w600)),
                                  Text('12/28',
                                      style: GoogleFonts.spaceMono(
                                          fontSize: 14,
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(height: AppSpacing.xxs),
                                  Text('GATEKEEPEER USER',
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14,
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 1)),
                                ],
                              ),
                              // Payment Network Logo
                              _CardNetworkLogo(step: page.step),
                            ],
                          )
                        ],
                      )
                    ],
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 400.ms, curve: Curves.easeOut),
          const SizedBox(height: 36),
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    page.tag,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                      letterSpacing: 2,),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  page.headline,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: AppColors.onSurface,
                    height: 1.2,
                    letterSpacing: -0.5,),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  page.sub,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 16,
                    color: AppColors.onSurfaceVariant,
                    height: 1.6,),
                ),
              ],
            ),
          ).animate().fadeIn(delay: 150.ms, duration: 400.ms),
        ],
      ),
    );
  }
}

class _CardNetworkLogo extends StatelessWidget {
  final int step;
  const _CardNetworkLogo({required this.step});

  @override
  Widget build(BuildContext context) {
    if (step == 1) {
      // Mastercard-esque logo
      return SizedBox(
        width: 44,
        height: 28,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              left: 16,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      );
    } else if (step == 2) {
      // Visa-esque logo
      return Text(
        'VISA',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 24,
          fontWeight: FontWeight.w900,
          fontStyle: FontStyle.italic,
          color: Colors.white,
          letterSpacing: -1,),
      );
    } else {
      // Verve-esque logo
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.redAccent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'Verve',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14,
                fontWeight: FontWeight.w800,
                fontStyle: FontStyle.italic,
                color: Colors.white,),
            ),
          ),
        ],
      );
    }
  }
}
