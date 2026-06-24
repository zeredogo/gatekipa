import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gatekipa/main.dart' as app;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:gatekipa/firebase_options.dart';
import 'package:gatekipa/app.dart';
import 'package:gatekipa/features/auth/screens/splash_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Gatekipa E2E Plan Selection Test', () {
    testWidgets('Sign Up and Select a Subscription Plan', (tester) async {
      


      try {
        if (Firebase.apps.isEmpty) {
            await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
        }
      } catch (e) {
        debugPrint("Error clearing state: $e");
      }

      runApp(const ProviderScope(child: GatekipaApp()));
      
      // Wait for runApp to be called and GatekipaApp to appear
      int waitLimit = 0;
      while (find.byType(GatekipaApp).evaluate().isEmpty && waitLimit < 100) {
        await tester.pump(const Duration(milliseconds: 100));
        waitLimit++;
      }
      
      // Wait for SplashScreen to disappear
      waitLimit = 0;
      while (find.byType(SplashScreen).evaluate().isNotEmpty && waitLimit < 100) {
        await tester.pump(const Duration(milliseconds: 200));
        waitLimit++;
      }

      await tester.pump(const Duration(seconds: 2));

      bool isLoggedOut = tester.any(find.byType(TextField)) || tester.any(find.byType(TextFormField));
      
      if (!isLoggedOut) {
        // Might be on Onboarding
        final signInSkip = find.text('Sign In');
        if (tester.any(signInSkip)) {
            debugPrint("🚀 Onboarding detected. Skipping to Login...");
            await tester.tap(signInSkip.first);
            await tester.pump(const Duration(seconds: 2));
            isLoggedOut = true;
        } else {
            debugPrint("🔐 App is logged in. Navigating to Profile to log out...");
            
            final appBarGestureDetectors = find.descendant(
              of: find.byType(SliverAppBar),
              matching: find.byType(GestureDetector),
            );
            
            if (tester.any(appBarGestureDetectors)) {
                await tester.tap(appBarGestureDetectors.first);
                await tester.pump(const Duration(seconds: 2));
                
                final logoutButton = find.textContaining(RegExp(r'Logout|Sign Out', caseSensitive: false));
                if (tester.any(logoutButton)) {
                    await tester.dragUntilVisible(
                        logoutButton,
                        find.byType(SingleChildScrollView),
                        const Offset(0, -300),
                    );
                    await tester.tap(logoutButton.first);
                    await tester.pump(const Duration(seconds: 5));
                }
            } else {
                debugPrint("⚠️ Could not find SliverAppBar GestureDetector. Trying to clear text...");
                final texts = tester.widgetList<Text>(find.byType(Text));
                for (var t in texts) {
                   debugPrint("SCREEN TEXT: ${t.data}");
                }
            }
            
            isLoggedOut = tester.any(find.byType(TextField)) || tester.any(find.byType(TextFormField));
        }
      }

      if (isLoggedOut) {
        debugPrint("🔐 App is on Login Screen. Attempting to log in...");
        
        final textFields = find.byType(TextField);
        final textFormFields = find.byType(TextFormField);
        
        if (tester.any(textFields) && textFields.evaluate().length >= 2) {
          await tester.enterText(textFields.at(0), 'plan_tester@gatekipa.app');
          await tester.enterText(textFields.at(1), 'Password123!');
          await tester.pump(const Duration(seconds: 2));
        } else if (tester.any(textFormFields) && textFormFields.evaluate().length >= 2) {
          await tester.enterText(textFormFields.at(0), 'plan_tester@gatekipa.app');
          await tester.enterText(textFormFields.at(1), 'Password123!');
          await tester.pump(const Duration(seconds: 2));
        }
        
        final loginButton = find.byType(FilledButton);
        final elevatedButton = find.byType(ElevatedButton);
        
        if (tester.any(loginButton)) {
          await tester.tap(loginButton.first);
        } else if (tester.any(elevatedButton)) {
          await tester.tap(elevatedButton.first);
        } else {
          final signInText = find.text('Sign In');
          if (tester.any(signInText)) await tester.tap(signInText.first);
        }
        
        // Wait for login to finish and Dashboard to appear (up to 20 seconds)
        int loginWait = 0;
        while (!tester.any(find.byIcon(Icons.credit_card_rounded)) && 
               !tester.any(find.text('Cards')) && 
               loginWait < 100) {
          await tester.pump(const Duration(milliseconds: 200));
          loginWait++;
        }
      } else {
        debugPrint("✅ App is still logged in or stuck.");
      }
      
      // Email Verification Screen might appear
      debugPrint("📧 Checking for Email Verification screen...");
      int emailWait = 0;
      while (tester.any(find.text("I've Verified My Email")) && emailWait < 20) {
        debugPrint("📧 Found Email Verification screen. Tapping verified...");
        await tester.tap(find.text("I've Verified My Email"));
        await tester.pump(const Duration(seconds: 1));
        emailWait++;
      }

      // Onboarding screens might appear here. We need to skip them.
      debugPrint("🚀 Looking for Onboarding Get Started or skipping...");
      final getStarted = find.textContaining('Get Started');
      if (tester.any(getStarted)) {
          await tester.tap(getStarted);
          await tester.pump(const Duration(seconds: 2));
      }

      // Now we should be on Dashboard. Navigate to Cards Tab.
      debugPrint("🧭 Navigating to Cards Menu...");
      var cardsTab = find.byIcon(Icons.credit_card_rounded);
      if (!tester.any(cardsTab)) {
        cardsTab = find.text('Cards');
      }
      
      if (tester.any(cardsTab)) {
        await tester.tap(cardsTab.first);
        await tester.pump(const Duration(seconds: 2));
      } else {
        debugPrint("⚠️ Could not find Cards tab in bottom nav. Dumping text:");
        final texts = tester.widgetList<Text>(find.byType(Text));
        for (var t in texts) {
           debugPrint("SCREEN TEXT: ${t.data}");
        }
      }

      // Dismiss any tooltips (like "Fund your Vault" -> "SKIP")
      debugPrint("🔍 Checking for tooltips to dismiss...");
      final skipText = find.text('SKIP');
      if (tester.any(skipText)) {
          debugPrint("👉 Found SKIP. Dismissing tooltip...");
          await tester.tap(skipText.first);
          await tester.pump(const Duration(seconds: 1));
      }

      // Click Add Card or Create First Card
      debugPrint("💳 Tapping Create Card...");
      final addCardBtn = find.byIcon(Icons.add_rounded);
      final createFirstBtn = find.text('Create First Card');
      final fallbackAddBtn = find.byIcon(Icons.add);
      
      if (tester.any(createFirstBtn)) {
          // ensure it's visible by ensuring no other tap blockers
          await tester.tap(createFirstBtn.first, warnIfMissed: false);
      } else if (tester.any(addCardBtn)) {
          await tester.tap(addCardBtn.first);
      } else if (tester.any(fallbackAddBtn)) {
          await tester.tap(fallbackAddBtn.first);
      } else {
          fail("Could not find Add Card button.");
      }
      await tester.pump(const Duration(seconds: 2));

      // NEW LOGIC: We are now on CardCreationScreen!
      debugPrint("📝 Filling Card Creation form to trigger Plan Selection...");
      
      // Inject PIN to bypass the PIN warning
      final auth = FirebaseAuth.instance;
      if (auth.currentUser != null) {
          const storage = FlutterSecureStorage();
          await storage.write(key: '${auth.currentUser!.uid}_transaction_pin', value: '1234');
          debugPrint("🔑 Injected mock transaction PIN.");
      }

      // Fill Card Name
      final cardNameField = find.widgetWithText(TextFormField, 'e.g. Hosting, Netflix, SaaS Tool');
      if (tester.any(cardNameField)) {
          await tester.enterText(cardNameField.first, 'Test Sub Card');
      }

      // Fill Billing Address
      final addressField = find.widgetWithText(TextFormField, 'Full Street Address (e.g., 123 Main St)');
      if (tester.any(addressField)) {
          await tester.enterText(addressField.first, '123 Test Street');
      }

      final cityField = find.widgetWithText(TextFormField, 'City');
      if (tester.any(cityField)) {
          await tester.enterText(cityField.first, 'Test City');
      }

      // State is a dropdown in Nigeria
      final stateText = find.text('State');
      if (tester.any(stateText)) {
          await tester.ensureVisible(stateText.first);
          await tester.tap(stateText.first, warnIfMissed: false);
          await tester.pump(const Duration(seconds: 1));
          
          final lagosOption = find.text('Lagos');
          if (tester.any(lagosOption)) {
             await tester.tap(lagosOption.last, warnIfMissed: false);
             await tester.pump(const Duration(seconds: 1));
          } else {
             // Fallback: tap the first dropdown menu item
             await tester.tap(find.text('Abia').last, warnIfMissed: false);
             await tester.pump(const Duration(seconds: 1));
          }
      } else {
          final stateField = find.widgetWithText(TextFormField, 'State');
          if (tester.any(stateField)) {
              await tester.enterText(stateField.first, 'Test State');
          }
      }
      
      final zipField = find.widgetWithText(TextFormField, 'Zip Code');
      if (tester.any(zipField)) {
          await tester.enterText(zipField.first, '100001');
      }

      final houseField = find.widgetWithText(TextFormField, 'House/Apartment N°');
      if (tester.any(houseField)) {
          await tester.enterText(houseField.first, '1A');
      }

      // Tap the Create Card button at the bottom of the form
      // Note: There's a title "Create Card" and a button "Create Card"
      debugPrint("🛒 Tapping Create Card form submission button...");
      final submitBtn = find.widgetWithText(FilledButton, 'Create Card');
      if (tester.any(submitBtn)) {
          // Scroll it into view if needed
          await tester.ensureVisible(submitBtn.first);
          await tester.tap(submitBtn.first, warnIfMissed: false);
      } else {
          // Fallback if the button uses a slightly different widget
          final elevatedSubmit = find.widgetWithText(ElevatedButton, 'Create Card');
          if (tester.any(elevatedSubmit)) {
              await tester.ensureVisible(elevatedSubmit.first);
              await tester.tap(elevatedSubmit.first, warnIfMissed: false);
          } else {
              // Try finding the text and tapping its parent
              final createTexts = find.text('Create Card');
              if (createTexts.evaluate().length > 1) {
                  await tester.ensureVisible(createTexts.last);
                  await tester.tap(createTexts.last, warnIfMissed: false);
              }
          }
      }
      
      await tester.pump(const Duration(seconds: 2));

      // Wait for PIN Setup prompt if it appears, or plan selection
      debugPrint("📋 Waiting for Plan Selection Sheet...");
      
      // If we need a transaction PIN, the app prompts for it. Let's see if "Select a Plan" appears.
      final selectPlanText = find.text('Select a Plan');
      
      if (!tester.any(selectPlanText)) {
          // If there is a PIN toast, we might have to set up a PIN.
          debugPrint("⚠️ 'Select a Plan' sheet not found. Checking if PIN is required.");
          final texts = tester.widgetList<Text>(find.byType(Text));
          for (var t in texts) {
             debugPrint("SCREEN TEXT: ${t.data}");
          }
          fail("Select a Plan sheet did not appear.");
      } else {
          debugPrint("✅ 'Select a Plan' sheet appeared!");
          
          final sentinelPrime = find.text('Sentinel Prime');
          expect(sentinelPrime, findsOneWidget, reason: 'Sentinel Prime plan should be visible');
          
          await tester.tap(sentinelPrime);
          await tester.pump(const Duration(seconds: 2));
          
          debugPrint("✅ Tapped Sentinel Prime.");
          
          final confirmSheet = find.textContaining(RegExp('Confirm', caseSensitive: false));
          if (tester.any(confirmSheet)) {
              debugPrint("✅ Confirmation sheet appeared.");
          } else {
              final createAccountSheet = find.text('Create Account');
              expect(createAccountSheet, findsWidgets, reason: 'Create Account sheet should appear');
              debugPrint("✅ Create Account sheet appeared.");
          }
      }
    });
  });
}
