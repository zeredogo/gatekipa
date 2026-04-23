// lib/features/wallet/models/wallet_ledger_model.dart
//
// Append-only ledger entry for wallet credits and debits.
// This collection (wallet_ledger/{entryId}) is the source of truth for
// all wallet balance changes. The wallet document's `cached_balance` field
// is a derived snapshot written exclusively by Cloud Functions after each
// ledger commit — never by the client.
//
// ⚠️  RULE: This model is READ ONLY from the client. All writes go through
//           Cloud Functions (verifyPaystackPayment, processTransaction, etc.)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

enum WalletLedgerType {
  credit,
  debit;

  String get firestoreValue => name; // 'credit' | 'debit'

  static WalletLedgerType fromString(String? raw) {
    switch (raw) {
      case 'credit':
        return WalletLedgerType.credit;
      case 'debit':
        return WalletLedgerType.debit;
      default:
        debugPrint('[WalletLedger] Unknown type: $raw — defaulting to debit');
        return WalletLedgerType.debit;
    }
  }
}

/// The source that triggered this ledger entry.
enum WalletLedgerSource {
  paystack,
  walletToCard,
  refund,
  admin,
  unknown;

  static WalletLedgerSource fromString(String? raw) {
    switch (raw) {
      case 'paystack':
        return WalletLedgerSource.paystack;
      case 'wallet_to_card':
        return WalletLedgerSource.walletToCard;
      case 'refund':
        return WalletLedgerSource.refund;
      case 'admin':
        return WalletLedgerSource.admin;
      default:
        return WalletLedgerSource.unknown;
    }
  }

  /// Human-readable label for UI display.
  String get displayLabel {
    switch (this) {
      case WalletLedgerSource.paystack:
        return 'Paystack Deposit';
      case WalletLedgerSource.walletToCard:
        return 'Card Funding';
      case WalletLedgerSource.refund:
        return 'Refund';
      case WalletLedgerSource.admin:
        return 'Admin Adjustment';
      case WalletLedgerSource.unknown:
        return 'Unknown';
    }
  }
}

class WalletLedgerEntry {
  final String id;
  final String userId;
  final WalletLedgerType type;
  final double amount;
  final String reference;

  /// Optional cached balance snapshot at the time of this entry.
  /// Useful for a running balance display but should not be used
  /// for financial calculations — always re-derive from the full ledger.
  final double? balanceAfter;

  final WalletLedgerSource source;
  final DateTime createdAt;

  const WalletLedgerEntry({
    required this.id,
    required this.userId,
    required this.type,
    required this.amount,
    required this.reference,
    this.balanceAfter,
    required this.source,
    required this.createdAt,
  });

  bool get isCredit => type == WalletLedgerType.credit;
  bool get isDebit => type == WalletLedgerType.debit;

  /// Signed amount: positive for credits, negative for debits.
  double get signedAmount => isCredit ? amount : -amount;

  factory WalletLedgerEntry.fromFirestore(DocumentSnapshot doc) {
    try {
      final data = doc.data() as Map<String, dynamic>;
      return WalletLedgerEntry(
        id: doc.id,
        userId: data['user_id'] as String? ?? '',
        type: WalletLedgerType.fromString(data['type'] as String?),
        amount: (data['amount'] as num? ?? 0).toDouble(),
        reference: data['reference'] as String? ?? '',
        balanceAfter: (data['balance_after'] as num?)?.toDouble(),
        source: WalletLedgerSource.fromString(data['source'] as String?),
        createdAt: data['created_at'] is Timestamp
            ? (data['created_at'] as Timestamp).toDate()
            : DateTime.now(),
      );
    } catch (e) {
      debugPrint(
          '[DataBoundary] Failed to parse WalletLedgerEntry for ${doc.id}: $e');
      rethrow;
    }
  }
}
