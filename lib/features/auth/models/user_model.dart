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
    String? avatarUrl,
    DateTime? lastLoginAt,
    bool? nightLockdown,
    bool? geoFence,
    bool? hasBvn,
    bool? blockAlerts,
    bool? subscriptionReminders,
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
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdAt: createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      nightLockdown: nightLockdown ?? this.nightLockdown,
      geoFence: geoFence ?? this.geoFence,
      hasBvn: hasBvn ?? this.hasBvn,
      blockAlerts: blockAlerts ?? this.blockAlerts,
      subscriptionReminders: subscriptionReminders ?? this.subscriptionReminders,
    );
  }
}
