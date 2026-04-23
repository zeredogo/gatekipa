// lib/features/wallet/models/wallet_model.dart
//
// The wallet document at users/{uid}/wallet/balance is a CACHED SNAPSHOT.
// It is written ONLY by Cloud Functions after committing ledger entries.
// The client MUST NOT write to this document directly.
//
// Source of truth for balance: wallet_ledger/{entryId} collection.
// See: lib/features/wallet/models/wallet_ledger_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class WalletModel {
  final String userId;

  /// Cached balance derived from wallet_ledger by the Cloud Functions layer.
  /// ⚠️  Do NOT use this field for financial calculations that require
  ///    perfect accuracy — always query the ledger sum from the backend.
  ///    This value is suitable for DISPLAY purposes only.
  final double cachedBalance;

  final String currency;
  final DateTime? lastFunded;
  final bool isLocked;

  const WalletModel({
    required this.userId,
    required this.cachedBalance,
    this.currency = 'NGN',
    this.lastFunded,
    this.isLocked = false,
  });

  /// Backward-compatibility getter for existing UI code.
  /// Prefer [cachedBalance] in new code.
  double get balance => cachedBalance;

  factory WalletModel.fromFirestore(DocumentSnapshot doc) {
    try {
      final data = doc.data() as Map<String, dynamic>;
      // During the dual-write migration window, read 'cached_balance' first.
      // Fall back to 'balance' for existing documents that haven't been
      // migrated yet by the Cloud Function backfill job.
      final rawBalance = data['cached_balance'] ?? data['balance'] ?? 0.0;
      return WalletModel(
        userId: doc.id,
        cachedBalance: (rawBalance as num).toDouble(),
        currency: data['currency'] as String? ?? 'NGN',
        lastFunded: (data['lastFunded'] as Timestamp?)?.toDate(),
        isLocked: data['isLocked'] as bool? ?? false,
      );
    } catch (e) {
      debugPrint('[DataBoundary] Failed to parse WalletModel for document ${doc.id}. Error: $e');
      rethrow;
    }
  }

  /// ⚠️  toFirestore() intentionally does NOT include cachedBalance.
  ///    Balance updates are performed exclusively by Cloud Functions
  ///    via FieldValue.increment() after committing wallet_ledger entries.
  Map<String, dynamic> toFirestore() {
    return <String, dynamic>{
      'currency': currency,
      // cached_balance is managed by backend only — omitted here deliberately.
    };
  }

  WalletModel copyWith({double? cachedBalance, bool? isLocked}) {
    return WalletModel(
      userId: userId,
      cachedBalance: cachedBalance ?? this.cachedBalance,
      currency: currency,
      lastFunded: lastFunded,
      isLocked: isLocked ?? this.isLocked,
    );
  }
}
