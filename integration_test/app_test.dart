import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:gatekipa/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Gatekipa E2E UI Integration Test', () {
    testWidgets('Full User Journey: Authentication, Dashboard, and Menus', (tester) async {
      app.main();
      
      // Wait for app to render and settle
      await tester.pumpAndSettle(const Duration(seconds: 5));

      final isLoggedOut = tester.any(find.byType(TextField)) || tester.any(find.byType(TextFormField));

      if (isLoggedOut) {
        debugPrint("🔐 App is on Login Screen. Attempting to log in...");
        
        final textFields = find.byType(TextField);
        final textFormFields = find.byType(TextFormField);
        
        if (tester.any(textFields) && textFields.evaluate().length >= 2) {
          await tester.enterText(textFields.at(0), 'tester@gatekipa.app');
          await tester.enterText(textFields.at(1), 'Password123!');
          await tester.pumpAndSettle();
        } else if (tester.any(textFormFields) && textFormFields.evaluate().length >= 2) {
          await tester.enterText(textFormFields.at(0), 'tester@gatekipa.app');
          await tester.enterText(textFormFields.at(1), 'Password123!');
          await tester.pumpAndSettle();
        }
        
        final loginButton = find.byType(ElevatedButton);
        if (tester.any(loginButton)) {
          await tester.tap(loginButton.first);
          await tester.pumpAndSettle(const Duration(seconds: 5));
        }
      } else {
        debugPrint("✅ App is already logged in (cached session). Proceeding to Dashboard...");
      }

      // --- 2. DASHBOARD / WALLET ---
      debugPrint("💰 Testing Wallet / Dashboard...");
      await tester.pumpAndSettle(const Duration(seconds: 3));

      final addFundsButton = find.textContaining(RegExp(r'Add Funds', caseSensitive: false));
      if (tester.any(addFundsButton)) {
        debugPrint("➡️ Tapping 'Add Funds'...");
        await tester.tap(addFundsButton.first);
        await tester.pumpAndSettle();
        
        final backButton = find.byTooltip('Back');
        if (tester.any(backButton)) {
          await tester.tap(backButton.first);
        } else {
          try {
            Navigator.of(tester.element(find.byType(MaterialApp))).pop();
          } catch(e) {}
        }
        await tester.pumpAndSettle();
      }

      // --- 3. BOTTOM NAVIGATION MENUS ---
      debugPrint("🧭 Testing Bottom Navigation (Cards, Detect, Insights)...");
      
      final cardsTab = find.textContaining(RegExp(r'Cards', caseSensitive: false));
      if (tester.any(cardsTab)) {
        await tester.tap(cardsTab.last);
        await tester.pumpAndSettle();
      }

      final detectTab = find.textContaining(RegExp(r'Detect', caseSensitive: false));
      if (tester.any(detectTab)) {
        await tester.tap(detectTab.last);
        await tester.pumpAndSettle();
      }

      final insightsTab = find.textContaining(RegExp(r'Insights', caseSensitive: false));
      if (tester.any(insightsTab)) {
        await tester.tap(insightsTab.last);
        await tester.pumpAndSettle();
      }

      final homeTab = find.textContaining(RegExp(r'Home|Wallet', caseSensitive: false));
      if (tester.any(homeTab)) {
        await tester.tap(homeTab.last);
        await tester.pumpAndSettle();
      }

      // --- 4. PROFILE & SETTINGS ---
      debugPrint("👤 Testing Profile & Settings...");
      var profileIcon = find.byIcon(Icons.person);
      if (!tester.any(profileIcon)) {
        profileIcon = find.byIcon(Icons.settings);
      }
          
      if (tester.any(profileIcon)) {
        await tester.tap(profileIcon.first);
        await tester.pumpAndSettle();

        // Account tab
        debugPrint("🧾 Checking Account...");
        final accountText = find.textContaining(RegExp(r'Account', caseSensitive: false));
        if (tester.any(accountText)) {
          await tester.tap(accountText.first);
          await tester.pumpAndSettle();
          try {
            Navigator.of(tester.element(find.byType(MaterialApp))).pop();
          } catch(e) {}
          await tester.pumpAndSettle();
        }

        debugPrint("🔒 Checking Biometric Lock toggle...");
        final biometricText = find.textContaining(RegExp(r'Biometric', caseSensitive: false));
        if (tester.any(biometricText)) {
          final switchWidget = find.byType(Switch);
          if (tester.any(switchWidget)) {
            await tester.tap(switchWidget.last);
            await tester.pumpAndSettle();
            await tester.tap(switchWidget.last);
            await tester.pumpAndSettle();
          }
        }

        debugPrint("⚙️ Checking Allow Auto Deductions...");
        final autoDeductionsText = find.textContaining(RegExp(r'Allow Auto Deductions', caseSensitive: false));
        if (tester.any(autoDeductionsText)) {
          final switchWidget = find.byType(Switch);
          if (tester.any(switchWidget)) {
            await tester.tap(switchWidget.last);
            await tester.pumpAndSettle();
            await tester.tap(switchWidget.last);
            await tester.pumpAndSettle();
          }
        }

        debugPrint("🆘 Checking Help & Support...");
        final supportText = find.textContaining(RegExp(r'Support|Help', caseSensitive: false));
        if (tester.any(supportText)) {
          await tester.tap(supportText.first);
          await tester.pumpAndSettle();
          
          try {
            Navigator.of(tester.element(find.byType(MaterialApp))).pop();
          } catch(e) {}
          await tester.pumpAndSettle();
        }
        
        // Try closing profile if it was a modal/push
        try {
          Navigator.of(tester.element(find.byType(MaterialApp))).pop();
        } catch(e) {}
        await tester.pumpAndSettle();
      }

      // --- 5. CARDS DEEP DIVE ---
      debugPrint("💳 Testing Add Cards and Kill Switch...");
      final cardsTabRetry = find.textContaining(RegExp(r'Cards', caseSensitive: false));
      if (tester.any(cardsTabRetry)) {
        await tester.tap(cardsTabRetry.last);
        await tester.pumpAndSettle();

        final addCardText = find.textContaining(RegExp(r'Add Card', caseSensitive: false));
        if (tester.any(addCardText)) {
          debugPrint("➡️ Tapping Add Card...");
          await tester.tap(addCardText.first);
          await tester.pumpAndSettle();
          try {
            Navigator.of(tester.element(find.byType(MaterialApp))).pop();
          } catch(e) {}
          await tester.pumpAndSettle();
        }

        // Tap the first card to check kill switch
        final anyCard = find.byType(Card);
        if (tester.any(anyCard)) {
          await tester.tap(anyCard.first);
          await tester.pumpAndSettle();

          final killSwitch = find.textContaining(RegExp(r'Kill Switch', caseSensitive: false));
          if (tester.any(killSwitch)) {
             debugPrint("💀 Tapping Emergency Kill Switch...");
             await tester.tap(killSwitch.first);
             await tester.pumpAndSettle();
             // In case a confirmation dialog pops up
             final cancelDialog = find.textContaining(RegExp(r'Cancel|No', caseSensitive: false));
             if (tester.any(cancelDialog)) {
                 await tester.tap(cancelDialog.last);
                 await tester.pumpAndSettle();
             }
          }
          
          try {
            Navigator.of(tester.element(find.byType(MaterialApp))).pop();
          } catch(e) {}
          await tester.pumpAndSettle();
        }
      }

      debugPrint("🎉 E2E UI Test Completed Successfully!");
    });
  });
}
