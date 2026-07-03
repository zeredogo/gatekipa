import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:gatekipa/firebase_options.dart';
import 'package:gatekipa/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gatekipa/core/theme/app_theme.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  AppTheme.isTesting = true;
  GoogleFonts.config.allowRuntimeFetching = false;
  
  // Ignore GoogleFonts network loading exceptions in testing environment
  final originalOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    final exceptionStr = details.exception.toString();
    if (exceptionStr.contains('Failed to load font') || 
        exceptionStr.contains('GoogleFonts') ||
        exceptionStr.contains('SpaceMono') ||
        exceptionStr.contains('Inter')) {
      debugPrint('ℹ️ Ignored GoogleFonts loading error: ${details.exception}');
      return;
    }
    originalOnError?.call(details);
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    final errorStr = error.toString();
    if (errorStr.contains('Failed to load font') || 
        errorStr.contains('GoogleFonts') ||
        errorStr.contains('SpaceMono') ||
        errorStr.contains('Inter')) {
      debugPrint('ℹ️ Ignored async GoogleFonts loading error: $error');
      return true; // handled
    }
    return false; // propagate
  };

  group('Insights Access E2E Test', () {
    Future<void> login(WidgetTester tester, String email, String password) async {
      debugPrint("🔐 Attempting to log in as $email...");
      
      // Wait up to 8 seconds for the app to boot and display one of the starting screens
      int bootWait = 0;
      while (!tester.any(find.text('Sign In')) && 
             !tester.any(find.textContaining('Continue with Email instead')) && 
             !tester.any(find.byType(TextField)) && 
             bootWait < 40) {
        await tester.pump(const Duration(milliseconds: 200));
        bootWait++;
      }

      // Skip Onboarding if present
      final signInSkip = find.text('Sign In');
      if (tester.any(signInSkip)) {
          debugPrint("🚀 Onboarding detected. Skipping to Login...");
          await tester.tap(signInSkip.first);
          await tester.pump(const Duration(seconds: 3));
      }

      // Wait up to 5 seconds for transition to settle
      int waitCount = 0;
      while (!tester.any(find.textContaining('Continue with Email instead')) && 
             !tester.any(find.byType(TextField)) && 
             waitCount < 25) {
        await tester.pump(const Duration(milliseconds: 200));
        waitCount++;
      }

      // If on Phone login screen, switch to Email login screen
      final emailOption = find.textContaining('Continue with Email instead');
      if (tester.any(emailOption)) {
          debugPrint("📧 Switching to Email Login screen...");
          await tester.tap(emailOption.first);
          await tester.pump(const Duration(seconds: 3));
      }

      // Define precise finders targeting the decorations on the text fields
      final emailFinder = find.byWidgetPredicate((widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'Email Address');
      final passwordFinder = find.byWidgetPredicate((widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'Password');

      // Wait up to 10 seconds for the Email and Password fields to be visible on screen
      waitCount = 0;
      while ((!tester.any(emailFinder) || !tester.any(passwordFinder)) && waitCount < 50) {
        await tester.pump(const Duration(milliseconds: 200));
        waitCount++;
      }

      // Enter credentials with visibility insurance
      await tester.ensureVisible(emailFinder.first);
      await tester.enterText(emailFinder, email);
      await tester.ensureVisible(passwordFinder.first);
      await tester.enterText(passwordFinder, password);
      await tester.pump();
      
      // Tap the FilledButton that contains 'Sign In'
      final submitBtn = find.ancestor(
        of: find.text('Sign In'),
        matching: find.byType(FilledButton),
      );

      if (tester.any(submitBtn)) {
          debugPrint("👆 Tapping login FilledButton...");
          await tester.ensureVisible(submitBtn.first);
          await tester.tap(submitBtn.first);
          await tester.pump();
      } else {
          // Fallback if the ancestor structure is different
          final loginBtn = find.byType(FilledButton);
          if (tester.any(loginBtn)) {
              debugPrint("👆 Tapping fallback login FilledButton...");
              await tester.ensureVisible(loginBtn.first);
              await tester.tap(loginBtn.first);
              await tester.pump();
          }
      }
      
      // Wait up to 15 seconds for login to complete and transition off the login screen
      waitCount = 0;
      while (tester.any(find.text('Welcome Back')) && waitCount < 75) {
        await tester.pump(const Duration(milliseconds: 200));
        waitCount++;
      }
      
      final currentUser = FirebaseAuth.instance.currentUser;
      debugPrint("🔐 FirebaseAuth current user: ${currentUser?.email}, uid: ${currentUser?.uid}, verified: ${currentUser?.emailVerified}");
      
      // Additional pump to settle dashboard transitions
      await tester.pump(const Duration(seconds: 3));
    }

    Future<void> navigateToInsights(WidgetTester tester) async {
      debugPrint("🧭 Navigating to Insights Menu...");

      // Print all visible text widgets before tapping
      final textsBefore = tester.widgetList<Text>(find.byType(Text));
      debugPrint("--- SCREEN TEXTS BEFORE NAV ---");
      for (var t in textsBefore) {
        debugPrint("SCREEN TEXT: ${t.data}");
      }
      debugPrint("-------------------------------");
      
      final insightsTab = find.text('Insights');
      if (tester.any(insightsTab)) {
        await tester.tap(insightsTab.first);
        await tester.pump(const Duration(seconds: 3));
      } else {
        // Find by icon if text is hidden
        final iconTab = find.byIcon(Icons.insights);
        if (tester.any(iconTab)) {
            await tester.tap(iconTab.first);
            await tester.pump(const Duration(seconds: 3));
        } else {
            // Check for Icons.insights_rounded as well
            final roundedIconTab = find.byIcon(Icons.insights_rounded);
            if (tester.any(roundedIconTab)) {
                await tester.tap(roundedIconTab.first);
                await tester.pump(const Duration(seconds: 3));
            }
        }
      }

      // Print all visible text widgets after tapping and pumping
      final textsAfter = tester.widgetList<Text>(find.byType(Text));
      debugPrint("--- SCREEN TEXTS AFTER NAV ---");
      for (var t in textsAfter) {
        debugPrint("SCREEN TEXT: ${t.data}");
      }
      debugPrint("------------------------------");
    }

    testWidgets('Free User sees Sentinel Prime Paywall', (tester) async {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('bypass_biometrics_for_test', true);
      await prefs.setBool('has_seen_dashboard_tutorial', true);
      await FirebaseAuth.instance.signOut();

      await tester.pumpWidget(
        const ProviderScope(
          child: GatekipaApp(),
        ),
      );
      await tester.pump(const Duration(seconds: 3));

      await login(tester, 'insight_free@gatekipa.app', 'Password123!');
      await navigateToInsights(tester);

      debugPrint("🔍 Verifying Paywall for Free User...");
      
      final sentinelText = find.text('Sentinel Prime');
      final unlockText = find.textContaining(RegExp('Unlock full insights', caseSensitive: false));
      
      expect(sentinelText, findsWidgets, reason: 'Paywall title should appear');
      expect(unlockText, findsWidgets, reason: 'Paywall description should appear');
      
      debugPrint("✅ Free User correctly saw the Premium Paywall.");
      
      // Settle any remaining async tasks and consume pending exceptions
      await tester.pump(const Duration(seconds: 3));
      tester.takeException();
    });

    testWidgets('Premium User sees Analytics Hub', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('bypass_biometrics_for_test', true);
      await prefs.setBool('has_seen_dashboard_tutorial', true);
      await FirebaseAuth.instance.signOut();

      await tester.pumpWidget(
        const ProviderScope(
          child: GatekipaApp(),
        ),
      );
      await tester.pump(const Duration(seconds: 3));

      await login(tester, 'insight_premium@gatekipa.app', 'Password123!');
      await navigateToInsights(tester);

      debugPrint("🔍 Verifying Analytics Content for Premium User...");
      
      // Wait up to 10 seconds for analytics data to load
      int waitCount = 0;
      final contentFinder = find.textContaining(RegExp('Recovered|No data yet|spending intelligence', caseSensitive: false));
      while (!tester.any(contentFinder) && waitCount < 50) {
        await tester.pump(const Duration(milliseconds: 200));
        waitCount++;
      }
      
      final contentText = find.textContaining(RegExp('Recovered|No data yet|spending intelligence', caseSensitive: false));
      expect(contentText, findsWidgets, reason: 'Analytics content or empty state should appear');
      
      final paywallText = find.textContaining(RegExp('Unlock full insights', caseSensitive: false));
      expect(paywallText, findsNothing, reason: 'Paywall should NOT appear');

      debugPrint("✅ Premium User correctly saw Analytics Content.");

      // Settle any remaining async tasks and consume pending exceptions
      await tester.pump(const Duration(seconds: 3));
      tester.takeException();
    });

    testWidgets('Business User sees Analytics Hub', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('bypass_biometrics_for_test', true);
      await prefs.setBool('has_seen_dashboard_tutorial', true);
      await FirebaseAuth.instance.signOut();

      await tester.pumpWidget(
        const ProviderScope(
          child: GatekipaApp(),
        ),
      );
      await tester.pump(const Duration(seconds: 3));

      await login(tester, 'insight_business@gatekipa.app', 'Password123!');
      await navigateToInsights(tester);

      debugPrint("🔍 Verifying Analytics Content for Business User...");
      
      // Wait up to 10 seconds for analytics data to load
      int waitCount = 0;
      final contentFinder = find.textContaining(RegExp('Recovered|No data yet|spending intelligence', caseSensitive: false));
      while (!tester.any(contentFinder) && waitCount < 50) {
        await tester.pump(const Duration(milliseconds: 200));
        waitCount++;
      }
      
      final contentText = find.textContaining(RegExp('Recovered|No data yet|spending intelligence', caseSensitive: false));
      expect(contentText, findsWidgets, reason: 'Analytics content or empty state should appear');
      
      final paywallText = find.textContaining(RegExp('Unlock full insights', caseSensitive: false));
      expect(paywallText, findsNothing, reason: 'Paywall should NOT appear');

      debugPrint("✅ Business User correctly saw Analytics Content.");

      // Settle any remaining async tasks and consume pending exceptions
      await tester.pump(const Duration(seconds: 3));
      tester.takeException();
    });
  });
}
