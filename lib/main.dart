import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gatekipa/app.dart';
import 'package:gatekipa/firebase_options.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Status bar style
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  // Portrait only
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  
  // App Check Initialization
  await FirebaseAppCheck.instance.activate(
    androidProvider: AndroidProvider.playIntegrity,
    appleProvider: AppleProvider.appAttest,
    // Web is only active in the web build — the site key must be set before publishing.
    webProvider: kIsWeb ? ReCaptchaV3Provider('recaptcha-v3-site-key') : null,
  );

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await FirebaseMessaging.instance.requestPermission();

  // Save FCM token whenever it changes (initial + refreshed)
  _initFcmTokenSave();

  runApp(const ProviderScope(child: GatekipaApp()));
}

/// Saves the FCM token to Firestore under the authenticated user's profile.
/// Called on app boot and whenever the token refreshes.
void _initFcmTokenSave() {
  Future<void> saveToken(String token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .set({'fcm_token': token}, SetOptions(merge: true));
  }

  // Save immediately if we have a token
  FirebaseMessaging.instance.getToken().then((token) {
    if (token != null) saveToken(token);
  });

  // Keep it updated when the token rotates
  FirebaseMessaging.instance.onTokenRefresh.listen(saveToken);

  // Foreground notification display
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    // When the app is open, FCM suppresses the system notification.
    // The Firestore listener in NotificationScreen already shows the badge.
    // Optionally show an in-app snackbar here if needed.
    debugPrint('[FCM] Foreground message: ${message.notification?.title}');
  });
}

