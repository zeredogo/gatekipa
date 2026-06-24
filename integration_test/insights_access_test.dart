import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:gatekipa/firebase_options.dart';
import 'package:gatekipa/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Insights Access E2E Test', () {
    Future<void> login(WidgetTester tester, String email, String password) async {
      debugPrint("🔐 Attempting to log in as $email...");
      
      if (FirebaseAuth.instance.currentUser != null) {
        await FirebaseAuth.instance.signOut();
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }

      // Skip Onboarding if present
      final signInSkip = find.text('Sign In');
      if (tester.any(signInSkip)) {
          debugPrint("🚀 Onboarding detected. Skipping to Login...");
          await tester.tap(signInSkip.first);
          await tester.pumpAndSettle(const Duration(seconds: 2));
      }

      final textFields = find.byType(TextField);
      final textFormFields = find.byType(TextFormField);
      
      if (!tester.any(textFields) && !tester.any(textFormFields)) {
        await tester.pumpAndSettle(const Duration(seconds: 3));
      }

      if (tester.any(textFields) && textFields.evaluate().length >= 2) {
          await tester.enterText(textFields.at(0), email);
          await tester.enterText(textFields.at(1), password);
      } else if (tester.any(textFormFields) && textFormFields.evaluate().length >= 2) {
          await tester.enterText(textFormFields.at(0), email);
          await tester.enterText(textFormFields.at(1), password);
      }
      
      final loginBtn = find.textContaining(RegExp(r'Sign In|Login', caseSensitive: false));
      if (tester.any(loginBtn)) {
          await tester.tap(loginBtn.first);
      }
      
      // Wait for login to complete and navigate to home
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle(const Duration(seconds: 3));
    }

    Future<void> navigateToInsights(WidgetTester tester) async {
      debugPrint("🧭 Navigating to Insights Menu...");
      
      // Tap Insights tab in bottom navigation
      final insightsTab = find.text('Insights');
      if (tester.any(insightsTab)) {
        await tester.tap(insightsTab.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
      } else {
        // Find by icon if text is hidden
        final iconTab = find.byIcon(Icons.insights);
        if (tester.any(iconTab)) {
            await tester.tap(iconTab.first);
            await tester.pumpAndSettle(const Duration(seconds: 3));
        }
      }
    }

    testWidgets('Free User sees Sentinel Prime Paywall', (tester) async {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

      await tester.pumpWidget(
        const ProviderScope(
          child: GatekipaApp(),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await login(tester, 'insight_free@gatekipa.app', 'Password123!');
      await navigateToInsights(tester);

      debugPrint("🔍 Verifying Paywall for Free User...");
      
      final sentinelText = find.text('Sentinel Prime');
      final unlockText = find.textContaining(RegExp('Unlock full insights', caseSensitive: false));
      
      expect(sentinelText, findsWidgets, reason: 'Paywall title should appear');
      expect(unlockText, findsWidgets, reason: 'Paywall description should appear');
      
      debugPrint("✅ Free User correctly saw the Premium Paywall.");
    });

    testWidgets('Premium User sees Analytics Hub', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: GatekipaApp(),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await login(tester, 'insight_premium@gatekipa.app', 'Password123!');
      await navigateToInsights(tester);

      debugPrint("🔍 Verifying Analytics Content for Premium User...");
      
      final recoveredText = find.textContaining(RegExp('Recovered', caseSensitive: false));
      expect(recoveredText, findsWidgets, reason: 'Analytics content should appear');
      
      final paywallText = find.textContaining(RegExp('Unlock full insights', caseSensitive: false));
      expect(paywallText, findsNothing, reason: 'Paywall should NOT appear');

      debugPrint("✅ Premium User correctly saw Analytics Content.");
    });

    testWidgets('Business User sees Analytics Hub', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: GatekipaApp(),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await login(tester, 'insight_business@gatekipa.app', 'Password123!');
      await navigateToInsights(tester);

      debugPrint("🔍 Verifying Analytics Content for Business User...");
      
      final recoveredText = find.textContaining(RegExp('Recovered', caseSensitive: false));
      expect(recoveredText, findsWidgets, reason: 'Analytics content should appear');
      
      final paywallText = find.textContaining(RegExp('Unlock full insights', caseSensitive: false));
      expect(paywallText, findsNothing, reason: 'Paywall should NOT appear');

      debugPrint("✅ Business User correctly saw Analytics Content.");
    });
  });
}
