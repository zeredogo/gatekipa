// lib/features/cards/providers/card_provider.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gatekipa/features/cards/models/virtual_card_model.dart';
import 'package:gatekipa/features/auth/providers/auth_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:gatekipa/features/accounts/providers/account_provider.dart';
import 'package:gatekipa/features/wallet/models/transaction_orchestration_model.dart';

// ── Rules Stream for a single card ─────────────────────────────────────────────
final cardRulesProvider = StreamProvider.autoDispose.family<List<CardRule>, String>((ref, cardId) {
  return FirebaseFirestore.instance
      .collection('rules')
      .where('card_id', isEqualTo: cardId)
      .snapshots()
      .map((snap) => snap.docs.map((d) => CardRule.fromFirestore(d)).toList());
});

final cardsProvider = StreamProvider<List<VirtualCardModel>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value([]);

  final accountsAsync = ref.watch(accountsStreamProvider);
  final accounts = accountsAsync.valueOrNull ?? [];

  // Firestore whereIn supports up to 30 values
  final accountIdsSet = accounts.map((a) => a.id).toSet();
  accountIdsSet.add(user.uid); // Inject personal user ID as a fallback account_id
  final accountIds = accountIdsSet.take(30).toList();

  return FirebaseFirestore.instance
      .collection('cards')
      .where('account_id', whereIn: accountIds)
      .snapshots()
      .map((snap) {
        final docs = snap.docs.map((d) => VirtualCardModel.fromFirestore(d)).toList();
        docs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return docs;
      });
});

// ── Specific Account Cards Stream ──────────────────────────────────────────────
final accountCardsProvider = StreamProvider.family<List<VirtualCardModel>, String>((ref, accountId) {
  return FirebaseFirestore.instance
      .collection('cards')
      .where('account_id', isEqualTo: accountId)
      .snapshots()
      .map((snap) {
        final docs = snap.docs.map((d) => VirtualCardModel.fromFirestore(d)).toList();
        docs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return docs;
      });
});

// ── Card Count Stream by Account ID ────────────────────────────────────────────
final cardCountProvider = StreamProvider.family<int, String>((ref, accountId) {
  return FirebaseFirestore.instance
      .collection('cards')
      .where('account_id', isEqualTo: accountId)
      .snapshots()
      .map((snap) => snap.docs.length);
});

// ── Specific Account Transactions Stream ───────────────────────────────────────
final accountTransactionsProvider = StreamProvider.family<List<TransactionModel>, String>((ref, accountId) {
  return FirebaseFirestore.instance
      .collection('transactions')
      .where('account_id', isEqualTo: accountId)
      .snapshots()
      .map((snap) {
        final docs = snap.docs.map((d) => TransactionModel.fromFirestore(d)).toList();
        docs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        return docs.take(100).toList();
      });
});

// ── Transactions Provider — combines ALL accounts the user has access to ───────
final transactionsProvider = StreamProvider<List<TransactionModel>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value([]);

  final accountsAsync = ref.watch(accountsStreamProvider);
  final accounts = accountsAsync.valueOrNull ?? [];

  // Firestore whereIn supports up to 30 values
  final accountIdsSet = accounts.map((a) => a.id).toSet();
  accountIdsSet.add(user.uid); // Inject personal user ID as a fallback account_id
  final accountIds = accountIdsSet.take(30).toList();

  return FirebaseFirestore.instance
      .collection('transactions')
      .where('account_id', whereIn: accountIds)
      .snapshots()
      .map((snap) {
        final docs = snap.docs.map((d) => TransactionModel.fromFirestore(d)).toList();
        docs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        return docs.take(100).toList();
      });
});

// ── Active Cards Only ───────────────────────────────────────────────────────────
final activeCardsProvider = Provider<List<VirtualCardModel>>((ref) {
  final cards = ref.watch(cardsProvider);
  return cards.when(
    data: (list) => list.where((c) => c.isActive).toList(),
    loading: () => [],
    error: (_, __) => [],
  );
});

// ── Card Notifier ───────────────────────────────────────────────────────────────
class CardNotifier extends StateNotifier<AsyncValue<void>> {
  CardNotifier() : super(const AsyncValue.data(null));

  Future<bool> registerCardholder({
    required String firstName,
    required String lastName,
    required String phone,
    required String address,
    required String city,
    required String regionState,
    required String postalCode,
    required String houseNumber,
    String? idType,
    String? idNo,
    String? idImage,
    String? selfieImage,
    String? country,
  }) async {
    state = const AsyncValue.loading();
    try {
      await FirebaseFunctions.instance.httpsCallable('registerCardholder').call({
        'first_name': firstName,
        'last_name': lastName,
        'phone': phone,
        'address': address,
        'city': city,
        'state': regionState,
        'postal_code': postalCode,
        'house_no': houseNumber,
        if (idType != null) 'id_type': idType,
        if (idNo != null) 'id_no': idNo,
        if (idImage != null) 'id_image': idImage,
        if (selfieImage != null) 'selfie_image': selfieImage,
        if (country != null) 'country': country,
      });
      state = const AsyncValue.data(null);
      return true;
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      return false;
    }
  }

