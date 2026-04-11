// lib/features/accounts/models/account_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// Maps exactly to the `accounts` Firestore collection schema:
/// { id, owner_user_id, name, type, created_at }
class AccountModel {
  final String id;
  final String ownerUserId;
  final String name;
  final String type; // personal | business
  final int createdAt; // epoch ms

  const AccountModel({
    required this.id,
    required this.ownerUserId,
    required this.name,
    required this.type,
    required this.createdAt,
  });

  factory AccountModel.fromFirestore(DocumentSnapshot doc) {
    try {
      final data = doc.data() as Map<String, dynamic>;
      return AccountModel(
        id: doc.id,
      ownerUserId: data['owner_user_id'] ?? '',
      name: data['name'] ?? 'Account',
      type: data['type'] ?? 'personal',
      createdAt: data['created_at'] is int
          ? data['created_at'] as int
          : (data['created_at'] as Timestamp?)?.millisecondsSinceEpoch ??
              DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      print('[DataBoundary] Failed to parse AccountModel for document ${doc.id}. Error: $e');
      rethrow;
    }
  }

  Map<String, dynamic> toFirestore() => {
        'owner_user_id': ownerUserId,
        'name': name,
        'type': type,
      };

  bool get isPersonal => type == 'personal';
  bool get isBusiness => type == 'business';
}
