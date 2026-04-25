// lib/features/wallet/models/transaction_orchestration_model.dart
//
// Represents a financial operation being managed by the processTransaction
// Cloud Function orchestrator. The `transactions/{txnId}` collection is the
// AUTHORITATIVE lifecycle tracker for every financial mutation in the system.
//
// Status machine (enforced by backend):
//   PENDING → PROCESSING → SUCCESS
//                        → FAILED
//                        → UNKNOWN  (network/timeout — reconciled later)
//
// ⚠️  UI RULE: Never assume SUCCESS until this document reflects it.
//              Display a spinner for PENDING/PROCESSING, not an optimistic tick.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Valid states in the transaction lifecycle state machine.
enum TxnStatus {
  pending,
  processing,
  success,
  failed,

  /// Assigned when the backend sent a request to an external system (Bridgecard,
  /// Paystack) but did not receive a confirmation before timeout. The daily
  /// reconciliation job resolves UNKNOWN transactions by querying external APIs.
  unknown;

  static TxnStatus fromString(String? raw) {
    switch (raw) {
      case 'PENDING':
        return TxnStatus.pending;
      case 'PROCESSING':
        return TxnStatus.processing;
      case 'SUCCESS':
        return TxnStatus.success;
      case 'FAILED':
        return TxnStatus.failed;
      case 'UNKNOWN':
        return TxnStatus.unknown;
      default:
        debugPrint('[OrchestratedTxn] Unknown status: $raw');
        return TxnStatus.unknown;
    }
  }

  /// Whether the transaction is still in-flight (not yet terminal).
  bool get isInFlight =>
      this == TxnStatus.pending || this == TxnStatus.processing;

  /// Terminal states — will not change further (except UNKNOWN which reconciles).
  bool get isTerminal =>
      this == TxnStatus.success || this == TxnStatus.failed;

  /// Short label for status badges in the UI.
  String get displayLabel {
    switch (this) {
      case TxnStatus.pending:
        return 'Pending';
      case TxnStatus.processing:
        return 'Processing';
      case TxnStatus.success:
        return 'Completed';
      case TxnStatus.failed:
        return 'Failed';
      case TxnStatus.unknown:
        return 'Verifying';
    }
  }
}

/// Valid types that a transaction can represent.
enum TxnType {
  walletToCard,
  cardCharge,
  walletFunding,
  withdrawal;

  static TxnType fromString(String? raw) {
    switch (raw) {
      case 'wallet_to_card':
        return TxnType.walletToCard;
      case 'card_charge':
        return TxnType.cardCharge;
      case 'wallet_funding':
        return TxnType.walletFunding;
      case 'withdrawal':
        return TxnType.withdrawal;
      default:
        return TxnType.cardCharge;
    }
  }

  String get displayLabel {
    switch (this) {
      case TxnType.walletToCard:
        return 'Card Funding';
      case TxnType.cardCharge:
        return 'Card Charge';
      case TxnType.walletFunding:
        return 'Wallet Top-Up';
      case TxnType.withdrawal:
        return 'Withdrawal';
    }
  }
}

class OrchestratedTransaction {
  final String id;
  final String userId;
  final TxnType type;
  final TxnStatus status;
  final double amount;

  /// Idempotency key used to prevent duplicate processing.
  /// Format: "{userId}:{action}:{nonce}" — set by the client on creation.
  final String idempotencyKey;

  /// Flexible metadata bag: cardId, paystackRef, bridgecardRef, accountId, etc.
  final Map<String, dynamic> metadata;

  final String? errorMessage;
  final DateTime createdAt;
  final DateTime updatedAt;

  const OrchestratedTransaction({
    required this.id,
    required this.userId,
    required this.type,
    required this.status,
    required this.amount,
    required this.idempotencyKey,
    required this.metadata,
    this.errorMessage,
    required this.createdAt,
    required this.updatedAt,
  });

  // ── Status helpers ──────────────────────────────────────────────────────────
  bool get isPending => status == TxnStatus.pending;
  bool get isProcessing => status == TxnStatus.processing;
  bool get isSuccess => status == TxnStatus.success;
  bool get isFailed => status == TxnStatus.failed;
  bool get isUnknown => status == TxnStatus.unknown;
  bool get isInFlight => status.isInFlight;

  // ── Metadata convenience accessors ──────────────────────────────────────────
  String? get cardId => metadata['card_id'] as String?;
  String? get paystackRef => metadata['paystack_ref'] as String?;
  String? get bridgecardRef => metadata['bridgecard_ref'] as String?;

  factory OrchestratedTransaction.fromFirestore(DocumentSnapshot doc) {
    try {
      final data = doc.data() as Map<String, dynamic>;
      return OrchestratedTransaction(
        id: doc.id,
        userId: data['user_id'] as String? ?? '',
        type: TxnType.fromString(data['type'] as String?),
        status: TxnStatus.fromString(data['status'] as String?),
        amount: num.tryParse(data['amount']?.toString() ?? '0')?.toDouble() ?? 0.0,
        idempotencyKey: data['idempotency_key'] as String? ?? '',
        metadata: Map<String, dynamic>.from(
            (data['metadata'] as Map?) ?? const {}),
        errorMessage: data['error_message'] as String?,
        createdAt: data['created_at'] is Timestamp
            ? (data['created_at'] as Timestamp).toDate()
            : DateTime.now(),
        updatedAt: data['updated_at'] is Timestamp
            ? (data['updated_at'] as Timestamp).toDate()
            : DateTime.now(),
      );
    } catch (e) {
      debugPrint(
          '[DataBoundary] Failed to parse OrchestratedTransaction for ${doc.id}: $e');
      rethrow;
    }
  }
}
