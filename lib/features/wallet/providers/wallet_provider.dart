// lib/features/wallet/providers/wallet_provider.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gatekeepeer/features/wallet/models/wallet_model.dart';


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

  /// DEPRECATED — This method is intentionally unusable.
  ///
  /// The backend [fundWallet] Cloud Function immediately throws a
  /// permission-denied error by design.
  ///
  /// The CORRECT wallet top-up flow is:
  ///   1. Show Paystack checkout (see [AddFundsScreen])
  ///   2. After user completes payment, call [verifyPaystackPayment]
  ///
  /// Never call this method.
  @Deprecated('Use verifyPaystackPayment() after Paystack checkout instead.')
  Future<bool> fundWallet({
    required String userId,
    required double amount,
    required String method,
    String? reference,
  }) async {
    throw UnsupportedError(
      'fundWallet is disabled. Use the Paystack checkout flow in AddFundsScreen '
      'and call verifyPaystackPayment() to credit the wallet.',
    );
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

  /// Biometric-gated wallet-to-card funding.
  ///
  /// Routes through the hardened `fundCard` Cloud Function which calls
  /// `processTransactionInternal`. This is the ONLY correct path for
  /// debiting the wallet and crediting a virtual card.
  ///
  /// Throws [SystemLockedDownException] if the system is in LOCKDOWN mode
  /// (checked client-side first; the server enforces this independently).
  Future<bool> fundCard({
    required String cardId,
    required String accountId,
    required double amount,
    required String idempotencyKey,
  }) async {
    state = const AsyncValue.loading();
    try {
      final callable = _functions.httpsCallable('fundCard');
      await callable.call({
        'card_id': cardId,
        'account_id': accountId,
        'amount': amount,
        'idempotency_key': idempotencyKey,
      });
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

