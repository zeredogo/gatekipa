// lib/features/wallet/models/wallet_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class WalletModel {
  final String userId;
  final double balance;
  final String currency;
  final DateTime? lastFunded;
  final bool isLocked;

  const WalletModel({
    required this.userId,
    required this.balance,
    this.currency = 'NGN',
    this.lastFunded,
    this.isLocked = false,
  });

  factory WalletModel.fromFirestore(DocumentSnapshot doc) {
    try {
      final data = doc.data() as Map<String, dynamic>;
      return WalletModel(
        userId: doc.id,
      balance: (data['balance'] ?? 0.0).toDouble(),
      currency: data['currency'] ?? 'NGN',
      lastFunded: (data['lastFunded'] as Timestamp?)?.toDate(),
      isLocked: data['isLocked'] ?? false,
    );
    } catch (e) {
      print('[DataBoundary] Failed to parse WalletModel for document ${doc.id}. Error: $e');
      rethrow;
    }
  }

  Map<String, dynamic> toFirestore() {
    final map = <String, dynamic>{
      'currency': currency,
    };
    
    if (lastFunded != null) {
      map['lastFunded'] = FieldValue.serverTimestamp();
    }
    
    return map;
  }

  WalletModel copyWith({double? balance, bool? isLocked}) {
    return WalletModel(
      userId: userId,
      balance: balance ?? this.balance,
      currency: currency,
      lastFunded: lastFunded,
      isLocked: isLocked ?? this.isLocked,
    );
  }
}
