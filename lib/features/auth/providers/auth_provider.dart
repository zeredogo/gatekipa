// lib/features/auth/providers/auth_provider.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gatekipa/features/auth/models/user_model.dart';
import 'package:gatekipa/features/accounts/providers/account_provider.dart';
import 'package:gatekipa/features/search/providers/search_provider.dart';

import 'package:gatekipa/core/constants/app_constants.dart';

// ── Firebase instances ──────────────────────────────────────────────────────────
final firebaseAuthProvider = Provider((ref) => FirebaseAuth.instance);
final firestoreProvider = Provider((ref) => FirebaseFirestore.instance);

// ── Auth State Stream ───────────────────────────────────────────────────────────
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(firebaseAuthProvider).authStateChanges();
});

// ── Current User Profile ────────────────────────────────────────────────────────
final userProfileProvider = StreamProvider<UserModel?>((ref) {
  final auth = ref.watch(authStateProvider);
  return auth.when(
    data: (user) {
      if (user == null) return Stream.value(null);
      return FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(user.uid)
          .snapshots()
          .map((doc) => doc.exists ? UserModel.fromFirestore(doc) : null);
    },
    loading: () => Stream.value(null),
    error: (_, __) => Stream.value(null),
  );
});

// ── Auth Notifier ───────────────────────────────────────────────────────────────
class AuthNotifier extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  AuthNotifier(this._ref, this._auth, this._db) : super(const AsyncValue.data(null));

  String? _verificationId;

  Future<void> sendOtp({
    required String phoneNumber,
    required void Function(String message) onError,
    required void Function() onCodeSent,
  }) async {
    state = const AsyncValue.loading();
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (credential) async {
        await _signInWithCredential(credential);
      },
      verificationFailed: (e) {
        state = AsyncValue.error(e, StackTrace.current);
        onError(e.message ?? 'Verification failed. Check your number.');
      },
      codeSent: (verificationId, resendToken) {
        _verificationId = verificationId;
        state = const AsyncValue.data(null);
        onCodeSent();
      },
      codeAutoRetrievalTimeout: (verificationId) {
        _verificationId = verificationId;
      },
    );
  }

  Future<bool> verifyOtp(String otp) async {
    if (_verificationId == null) return false;
    try {
      state = const AsyncValue.loading();
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: otp,
      );
      await _signInWithCredential(credential);
      return true;
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      return false;
    }
  }

  Future<void> _signInWithCredential(PhoneAuthCredential credential) async {
    final result = await _auth.signInWithCredential(credential);
    if (result.user != null) {
      await _handleUserLogin(result.user!);
      state = const AsyncValue.data(null);
    }
  }

  String _getFriendlyErrorMessage(String? code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Invalid email or password. Please try again.';
      case 'network-request-failed':
        return 'No internet connection. Please check your network and try again.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'weak-password':
        return 'Your password is too weak. Please use a stronger password.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-disabled':
        return 'This account has been disabled. Please contact support.';
      default:
        return 'Something went wrong. Please try again later.';
    }
  }

  Future<void> signInWithEmail(String email, String password) async {
    state = const AsyncValue.loading();
    try {
      final result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      if (result.user != null) {
        await _handleUserLogin(result.user!);
      }
      state = const AsyncValue.data(null);
    } on FirebaseAuthException catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      throw _getFriendlyErrorMessage(e.code);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      throw 'An unexpected error occurred. Please try again.';
    }
  }

  Future<void> resetPassword(String email) async {
    state = const AsyncValue.loading();
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('requestPasswordReset');
      await callable.call({'email': email});
      state = const AsyncValue.data(null);
    } on FirebaseAuthException catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      throw _getFriendlyErrorMessage(e.code);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      throw 'An unexpected error occurred. Please try again.';
    }
  }

  Future<void> signUpWithEmail(String email, String password,
      {String? firstName, String? lastName, String? phone, String? address,
       String? city, String? addrState, String? postalCode, String? houseNumber}) async {
    state = const AsyncValue.loading();
    try {
      final result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      if (result.user != null) {
        await _handleUserLogin(result.user!,
            firstName: firstName, lastName: lastName, phone: phone, address: address,
            city: city, addrState: addrState, postalCode: postalCode, houseNumber: houseNumber);
      }
      state = const AsyncValue.data(null);
    } on FirebaseAuthException catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      throw _getFriendlyErrorMessage(e.code);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      throw 'An unexpected error occurred. Please try again.';
    }
  }

  Future<void> _handleUserLogin(User user,
      {String? firstName, String? lastName, String? phone, String? address,
       String? city, String? addrState, String? postalCode, String? houseNumber}) async {
    final doc = _db.collection(AppConstants.usersCollection).doc(user.uid);
    // Add a timeout to prevent infinite hanging when fully offline.
    final snap = await doc.get().timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw 'Network timeout while loading your profile. Please check your connection.',
        );
    if (!snap.exists) {
      // New user — create profile. Wallet creation delegates to onUserCreated Cloud Function.
      final profile = UserModel(
        uid: user.uid,
        firstName: firstName,
        lastName: lastName,
        address: address,
        city: city,
        state: addrState,
        postalCode: postalCode,
        houseNumber: houseNumber,
        displayName: (firstName != null && lastName != null)
            ? '$firstName $lastName'
            : null,
        phoneNumber: phone ?? user.phoneNumber,
        email: user.email,
        kycStatus: 'pending',
        isPremium: false,
        createdAt: DateTime.now(),
        lastLoginAt: DateTime.now(),
      );
      await doc.set(profile.toFirestore());
    } else {
      await doc.update({'lastLoginAt': FieldValue.serverTimestamp()});
    }
  }

  Future<void> updateProfile({
    required String uid,
    required Map<String, dynamic> data,
  }) async {
    if (data.containsKey('displayName')) {
      try {
        await _auth.currentUser?.updateDisplayName(data['displayName']);
      } catch (_) {}
    }
    
    // SECURITY HARDENING: Prevents client-side payload injection.
    // Sensitive fields must be set via dedicated methods below.
    final safeData = Map<String, dynamic>.from(data)
      ..remove('kycStatus')
      ..remove('isPremium')
      ..remove('hasBvn')
      ..remove('createdAt');
      
    await _db.collection(AppConstants.usersCollection).doc(uid).set(safeData, SetOptions(merge: true));
  }


  /// Saves the current user's UID so the lock-and-biometric flow can reference it.
  Future<void> _saveLastUserId(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_user_id', uid);
  }

  /// Full sign-out: destroys the Firebase session completely.
  /// Biometric will NOT be offered on the next launch because currentUser is null
  /// and we clear the last_user_id.
  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('last_user_id'); // clear any lock-mode data
    await _auth.signOut();
    _ref.invalidate(activeAccountIdProvider);
    _ref.invalidate(searchQueryProvider);
  }

  /// Lock the app — keeps the Firebase session alive so biometric can unlock
  /// directly to the dashboard without re-entering credentials.
  ///
  /// How it works:
  ///   1. We save `last_user_id` so the splash screen knows who last used the app.
  ///   2. We do NOT call _auth.signOut() — Firebase session is preserved on disk.
  ///   3. On next launch, splash finds `currentUser != null`, sees biometrics enabled,
  ///      and prompts. On success → straight to dashboard.
  Future<void> lockApp() async {
    final uid = _auth.currentUser?.uid;
    if (uid != null) await _saveLastUserId(uid);
    // Invalidate Riverpod state so UI clears — but Firebase session is kept.
    _ref.invalidate(activeAccountIdProvider);
    _ref.invalidate(searchQueryProvider);
  }
}

final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, AsyncValue<void>>((ref) {
  return AuthNotifier(
    ref,
    ref.watch(firebaseAuthProvider),
    ref.watch(firestoreProvider),
  );
});
