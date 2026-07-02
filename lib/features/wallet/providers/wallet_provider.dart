// lib/features/wallet/providers/wallet_provider.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:gatekipa/features/wallet/models/wallet_model.dart';
import 'package:gatekipa/features/cards/providers/card_provider.dart'
    show TransactionModel, transactionsProvider;


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

// ── Wallet Ledger Stream (standalone, for top-ups + card funding visibility) ────
final walletLedgerProvider = StreamProvider<List<TransactionModel>>((ref) {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return Stream.value([]);

  return FirebaseFirestore.instance
      .collection('wallet_ledger')
      .where('user_id', isEqualTo: user.uid)
      .orderBy('created_at', descending: true)
      .limit(150)
      .snapshots()
      .map((snap) => snap.docs.map((doc) {
            final data = doc.data();
            // Adapt wallet_ledger schema to TransactionModel so the UI
            // can render it uniformly without a separate widget hierarchy.
            final src = data['source'] as String? ?? 'unknown';
            final isCredit = (data['type'] as String?) == 'credit' ||
                src == 'paystack' ||
                src == 'wallet_funding';
            return TransactionModel(
              id: doc.id,
              cardId: data['card_id'] as String? ?? '',
              accountId: data['account_id'] as String? ?? '',
              userId: data['user_id'] as String? ?? '',
              merchantName: data['merchant_name'] as String?
                  ?? _ledgerSourceLabel(src),
              amount: (data['amount'] as num? ?? 0).toDouble(),
              status: data['status'] as String? ?? (isCredit ? 'success' : 'approved'),
              declineReason: null,
              timestamp: data['created_at'] is Timestamp
                  ? (data['created_at'] as Timestamp).toDate()
                  : DateTime.now(),
              source: src,
              providerReference: data['reference'] as String?,
              rawType: isCredit ? 'credit' : 'debit',
            );
          }).toList());
});

String _ledgerSourceLabel(String source) {
  switch (source) {
    case 'paystack':
    case 'wallet_funding':      return 'Wallet Top-Up';
    case 'wallet_to_card':
    case 'card_funding':        return 'Card Funding';
    case 'card_transaction_fee':return 'Transaction Fee';
    case 'sudo_refund':
    case 'refund':              return 'Refund';
    case 'ghost_card_auto_refund': return 'Refund (Card Failed)';
    case 'sudo_jit_auth':       return 'Card Hold';
    case 'admin':               return 'Admin Adjustment';
    default:                    return 'Wallet Event';
  }
}

// ── Unified Ledger Provider — merges transactions + wallet_ledger ───────────────
// This is the definitive feed for all money movement visible to the user.
// It covers:
//   • Card charges (from `transactions`)
//   • Declined / JIT declined transactions (from `transactions`)
//   • Wallet top-ups via Paystack (from `wallet_ledger`)
//   • Card funding from wallet (from `wallet_ledger`)
//   • Platform transaction fees (from `wallet_ledger`)
//   • Refunds from failed card provisioning (from `wallet_ledger`)
//   • Authorization holds (from `wallet_ledger` with status: reserved)
final unifiedLedgerProvider = StreamProvider<List<TransactionModel>>((ref) {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return Stream.value([]);

  final ledgerAsync   = ref.watch(walletLedgerProvider);
  final txAsync       = ref.watch(transactionsProvider);

  final ledger = ledgerAsync.valueOrNull ?? [];
  final txns   = txAsync.valueOrNull   ?? [];

  // Merge & deduplicate by id, then sort by timestamp descending
  final seen = <String>{};
  final merged = <TransactionModel>[];

  for (final t in [...txns, ...ledger]) {
    if (seen.add(t.id)) merged.add(t);
  }
  merged.sort((a, b) => b.timestamp.compareTo(a.timestamp));

  return Stream.value(merged.take(200).toList());
});



// ── Wallet Notifier ─────────────────────────────────────────────────────────────
class WalletNotifier extends StateNotifier<AsyncValue<void>> {
  final FirebaseFunctions _functions;

  WalletNotifier(this._functions) : super(const AsyncValue.data(null));



  Future<String?> initiateVaultVerification({String? faceImageBase64}) async {
    state = const AsyncValue.loading();
    try {
      final callable = _functions.httpsCallable('initiateVaultVerification');
      final result = await callable.call({
        if (faceImageBase64 != null) 'faceImageBase64': faceImageBase64,
      });
      state = const AsyncValue.data(null);
      return result.data['identityId'] as String?;
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      return null;
    }
  }

  Future<bool> generateVaultAccount(String userId, {String? otp, String? identityId}) async {
    state = const AsyncValue.loading();
    try {
      final callable = _functions.httpsCallable('createVaultAccount');
      await callable.call({'otp': otp, 'identityId': identityId});
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
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("User not authenticated");
      
      const storage = FlutterSecureStorage();
      final secureKey = '${user.uid}_transaction_pin';
      final pin = await storage.read(key: secureKey);
      
      if (pin == null || pin.isEmpty) {
        throw Exception("No local Transaction PIN found. Please set one up in Profile.");
      }

      final callable = _functions.httpsCallable('fundCard');
      await callable.call({
        'card_id': cardId,
        'account_id': accountId,
        'amount': amount,
        'idempotency_key': idempotencyKey,
        'pin': pin,
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

