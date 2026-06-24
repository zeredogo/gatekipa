// lib/features/auth/screens/splash_screen.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:gatekipa/core/constants/routes.dart';
import 'package:gatekipa/core/services/force_update_service.dart';
import 'package:gatekipa/core/theme/app_colors.dart';

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

    // ── Force-update gate ────────────────────────────────────────────────────
    // Silently checks Remote Config. If the installed build is too old,
    // show a blocking dialog. The version number is never shown to the user.
    final needsUpdate = await ForceUpdateService.isUpdateRequired();
    if (!mounted) return;
    if (needsUpdate) {
      _showForceUpdateDialog();
      return; // Stop routing — user must update before proceeding
    }

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
          if (mounted) context.go(Routes.emailAuth);
          return;
        }
      }

      if (mounted) {
        if (!user.emailVerified) {
          context.go(Routes.emailVerifyPending, extra: user.email);
        } else {
          context.go(Routes.dashboard);
        }
      }
      return;
    }

    // ── No Firebase session (user did a full signOut or first launch) ─────────
    final hasOnboarded = prefs.getBool('has_onboarded') ?? false;
    if (mounted) {
      context.go(hasOnboarded ? Routes.emailAuth : Routes.onboarding);
    }
  }

  /// Shows a non-dismissible dialog that blocks all navigation until the user
  /// taps "Update Now" and is sent to the Play Store.
  /// The installed version/build number is never displayed.
  void _showForceUpdateDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false, // Blocks the Android back button
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.system_update_rounded, color: AppColors.primary),
              SizedBox(width: 10),
              Text('Update Required'),
            ],
          ),
          content: const Text(
            'A newer version of Gatekipa is available with important '
            'security and performance improvements.\n\n'
            'Please update to continue using the app.',
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final marketUri = Uri.parse('market://details?id=com.gatekipa.gatekeeper');
                final webUri = Uri.parse('https://play.google.com/store/apps/details?id=com.gatekipa.gatekeeper');
                
                if (await canLaunchUrl(marketUri)) {
                  await launchUrl(marketUri, mode: LaunchMode.externalApplication);
                } else if (await canLaunchUrl(webUri)) {
                  await launchUrl(webUri, mode: LaunchMode.externalApplication);
                }

              },
              child: const Text(
                'Update Now',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
