// lib/features/wallet/providers/wallet_provider.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/wallet_model.dart';


// ── Wallet Stream ───────────────────────────────────────────────────────────────
final walletProvider = StreamProvider<WalletModel?>((ref) {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return Stream.value(null);
  return FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('wallet')
      .doc('balance')
      .snapshots()
      .map((doc) => doc.exists ? WalletModel.fromFirestore(doc) : null);
});

// ── Wallet Notifier ─────────────────────────────────────────────────────────────
class WalletNotifier extends StateNotifier<AsyncValue<void>> {
  final FirebaseFunctions _functions;

  WalletNotifier(this._functions) : super(const AsyncValue.data(null));

  Future<bool> fundWallet({
    required String userId,
    required double amount,
    required String method,
    String? reference,
  }) async {
    state = const AsyncValue.loading();
    try {
      final callable = _functions.httpsCallable('fundWallet');
      await callable.call({
        'userId': userId,
        'amount': amount,
        'method': method,
        'reference': reference ?? 'GTK-${DateTime.now().millisecondsSinceEpoch}',
      });
      state = const AsyncValue.data(null);
      return true;
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      return false;
    }
  }

  Future<bool> withdraw({required String userId, required double amount}) async {
    state = const AsyncValue.loading();
    try {
      final callable = _functions.httpsCallable('withdrawFunds');
      await callable.call({
        'amount': amount,
      });
      state = const AsyncValue.data(null);
      return true;
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      return false;
    }
  }

  Future<bool> generateVaultAccount(String userId) async {
    state = const AsyncValue.loading();
    try {
      final callable = _functions.httpsCallable('createVaultAccount');
      await callable.call();
      state = const AsyncValue.data(null);
      return true;
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      return false;
    }
  }

  /// Called after Paystack client-side charge succeeds.
  /// The Cloud Function verifies the reference with Paystack's API
  /// and atomically credits the wallet — the client can't bypass this.
  Future<bool> verifyPaystackPayment({required String reference}) async {
    state = const AsyncValue.loading();
    try {
      final callable = _functions.httpsCallable('verifyPaystackPayment');
      await callable.call({'reference': reference});
      state = const AsyncValue.data(null);
      return true;
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      return false;
    }
  }
}

final walletNotifierProvider =
    StateNotifierProvider<WalletNotifier, AsyncValue<void>>((ref) {
  return WalletNotifier(
    FirebaseFunctions.instance,
  );
});
