// lib/features/cards/models/virtual_card_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

// ── CardRule — maps to top-level `rules` collection ────────────────────────────
class CardRule {
  final String id;
  final String cardId;
  final String type;     // spend | time | behavior
  final String subType;  // max_per_txn | monthly_cap | expiry_date | valid_duration | max_charges | block_after_first | block_if_amount_changes
  final dynamic value;
  final int createdAt;

  const CardRule({
    required this.id,
    required this.cardId,
    required this.type,
    required this.subType,
    required this.value,
    required this.createdAt,
  });

  factory CardRule.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CardRule(
      id: doc.id,
      cardId: data['card_id'] ?? '',
      type: data['type'] ?? '',
      subType: data['sub_type'] ?? '',
      value: data['value'],
      createdAt: data['created_at'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'card_id': cardId,
        'type': type,
        'sub_type': subType,
        'value': value,
        'created_at': createdAt,
      };

  // Typed accessors derived from subType + value
  double? get maxAmountPerTransaction =>
      subType == 'max_per_txn' ? (value as num?)?.toDouble() : null;

  double? get monthlyCap =>
      subType == 'monthly_cap' ? (value as num?)?.toDouble() : null;

  DateTime? get expiryDate => subType == 'expiry_date' && value != null
      ? DateTime.fromMillisecondsSinceEpoch(value as int)
      : null;

  int? get maxCharges =>
      subType == 'max_charges' ? (value as num?)?.toInt() : null;

  bool get blockAfterFirst => subType == 'block_after_first';

  bool get blockIfAmountChanges => subType == 'block_if_amount_changes';

  // UI display helpers
  bool get instantBreachAlert => false;
  bool get nightLockdown => subType == 'night_lockdown';
  bool get geoFenceEnabled => false;
}

// ── VirtualCardModel — maps to top-level `cards` collection ───────────────────
class VirtualCardModel {
  final String id;
  final String accountId;  // -> accounts.id
  final String name;
  final String status;     // active | blocked | expired | pending_issuance | frozen
  final bool isTrial;
  final String category;   // personal | business
  final int createdAt;     // epoch ms
  final String? color;

  // Bridgecard specifics
  final String? bridgecardCardId;
  final String? bridgecardStatus;
  final String? bridgecardCurrency;

  // UI display extras (populated from card doc if present)
  final String? last4;
  final String? maskedNumber;
  final String? cvv;
  final double balanceLimit;
  final double spentAmount;
  final int chargeCount;

  // Legacy compat — some screens use these
  String get userId => '';
  String get type => isTrial ? 'trial' : 'subscription';
  String? get label => name;
  String? get merchantName => null;
  String? get merchantCategory => null;
  String? get bridgecardId => bridgecardCardId;
  String? get currency => bridgecardCurrency ?? 'NGN';

  const VirtualCardModel({
    required this.id,
    required this.accountId,
    required this.name,
    this.status = 'active',
    this.isTrial = false,
    this.category = 'personal',
    required this.createdAt,
    this.color,
    this.bridgecardCardId,
    this.bridgecardStatus,
    this.bridgecardCurrency,
    this.last4,
    this.maskedNumber,
    this.cvv,
    this.balanceLimit = 0,
    this.spentAmount = 0,
    this.chargeCount = 0,
  });

  factory VirtualCardModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return VirtualCardModel(
      id: doc.id,
      accountId: data['account_id'] ?? '',
      name: data['name'] ?? 'Virtual Card',
      status: data['status'] ?? 'active',
      isTrial: data['is_trial'] ?? false,
      category: data['category'] ?? 'personal',
      createdAt: data['created_at'] is int
          ? data['created_at'] as int
          : (data['created_at'] as Timestamp?)?.millisecondsSinceEpoch ??
              DateTime.now().millisecondsSinceEpoch,
      color: data['color'],
      bridgecardCardId: data['bridgecard_card_id'],
      bridgecardStatus: data['bridgecard_status'],
      bridgecardCurrency: data['bridgecard_currency'],
      last4: data['last4'],
      maskedNumber: data['masked_number'],
      cvv: data['cvv'],
      balanceLimit: (data['balance_limit'] ?? 0).toDouble(),
      spentAmount: (data['spent_amount'] ?? 0).toDouble(),
      chargeCount: data['charge_count'] ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'account_id': accountId,
        'name': name,
        'status': status,
        'is_trial': isTrial,
        'category': category,
        'created_at': createdAt,
        'color': color,
      };

  bool get isActive => status == 'active';
  bool get isBlocked => status == 'blocked';
  bool get isExpired => status == 'expired';
  bool get isFrozen => status == 'frozen';

  String get displayName => name;

  // Stub rule — real rules are fetched via cardRulesProvider stream
  CardRule get rule => CardRule(
        id: '',
        cardId: id,
        type: '',
        subType: 'none',
        value: null,
        createdAt: 0,
      );

  DateTime get createdAtDate =>
      DateTime.fromMillisecondsSinceEpoch(createdAt);

  double get remainingLimit => balanceLimit - spentAmount;
  double get usagePercent =>
      balanceLimit > 0 ? (spentAmount / balanceLimit).clamp(0.0, 1.0) : 0;
}