  Future<String?> createCard({
    String? accountId,
    required String name,
    required bool isTrial,
    String category = 'personal',
    double balanceLimit = 50000,
    String currency = 'NGN',
  }) async {
    state = const AsyncValue.loading();
    try {
      final result = await FirebaseFunctions.instance.httpsCallable('createVirtualCard').call({
        if (accountId != null) 'account_id': accountId,
        'name': name,
        'is_trial': isTrial,
        'category': category,
        'balance_limit': balanceLimit,
        'currency': currency,
      });
      state = const AsyncValue.data(null);
      final dataMap = result.data as Map<dynamic, dynamic>;
      return dataMap['cardId']?.toString();
    } catch (e) {
      state = AsyncValue.error(e.toString(), StackTrace.current);
      return null;
    }
  }


  Future<bool> createSudoCard({
    required String cardId,
    required String pin,
  }) async {
    state = const AsyncValue.loading();
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');
      
      const storage = FlutterSecureStorage();
      final secureKey = '${user.uid}_transaction_pin';
      final transactionPin = await storage.read(key: secureKey);
      
      if (transactionPin == null || transactionPin.isEmpty) {
        throw Exception("No Transaction PIN configured. Please set one up in Profile.");
      }

      await FirebaseFunctions.instance.httpsCallable('createSudoCard').call({
        'card_id': cardId,
        'pin': pin,
        'transactionPin': transactionPin,
      });
      state = const AsyncValue.data(null);
      return true;
    } catch (e) {
      state = AsyncValue.error(e.toString(), StackTrace.current);
      return false;
    }
  }

  Future<bool> updateCardStatus({
    required String cardId,
    required String status,
  }) async {
    state = const AsyncValue.loading();
    try {
      await FirebaseFunctions.instance.httpsCallable('toggleCardStatus').call({
        'card_id': cardId,
        'status': status,
      });
      state = const AsyncValue.data(null);
      return true;
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      return false;
    }
  }

  Future<bool> renameCard({
    required String cardId,
    required String newName,
  }) async {
    state = const AsyncValue.loading();
    try {
      await FirebaseFunctions.instance.httpsCallable('renameCard').call({
        'card_id': cardId,
        'new_name': newName.trim(),
      });
      state = const AsyncValue.data(null);
      return true;
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      return false;
    }
  }

  Future<bool> createCardRule({
    required String cardId,
    required String type,
    required String subType,
    required dynamic value,
  }) async {
    state = const AsyncValue.loading();
    try {
      await FirebaseFunctions.instance.httpsCallable('createRule').call({
        'card_id': cardId,
        'type': type,
        'sub_type': subType,
        'value': value,
      });
      state = const AsyncValue.data(null);
      return true;
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      return false;
    }
  }

  Future<bool> deleteCardRule({required String ruleId}) async {
    state = const AsyncValue.loading();
    try {
      await FirebaseFunctions.instance.httpsCallable('deleteRule').call({
        'rule_id': ruleId,
      });
      state = const AsyncValue.data(null);
      return true;
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      return false;
    }
  }

  /// Freezes all active cards belonging to the current user's accounts.
  Future<String?> freezeAllCards(String uid) async {
    state = const AsyncValue.loading();
    try {
      await FirebaseFunctions.instance.httpsCallable('freezeAllCards').call();
      state = const AsyncValue.data(null);
      return null;
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      if (e is FirebaseFunctionsException) {
        return e.message;
      }
      return 'An unexpected error occurred. Please try again.';
    }
  }

  /// Fetches the Secure Proxy Token for PCI-Compliant card display.
  /// NOTE: This token must be passed to the Sudo Native SDK or Webview to display the card details natively.
  Future<Map<String, dynamic>?> revealCardDetails({required String cardId}) async {
    state = const AsyncValue.loading();
    try {
      final res = await FirebaseFunctions.instance.httpsCallable('revealCardDetails').call({
        'card_id': cardId,
      });
      state = const AsyncValue.data(null);
      if (res.data != null && res.data['success'] == true) {
        return {
          'success': true,
          'token': res.data['token'], // Use this token with Sudo Secure Proxy Show SDK
          // TODO: Integrate Sudo Cloud Card SDK for Flutter using this token
        };
      }
      return null;
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      return null;
    }
  }


}

// ── Transaction Model (wired to top-level collection schema) ───────────────────
class TransactionModel {
  final String id;
  final String cardId;
  final String accountId;
  final String userId;
  final String merchantName;
  final double amount;
  final String status; // approved, declined, DECLINED, reserved, settled
  final String? declineReason;
  final DateTime timestamp;
  final String source;          // card_charge | wallet_funding | card_funding | fee | refund | sudo_jit_auth
  final String? providerReference; // providerRef / sudo_event_id
  final String rawType;         // credit | debit (from ledger entries)

