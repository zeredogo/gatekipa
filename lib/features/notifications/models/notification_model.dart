// lib/features/notifications/models/notification_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationModel {
  final String id;
  final String userId;
  final String type; // blocked, upcoming, system, transaction
  final String title;
  final String body;
  final bool isRead;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata; // e.g. cardId, amount, merchant

  const NotificationModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    this.isRead = false,
    required this.timestamp,
    this.metadata,
  });

  factory NotificationModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return NotificationModel(
      id: doc.id,
      // Cloud Function writes user_id (snake_case); guard against legacy docs
      userId: data['user_id'] ?? data['userId'] ?? '',
      type: data['type'] ?? 'system',
      title: data['title'] ?? '',
      body: data['body'] ?? data['message'] ?? '',
      // Cloud Function writes isRead; guard against old 'read' field
      isRead: data['isRead'] ?? data['read'] ?? false,
      timestamp: data['timestamp'] is Timestamp
          ? (data['timestamp'] as Timestamp).toDate()
          : DateTime.now(),
      metadata: data['metadata'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'user_id': userId,
        'type': type,
        'title': title,
        'body': body,
        'isRead': isRead,
        'timestamp': Timestamp.fromDate(timestamp),
        'metadata': metadata,
      };


  NotificationModel markRead() => NotificationModel(
        id: id,
        userId: userId,
        type: type,
        title: title,
        body: body,
        isRead: true,
        timestamp: timestamp,
        metadata: metadata,
      );
}

// ── Subscription Model ─────────────────────────────────────────────────────────
class SubscriptionModel {
  final String id;
  final String userId;
  final String name;
  final String category;
  final double lastAmount;
  final String billingCycle; // monthly, yearly, weekly
  final String protectionStatus; // unprotected, protected
  final String? iconName;
  final String? linkedCardId;
  final DateTime? lastCharged;
  final DateTime? nextCharged;

  const SubscriptionModel({
    required this.id,
    required this.userId,
    required this.name,
    required this.category,
    required this.lastAmount,
    this.billingCycle = 'monthly',
    this.protectionStatus = 'unprotected',
    this.iconName,
    this.linkedCardId,
    this.lastCharged,
    this.nextCharged,
  });

  factory SubscriptionModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SubscriptionModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      name: data['name'] ?? '',
      category: data['category'] ?? 'General',
      lastAmount: (data['lastAmount'] ?? 0.0).toDouble(),
      billingCycle: data['billingCycle'] ?? 'monthly',
      protectionStatus: data['protectionStatus'] ?? 'unprotected',
      iconName: data['iconName'],
      linkedCardId: data['linkedCardId'],
      lastCharged: (data['lastCharged'] as Timestamp?)?.toDate(),
      nextCharged: (data['nextCharged'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'name': name,
        'category': category,
        'lastAmount': lastAmount,
        'billingCycle': billingCycle,
        'protectionStatus': protectionStatus,
        'iconName': iconName,
        'linkedCardId': linkedCardId,
        'lastCharged':
            lastCharged != null ? Timestamp.fromDate(lastCharged!) : null,
        'nextCharged':
            nextCharged != null ? Timestamp.fromDate(nextCharged!) : null,
      };

  bool get isProtected => protectionStatus == 'protected';
}
