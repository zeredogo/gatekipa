// lib/features/auth/models/user_model.dart
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
  final String kycStatus; // 'pending', 'verified', 'failed'
  final bool isPremium;
  final String? avatarUrl;
  final DateTime createdAt;
  final DateTime? lastLoginAt;
  final bool nightLockdown;
  final bool geoFence;
  final bool hasBvn;
  final bool blockAlerts;
  final bool subscriptionReminders;
  final int bvnVerificationAttempts;
  final int kycVerificationAttempts;

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
    this.kycStatus = 'pending',
    this.isPremium = false,
    this.avatarUrl,
    required this.createdAt,
    this.lastLoginAt,
    this.nightLockdown = false,
    this.geoFence = false,
    this.hasBvn = false,
    this.blockAlerts = false,
    this.subscriptionReminders = false,
    this.bvnVerificationAttempts = 0,
    this.kycVerificationAttempts = 0,
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
      kycStatus: data['kycStatus'] ?? 'pending',
      isPremium: data['isPremium'] ?? false,
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
      bvnVerificationAttempts: data['bvnVerificationAttempts'] ?? 0,
      kycVerificationAttempts: data['kycVerificationAttempts'] ?? 0,
    );
    } catch (e) {
      debugPrint('[DataBoundary] Failed to parse UserModel for document ${doc.id}. Error: $e');
      rethrow;
    }
  }

  Map<String, dynamic> toFirestore() {
    return <String, dynamic>{
      'firstName': firstName,
      'lastName': lastName,
      'address': address,
      'displayName': displayName,
      'phoneNumber': phoneNumber,
      'email': email,
      'avatarUrl': avatarUrl,
      'nightLockdown': nightLockdown,
      'geoFence': geoFence,
      'blockAlerts': blockAlerts,
      'subscriptionReminders': subscriptionReminders,
      'bvnVerificationAttempts': bvnVerificationAttempts,
      'kycVerificationAttempts': kycVerificationAttempts,
      // lastLoginAt is NEVER written here — it is set only by _handleUserLogin
      // via a separate Firestore update to avoid overwriting on every profile sync.
    };
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
    String? kycStatus,
    bool? isPremium,
    String? avatarUrl,
    DateTime? lastLoginAt,
    bool? nightLockdown,
    bool? geoFence,
    bool? hasBvn,
    bool? blockAlerts,
    bool? subscriptionReminders,
    int? bvnVerificationAttempts,
    int? kycVerificationAttempts,
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
      kycStatus: kycStatus ?? this.kycStatus,
      isPremium: isPremium ?? this.isPremium,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdAt: createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      nightLockdown: nightLockdown ?? this.nightLockdown,
      geoFence: geoFence ?? this.geoFence,
      hasBvn: hasBvn ?? this.hasBvn,
      blockAlerts: blockAlerts ?? this.blockAlerts,
      subscriptionReminders: subscriptionReminders ?? this.subscriptionReminders,
      bvnVerificationAttempts: bvnVerificationAttempts ?? this.bvnVerificationAttempts,
      kycVerificationAttempts: kycVerificationAttempts ?? this.kycVerificationAttempts,
    );
  }
}
