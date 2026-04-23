// lib/features/cards/models/card_ledger_model.dart
//
// Append-only ledger entry for all virtual card financial events.
// This collection (card_ledger/{entryId}) is the ONLY authoritative source
// that the backend rule engine queries for:
//   - monthly_cap  → sum of 'charge' entries in the last 30 days
//   - max_charges  → count of 'charge' entries
//   - block_after_first → count >= 1
//   - block_if_amount_changes → amount of first 'charge' entry
//
// ⚠️  RULE: This model is READ ONLY from the client. All writes go through
//           Cloud Functions (Bridgecard webhooks, processTransaction, etc.)
//           cards.spentAmount and cards.chargeCount are CACHED COPIES only
//           and must NEVER be used for rule enforcement.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

enum CardLedgerType {
  funding,
  charge,
  refund,
  reversal;

  String get firestoreValue => name;

  static CardLedgerType fromString(String? raw) {
    switch (raw) {
      case 'funding':
        return CardLedgerType.funding;
      case 'charge':
        return CardLedgerType.charge;
      case 'refund':
        return CardLedgerType.refund;
      case 'reversal':
        return CardLedgerType.reversal;
      default:
        debugPrint('[CardLedger] Unknown type: $raw — defaulting to charge');
        return CardLedgerType.charge;
    }
  }

  /// UI display label.
  String get displayLabel {
    switch (this) {
      case CardLedgerType.funding:
        return 'Card Funded';
      case CardLedgerType.charge:
        return 'Charge';
      case CardLedgerType.refund:
        return 'Refund';
      case CardLedgerType.reversal:
        return 'Reversal';
    }
  }

  bool get isDebit => this == CardLedgerType.charge;
  bool get isCredit =>
      this == CardLedgerType.funding ||
      this == CardLedgerType.refund ||
      this == CardLedgerType.reversal;
}

class CardLedgerEntry {
  final String id;
  final String cardId;
  final String accountId;
  final CardLedgerType type;
  final double amount;
  final String merchantName;

  /// External reference: Bridgecard transaction ID, internal txnId, etc.
  final String reference;

  final DateTime createdAt;

  const CardLedgerEntry({
    required this.id,
    required this.cardId,
    required this.accountId,
    required this.type,
    required this.amount,
    required this.merchantName,
    required this.reference,
    required this.createdAt,
  });

  bool get isCharge => type == CardLedgerType.charge;
  bool get isFunding => type == CardLedgerType.funding;

  /// Signed amount for running balance display.
  double get signedAmount => type.isDebit ? -amount : amount;

  factory CardLedgerEntry.fromFirestore(DocumentSnapshot doc) {
    try {
      final data = doc.data() as Map<String, dynamic>;
      return CardLedgerEntry(
        id: doc.id,
        cardId: data['card_id'] as String? ?? '',
        accountId: data['account_id'] as String? ?? '',
        type: CardLedgerType.fromString(data['type'] as String?),
        amount: (data['amount'] as num? ?? 0).toDouble(),
        merchantName: data['merchant_name'] as String? ?? 'Unknown',
        reference: data['reference'] as String? ?? '',
        createdAt: data['created_at'] is Timestamp
            ? (data['created_at'] as Timestamp).toDate()
            : DateTime.now(),
      );
    } catch (e) {
      debugPrint(
          '[DataBoundary] Failed to parse CardLedgerEntry for ${doc.id}: $e');
      rethrow;
    }
  }
}
