// lib/features/auth/screens/splash_screen.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/routes.dart';
import '../../../core/theme/app_colors.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigate();
  }

  Future<void> _navigate() async {
    // Let the logo animation play
    await Future.delayed(const Duration(milliseconds: 1800));
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;

    // ── Active Firebase session (normal login OR locked-with-biometrics) ──────
    // lockApp() keeps the session alive, so currentUser is non-null even after
    // the user "signs out" via the lock button. Biometric prompt gates access.
    if (user != null) {
      final biometricsEnabled = prefs.getBool('${user.uid}_use_biometrics') ?? false;
      if (biometricsEnabled) {
        final passed = await _tryBiometricAuth();
        if (!mounted) return;
        if (!passed) {
          // Biometric failed / cancelled → full signout → login screen
          await FirebaseAuth.instance.signOut();
          if (mounted) context.go(Routes.phoneAuth);
          return;
        }
      }
      if (mounted) context.go(Routes.dashboard);
      return;
    }

    // ── No Firebase session (user did a full signOut or first launch) ─────────
    final hasOnboarded = prefs.getBool('has_onboarded') ?? false;
    if (mounted) {
      context.go(hasOnboarded ? Routes.phoneAuth : Routes.onboarding);
    }
  }

  /// Triggers the device biometric/PIN prompt.
  /// Returns true if the user passes, false otherwise.
  Future<bool> _tryBiometricAuth() async {
    final auth = LocalAuthentication();
    try {
      final canCheck = await auth.canCheckBiometrics;
      final isSupported = await auth.isDeviceSupported();
      if (!canCheck && !isSupported) return true; // No hardware – skip gate

      return await auth.authenticate(
        localizedReason: 'Verify your identity to open Gatekipa',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false, // allow PIN fallback
        ),
      );
    } catch (_) {
      // Any error (e.g. no enrolled biometrics) → let user through
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Image.asset(
          'assets/images/logo.png',
          width: 340,
          height: 340,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (ctx, _, __) => const Icon(
            Icons.shield_rounded,
            color: AppColors.primary,
            size: 88,
          ),
        ).animate().scale(
              begin: const Offset(0.4, 0.4),
              end: const Offset(1, 1),
              duration: 800.ms,
              curve: Curves.elasticOut,
            ),
      ),
    );
  }
}