  const TransactionModel({
    required this.id,
    required this.cardId,
    required this.accountId,
    required this.userId,
    required this.merchantName,
    required this.amount,
    required this.status,
    this.declineReason,
    required this.timestamp,
    required this.source,
    this.providerReference,
    required this.rawType,
  });

  factory TransactionModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    DateTime parseTimestamp(dynamic raw) {
      if (raw == null) return DateTime.now();
      if (raw is Timestamp) return raw.toDate();
      if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
      return DateTime.now();
    }

    // ── CRITICAL FIX: backend writes `created_at`, not `timestamp` ──────
    final ts = data['created_at'] ?? data['timestamp'];

    final source = data['source'] as String? ?? '';
    final rawType = data['type'] as String? ?? 'debit';

    // Provider reference: check all possible field names
    final providerRef = data['providerRef'] as String?
        ?? data['sudo_event_id'] as String?
        ?? data['paystackRef'] as String?
        ?? data['reference'] as String?;

    return TransactionModel(
      id: doc.id,
      cardId: data['card_id'] as String? ?? '',
      accountId: data['account_id'] as String? ?? '',
      userId: data['user_id'] as String? ?? '',
      merchantName: data['merchant_name'] as String? ?? 'Unknown',
      amount: (num.tryParse(data['amount']?.toString() ?? '0') ?? 0).toDouble(),
      status: data['status'] as String? ?? 'unknown',
      declineReason: data['decline_reason'] as String?,
      timestamp: parseTimestamp(ts),
      source: source,
      providerReference: providerRef,
      rawType: rawType,
    );
  }

  /// True when this entry represents money coming IN to the wallet.
  bool get isCredit =>
      rawType == 'credit' ||
      source == 'wallet_funding' ||
      source == 'paystack' ||
      source == 'sudo_refund' ||
      source == 'ghost_card_auto_refund' ||
      status == 'refund';

  bool get isApproved =>
      status == 'approved' || status == 'success' || status == 'settled' || status == 'APPROVED';

  bool get isDeclined =>
      status == 'declined' || status == 'DECLINED' || status == 'failed';

  bool get isPending =>
      status == 'reserved' || status == 'pending' || status == 'processing';

  // Legacy compat getters
  String get merchant => merchantName;
  bool get isBlocked => isDeclined;
  String? get blockReason => declineReason;
  String get category => displayType;
  String get type => rawType;

  /// Human-readable transaction type for display.
  String get displayType {
    switch (source) {
      case 'wallet_funding':
      case 'paystack':
        return 'Wallet Top-Up';
      case 'wallet_to_card':
      case 'card_funding':
        return 'Card Funding';
      case 'card_transaction_fee':
        return 'Transaction Fee';
      case 'sudo_refund':
      case 'refund':
        return 'Refund';
      case 'ghost_card_auto_refund':
        return 'Refund (Card Failed)';
      case 'sudo_jit_auth':
        return status == 'reserved' ? 'Authorization Hold' : 'Card Charge';
      case 'card_charge':
        return 'Card Charge';
      case 'admin':
        return 'Admin Adjustment';
      default:
        return isCredit ? 'Credit' : 'Debit';
    }
  }

  /// Typed status for badge widgets — maps raw Firestore string to [TxnStatus].
  TxnStatus get txnStatus {
    if (isApproved) return TxnStatus.success;
    if (isDeclined) return TxnStatus.failed;
    if (isPending)  return TxnStatus.pending;
    switch (status.toLowerCase()) {
      case 'processing': return TxnStatus.processing;
      default:           return TxnStatus.unknown;
    }
  }
}

class FreezeLogModel {
  final String id;
  final String cardId;
  final String userId;
  final String action;
  final DateTime timestamp;
  final String? triggeredBy;
  final String? context;

  const FreezeLogModel({
    required this.id,
    required this.cardId,
    required this.userId,
    required this.action,
    required this.timestamp,
    this.triggeredBy,
    this.context,
  });

  factory FreezeLogModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return FreezeLogModel(
      id: doc.id,
      cardId: data['card_id'] as String? ?? '',
      userId: data['user_id'] as String? ?? '',
      action: data['action'] as String? ?? 'frozen',
      timestamp: data['timestamp'] is Timestamp 
          ? (data['timestamp'] as Timestamp).toDate() 
          : DateTime.now(),
      triggeredBy: data['triggered_by'] as String?,
      context: data['context'] as String?,
    );
  }
}

final freezeLogsProvider = StreamProvider.autoDispose.family<List<FreezeLogModel>, String>((ref, cardId) {
  return FirebaseFirestore.instance
      .collection('card_freeze_logs')
      .where('card_id', isEqualTo: cardId)
      .orderBy('timestamp', descending: true)
      .snapshots()
      .map((snap) => snap.docs.map((d) => FreezeLogModel.fromFirestore(d)).toList());
});

final cardNotifierProvider =
    StateNotifierProvider<CardNotifier, AsyncValue<void>>((ref) {
  return CardNotifier();
});
