// lib/features/cards/providers/card_provider.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/virtual_card_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../../accounts/providers/account_provider.dart';

// ── Rules Stream for a single card ─────────────────────────────────────────────
final cardRulesProvider = StreamProvider.family<List<CardRule>, String>((ref, cardId) {
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
  if (accounts.isEmpty) return Stream.value([]);

  final accountIds = accounts.map((a) => a.id).take(10).toList();

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
  if (accounts.isEmpty) return Stream.value([]);

  final accountIds = accounts.map((a) => a.id).take(10).toList();

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

  Future<String?> createCard({
    required String accountId,
    required String name,
    required bool isTrial,
    String category = 'personal',
    double balanceLimit = 50000,
  }) async {
    state = const AsyncValue.loading();
    try {
      final result = await FirebaseFunctions.instance.httpsCallable('createVirtualCard').call({
        'account_id': accountId,
        'name': name,
        'is_trial': isTrial,
        'category': category,
        'balance_limit': balanceLimit,
      });
      state = const AsyncValue.data(null);
      return result.data['cardId'] as String?;
    } catch (e) {
      state = AsyncValue.error(e.toString(), StackTrace.current);
      return null;
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
  Future<bool> activateKillSwitch(String uid) async {
    state = const AsyncValue.loading();
    try {
      await FirebaseFunctions.instance.httpsCallable('activateKillSwitch').call();
      state = const AsyncValue.data(null);
      return true;
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      return false;
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
}

final cardNotifierProvider =
    StateNotifierProvider<CardNotifier, AsyncValue<void>>((ref) {
  return CardNotifier();
});
