import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class UserModel {
  final String uid;
  final String? firstName;
  final String? lastName;
  final String? address;
  final String? displayName;
  final String? phoneNumber;
  final String? email;
  final String? bridgecardNuban;
  final String? bridgecardBankName;
  final String? bridgecardAccountName;
  final String? city;
  final String? state;
  final String? postalCode;
  final String? houseNumber;
  final String? bridgecardStatus;
  final String? bridgecardCardholderId;
  final String kycStatus; // 'pending', 'verified', 'failed'
  @Deprecated('Use planTier instead')
  final bool isPremium;
  final String planTier; // 'none', 'free', 'activation', 'premium', 'business'
  final int cardsIncluded;
  final String? avatarUrl;
  final DateTime createdAt;
  final DateTime? lastLoginAt;
  final bool nightLockdown;
  final bool geoFence;
  final bool hasBvn;
  final bool blockAlerts;
  final bool subscriptionReminders;
  final DateTime? sentinelTrialExpiryDate;
  final DateTime? subscriptionExpiryDate;
  final bool hasTransactionPin;

  bool get isSentinelPrime {
    if (planTier == 'premium' || planTier == 'business') return true;
    if (sentinelTrialExpiryDate != null && sentinelTrialExpiryDate!.isAfter(DateTime.now())) return true;
    return false;
  }

  /// Days left on either sentinel trial or full subscription, whichever is active.
  int get daysLeftOnPlan {
    if (planTier == 'premium' || planTier == 'business') {
      if (subscriptionExpiryDate != null) {
        return subscriptionExpiryDate!.difference(DateTime.now()).inDays.clamp(0, 999);
      }
      return 0;
    }
    // Instant / Activation — trial period
    if (sentinelTrialExpiryDate != null && sentinelTrialExpiryDate!.isAfter(DateTime.now())) {
      return sentinelTrialExpiryDate!.difference(DateTime.now()).inDays.clamp(0, 5);
    }
    return 0;
  }

  bool get isTrialActive =>
      sentinelTrialExpiryDate != null &&
      sentinelTrialExpiryDate!.isAfter(DateTime.now()) &&
      planTier != 'premium' &&
      planTier != 'business';

  const UserModel({
    required this.uid,
    this.firstName,
    this.lastName,
    this.address,
    this.displayName,
    this.phoneNumber,
    this.email,
    this.bridgecardNuban,
    this.bridgecardBankName,
    this.bridgecardAccountName,
    this.city,
    this.state,
    this.postalCode,
    this.houseNumber,
    this.bridgecardStatus,
    this.bridgecardCardholderId,
    this.kycStatus = 'pending',
    this.isPremium = false,
    this.planTier = 'none',
    this.cardsIncluded = 0,
    this.avatarUrl,
    required this.createdAt,
    this.lastLoginAt,
    this.nightLockdown = false,
    this.geoFence = false,
    this.hasBvn = false,
    this.blockAlerts = false,
    this.subscriptionReminders = false,
    this.sentinelTrialExpiryDate,
    this.subscriptionExpiryDate,
    this.hasTransactionPin = false,
  });

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    try {
      final data = doc.data() as Map<String, dynamic>;
      return UserModel(
        uid: doc.id,
      firstName: data['firstName'],
      lastName: data['lastName'],
      address: data['address'],
      displayName: data['displayName'],
      phoneNumber: data['phoneNumber'],
      email: data['email'],
      bridgecardNuban: data['bridgecardNuban'],
      bridgecardBankName: data['bridgecardBankName'],
      bridgecardAccountName: data['bridgecardAccountName'],
      city: data['city'],
      state: data['state'],
      postalCode: data['postalCode'],
      houseNumber: data['houseNumber'],
      bridgecardStatus: data['bridgecard_status'],
      bridgecardCardholderId: data['bridgecard_cardholder_id'],
      kycStatus: data['kycStatus'] ?? 'pending',
      isPremium: data['isPremium'] ?? false,
      planTier: data['planTier'] ?? 'none',
      cardsIncluded: data['cardsIncluded'] ?? 0,
      avatarUrl: data['avatarUrl'],
      createdAt: data.containsKey('created_at')
          ? (data['created_at'] is Timestamp 
              ? (data['created_at'] as Timestamp).toDate() 
              : DateTime.fromMillisecondsSinceEpoch(data['created_at'] as int))
          : (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastLoginAt: (data['lastLoginAt'] as Timestamp?)?.toDate(),
      nightLockdown: data['nightLockdown'] ?? false,
      geoFence: data['geoFence'] ?? false,
      hasBvn: data['hasBvn'] ?? false,
      blockAlerts: data['blockAlerts'] ?? false,
      subscriptionReminders: data['subscriptionReminders'] ?? false,
      sentinelTrialExpiryDate: data['sentinel_trial_expiry_date'] != null
          ? (data['sentinel_trial_expiry_date'] is Timestamp
              ? (data['sentinel_trial_expiry_date'] as Timestamp).toDate()
              : DateTime.fromMillisecondsSinceEpoch(data['sentinel_trial_expiry_date'] as int))
          : null,
      subscriptionExpiryDate: data['subscription_expiry_date'] != null
          ? (data['subscription_expiry_date'] is Timestamp
              ? (data['subscription_expiry_date'] as Timestamp).toDate()
              : DateTime.fromMillisecondsSinceEpoch(data['subscription_expiry_date'] as int))
          : null,
      hasTransactionPin: data['security'] != null && data['security']['pinHash'] != null,
    );
    } catch (e) {
      debugPrint('[DataBoundary] Failed to parse UserModel for document ${doc.id}. Error: $e');
      rethrow;
    }
  }

  Map<String, dynamic> toFirestore() {
    final map = <String, dynamic>{
      'firstName': firstName,
      'lastName': lastName,
      'address': address,
      'city': city,
      'state': state,
      'postalCode': postalCode,
      'houseNumber': houseNumber,
      'displayName': displayName,
      'phoneNumber': phoneNumber,
      'email': email,
      'avatarUrl': avatarUrl,
      'nightLockdown': nightLockdown,
      'geoFence': geoFence,
      'blockAlerts': blockAlerts,
      'subscriptionReminders': subscriptionReminders,
    };
    
    if (lastLoginAt != null) {
      map['lastLoginAt'] = FieldValue.serverTimestamp();
    }
    
    return map;
  }

  UserModel copyWith({
    String? firstName,
    String? lastName,
    String? address,
    String? displayName,
    String? phoneNumber,
    String? email,
    String? bridgecardNuban,
    String? bridgecardBankName,
    String? bridgecardAccountName,
    String? city,
    String? state,
    String? postalCode,
    String? houseNumber,
    String? bridgecardStatus,
    String? bridgecardCardholderId,
    String? kycStatus,
    bool? isPremium,
    // FIX: planTier and cardsIncluded were missing from copyWith — any caller that needed
    // to locally update the plan (e.g. optimistic UI after upgrade) silently fell back
    // to stale values, keeping isSentinelPrime incorrect until a full Firestore refresh.
    String? planTier,
    int? cardsIncluded,
    String? avatarUrl,
    DateTime? lastLoginAt,
    bool? nightLockdown,
    bool? geoFence,
    bool? hasBvn,
    bool? blockAlerts,
    bool? subscriptionReminders,
    DateTime? sentinelTrialExpiryDate,
    DateTime? subscriptionExpiryDate,
    bool? hasTransactionPin,
  }) {
    return UserModel(
      uid: uid,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      address: address ?? this.address,
      displayName: displayName ?? this.displayName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      email: email ?? this.email,
      bridgecardNuban: bridgecardNuban ?? this.bridgecardNuban,
      bridgecardBankName: bridgecardBankName ?? this.bridgecardBankName,
      bridgecardAccountName: bridgecardAccountName ?? this.bridgecardAccountName,
      city: city ?? this.city,
      state: state ?? this.state,
      postalCode: postalCode ?? this.postalCode,
      houseNumber: houseNumber ?? this.houseNumber,
      bridgecardStatus: bridgecardStatus ?? this.bridgecardStatus,
      bridgecardCardholderId: bridgecardCardholderId ?? this.bridgecardCardholderId,
      kycStatus: kycStatus ?? this.kycStatus,
      // ignore: deprecated_member_use_from_same_package
      isPremium: isPremium ?? this.isPremium,
      planTier: planTier ?? this.planTier,
      cardsIncluded: cardsIncluded ?? this.cardsIncluded,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdAt: createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      nightLockdown: nightLockdown ?? this.nightLockdown,
      geoFence: geoFence ?? this.geoFence,
      hasBvn: hasBvn ?? this.hasBvn,
      blockAlerts: blockAlerts ?? this.blockAlerts,
      subscriptionReminders: subscriptionReminders ?? this.subscriptionReminders,
      sentinelTrialExpiryDate: sentinelTrialExpiryDate ?? this.sentinelTrialExpiryDate,
      subscriptionExpiryDate: subscriptionExpiryDate ?? this.subscriptionExpiryDate,
      hasTransactionPin: hasTransactionPin ?? this.hasTransactionPin,
    );
  }
}
