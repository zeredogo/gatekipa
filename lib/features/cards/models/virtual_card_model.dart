// lib/features/cards/models/virtual_card_model.dart
//
// Card status authority model:
//   local_status  → what the Gatekeeper app uses for ALL decisions
//   bridgecard_status → mirrored from Bridgecard for display / audit only
//
// Status lifecycle (enforced by stateMachine.ts in Cloud Functions):
//   pending_issuance → issued → active → frozen → terminated
//   No skipping. Transitions enforced by backend only.
//
// ⚠️  spentAmount and chargeCount are CACHED COPIES updated by Cloud
//    Functions. The rule engine reads card_ledger directly. Do NOT
//    use these fields for rule enforcement decisions.
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
  final String accountId;  // → accounts.id
  final String name;

  /// The authoritative status for all app-side behavior.
  /// Written by Cloud Functions via the stateMachine only — never by the client.
  /// Valid values: pending_issuance | issued | active | frozen | terminated
  final String localStatus;

  /// Mirrored from Bridgecard for display and audit purposes ONLY.
  /// Never use this field to gate transactions or UI actions.
  final String? bridgecardStatus;

  /// Monotonically increasing version counter, incremented on every state change.
  /// Used by the backend to detect and reject stale concurrent mutations.
  final int lifecycleVersion;

  final bool isTrial;
  final String category;   // personal | business
  final int createdAt;     // epoch ms
  final String? color;

  // Bridgecard specifics
  final String? bridgecardCardId;
  final String? bridgecardCurrency;

  // UI display extras
  final String? last4;
  final String? maskedNumber;
  final String? cvv;

  /// The amount of wallet funds allocated to this card.
  final double allocatedAmount;

  /// Cached total spend from the card_ledger. Updated by Cloud Functions.
  /// ⚠️  For DISPLAY only. The rule engine uses card_ledger directly.
  final double cachedSpentAmount;

  /// Cached charge count from the card_ledger. Updated by Cloud Functions.
  /// ⚠️  For DISPLAY only. The rule engine uses card_ledger directly.
  final int cachedChargeCount;

  // ── Backward-compatibility getters ──────────────────────────────────────────
  /// Use [localStatus] for all decisions. This getter exists for backward compat.
  String get status => localStatus;
  String get userId => '';
  String get type => isTrial ? 'trial' : 'subscription';
  String? get label => name;
  String? get merchantName => null;
  String? get merchantCategory => null;
  String? get bridgecardId => bridgecardCardId;
  String? get currency => bridgecardCurrency ?? 'NGN';

  /// Backward-compat: screens referencing balanceLimit still work during migration.
  double get balanceLimit => allocatedAmount;

  /// Backward-compat: screens referencing spentAmount get the cached value.
  double get spentAmount => cachedSpentAmount;

  /// Backward-compat: screens referencing chargeCount get the cached value.
  int get chargeCount => cachedChargeCount;

  const VirtualCardModel({
    required this.id,
    required this.accountId,
    required this.name,
    this.localStatus = 'active',
    this.bridgecardStatus,
    this.lifecycleVersion = 0,
    this.isTrial = false,
    this.category = 'personal',
    required this.createdAt,
    this.color,
    this.bridgecardCardId,
    this.bridgecardCurrency,
    this.last4,
    this.maskedNumber,
    this.cvv,
    this.allocatedAmount = 0,
    this.cachedSpentAmount = 0,
    this.cachedChargeCount = 0,
  });

  factory VirtualCardModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return VirtualCardModel(
      id: doc.id,
      accountId: data['account_id'] as String? ?? '',
      name: data['name'] as String? ?? 'Virtual Card',
      // Read localStatus first (new field). Fall back to legacy 'status' field
      // during the migration window before Cloud Functions backfill runs.
      localStatus: data['local_status'] as String? ?? data['status'] as String? ?? 'active',
      bridgecardStatus: data['bridgecard_status'] as String?,
      lifecycleVersion: data['lifecycle_version'] as int? ?? 0,
      isTrial: data['is_trial'] as bool? ?? false,
      category: data['category'] as String? ?? 'personal',
      createdAt: data['created_at'] is int
          ? data['created_at'] as int
          : (data['created_at'] as Timestamp?)?.millisecondsSinceEpoch ??
              DateTime.now().millisecondsSinceEpoch,
      color: data['color'] as String?,
      bridgecardCardId: data['bridgecard_card_id'] as String?,
      bridgecardCurrency: data['bridgecard_currency'] as String?,
      last4: data['last4'] as String?,
      maskedNumber: data['masked_number'] as String?,
      cvv: data['cvv'] as String?,
      // Prefer allocated_amount; fall back to legacy balance_limit.
      allocatedAmount:
          ((data['allocated_amount'] ?? data['balance_limit'] ?? 0) as num).toDouble(),
      cachedSpentAmount:
          ((data['spent_amount'] ?? 0) as num).toDouble(),
      cachedChargeCount: data['charge_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'account_id': accountId,
        'name': name,
        // Do NOT write local_status or lifecycle_version from client.
        // These are managed exclusively by Cloud Functions.
        'is_trial': isTrial,
        'category': category,
        'created_at': createdAt,
        'color': color,
      };

  /// Status checks use localStatus — the authoritative app-side field.
  bool get isActive => localStatus == 'active';
  bool get isBlocked => localStatus == 'blocked';
  bool get isExpired => localStatus == 'expired';
  bool get isFrozen => localStatus == 'frozen';
  bool get isPendingIssuance => localStatus == 'pending_issuance';
  bool get isTerminated => localStatus == 'terminated';

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

  /// Remaining spendable balance — for DISPLAY only.
  /// The rule engine uses the live card_ledger sum, not this value.
  double get remainingLimit => allocatedAmount - cachedSpentAmount;

  /// Usage fraction (0.0 to 1.0) — for UI progress indicators.
  double get usagePercent =>
      allocatedAmount > 0 ? (cachedSpentAmount / allocatedAmount).clamp(0.0, 1.0) : 0;
}
