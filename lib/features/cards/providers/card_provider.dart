// lib/features/cards/providers/card_provider.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gatekeepeer/features/cards/models/virtual_card_model.dart';
import 'package:gatekeepeer/features/auth/providers/auth_provider.dart';
import 'package:gatekeepeer/features/accounts/providers/account_provider.dart';
import 'package:gatekeepeer/features/wallet/models/transaction_orchestration_model.dart';

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
      .orderBy('created_at', descending: true)
      .snapshots()
      .map((snap) => snap.docs.map((d) => VirtualCardModel.fromFirestore(d)).toList());
});

// ── Specific Account Cards Stream ──────────────────────────────────────────────
final accountCardsProvider = StreamProvider.family<List<VirtualCardModel>, String>((ref, accountId) {
  return FirebaseFirestore.instance
      .collection('cards')
      .where('account_id', isEqualTo: accountId)
      .orderBy('created_at', descending: true)
      .snapshots()
      .map((snap) => snap.docs.map((d) => VirtualCardModel.fromFirestore(d)).toList());
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
      .orderBy('timestamp', descending: true)
      .limit(100)
      .snapshots()
      .map((snap) => snap.docs.map((d) => TransactionModel.fromFirestore(d)).toList());
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
      .orderBy('timestamp', descending: true)
      .limit(100)
      .snapshots()
      .map((snap) => snap.docs.map((d) => TransactionModel.fromFirestore(d)).toList());
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

  Future<bool> createBridgecard({
    required String cardId,
    required String pin,
    String? cardCurrency,
  }) async {
    state = const AsyncValue.loading();
    try {
      await FirebaseFunctions.instance.httpsCallable('createBridgecard').call({
        'card_id': cardId,
        'pin': pin,
        if (cardCurrency != null) 'card_currency': cardCurrency,
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

  /// Blocks all active cards belonging to the current user's accounts.
  Future<String?> activateKillSwitch(String uid) async {
    state = const AsyncValue.loading();
    try {
      await FirebaseFunctions.instance.httpsCallable('activateKillSwitch').call();
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

  /// Securely proxies Bridgecard's PCI-DSS endpoint to map raw card bytes locally.
  /// Never persists results natively!
  Future<Map<String, dynamic>?> revealCardDetails({required String cardId}) async {
    state = const AsyncValue.loading();
    try {
      final res = await FirebaseFunctions.instance.httpsCallable('revealCardDetails').call({
        'card_id': cardId,
      });
      state = const AsyncValue.data(null);
      if (res.data != null && res.data['success'] == true) {
        return Map<String, dynamic>.from(res.data);
      }
      return null;
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      return null;
    }
  }

  /// Fetches the live 3D Secure OTP tied to the explicit Naira transaction amount.
  Future<String?> getCardOtp({required String cardId, required double amountNgn}) async {
    state = const AsyncValue.loading();
    try {
      final res = await FirebaseFunctions.instance.httpsCallable('getCardOtp').call({
        'card_id': cardId,
        'amount_ngn': amountNgn,
      });
      state = const AsyncValue.data(null);
      if (res.data != null && res.data['success'] == true && res.data['otp'] != null) {
        return res.data['otp'].toString();
      }
      return null;
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      if (e is FirebaseFunctionsException) {
        throw Exception(e.message ?? 'Failed to get OTP');
      }
      throw Exception('Failed to get OTP from the server');
    }
  }
}

// ── Transaction Model (wired to top-level collection schema) ───────────────────
class TransactionModel {
  final String id;
  final String cardId;
  final String accountId;
  final String merchantName;
  final double amount;
  final String status; // approved, declined
  final String? declineReason;
  final DateTime timestamp;

  const TransactionModel({
    required this.id,
    required this.cardId,
    required this.accountId,
    required this.merchantName,
    required this.amount,
    required this.status,
    this.declineReason,
    required this.timestamp,
  });

  factory TransactionModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Firestore stores timestamps as Timestamp objects, not plain ints.
    // Support both forms so prod and emulator both work.
    DateTime parseTimestamp(dynamic raw) {
      if (raw == null) return DateTime.now();
      if (raw is Timestamp) return raw.toDate();
      if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
      return DateTime.now();
    }

    return TransactionModel(
      id: doc.id,
      cardId: data['card_id'] ?? '',
      accountId: data['account_id'] ?? '',
      merchantName: data['merchant_name'] ?? 'Unknown',
      amount: (data['amount'] ?? 0).toDouble(),
      status: data['status'] ?? 'declined',
      declineReason: data['decline_reason'],
      timestamp: parseTimestamp(data['timestamp']),
    );
  }

  bool get isApproved => status == 'approved';
  bool get isDeclined => status == 'declined';
  // Legacy compat getters
  String get merchant => merchantName;
  bool get isBlocked => isDeclined;
  bool get isCredit => false; // All gateway transactions are debits
  String? get blockReason => declineReason;
  String get category => 'Card Transaction';
  String get type => 'debit';
  /// Typed status for badge widgets — maps raw Firestore string to [TxnStatus].
  TxnStatus get txnStatus {
    switch (status.toLowerCase()) {
      case 'approved':    return TxnStatus.success;
      case 'pending':     return TxnStatus.pending;
      case 'processing':  return TxnStatus.processing;
      case 'declined':
      case 'failed':      return TxnStatus.failed;
      default:            return TxnStatus.unknown;
    }
  }
}

final cardNotifierProvider =
    StateNotifierProvider<CardNotifier, AsyncValue<void>>((ref) {
  return CardNotifier();
});
