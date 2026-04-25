// lib/features/notifications/providers/notification_provider.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gatekipa/features/notifications/models/notification_model.dart';
import 'package:gatekipa/features/auth/providers/auth_provider.dart';
import 'package:gatekipa/core/constants/app_constants.dart';

// ── Notifications Stream ────────────────────────────────────────────────────────
final notificationsProvider = StreamProvider<List<NotificationModel>>((ref) {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return Stream.value([]);
  return FirebaseFirestore.instance
      .collection(AppConstants.usersCollection)
      .doc(user.uid)
      .collection(AppConstants.notificationsCollection)
      .orderBy('timestamp', descending: true)
      .limit(50)
      .snapshots()
      .map((snap) =>
          snap.docs.map((d) => NotificationModel.fromFirestore(d)).toList());
});

// ── Unread count ────────────────────────────────────────────────────────────────
final unreadNotifCountProvider = Provider<int>((ref) {
  final notifs = ref.watch(notificationsProvider);
  return notifs.when(
    data: (list) => list.where((n) => !n.isRead).length,
    loading: () => 0,
    error: (_, __) => 0,
  );
});

// ── Filter provider ─────────────────────────────────────────────────────────────
final notifFilterProvider = StateProvider<String>((ref) => 'all');

final filteredNotificationsProvider = Provider<List<NotificationModel>>((ref) {
  final all = ref.watch(notificationsProvider);
  final filter = ref.watch(notifFilterProvider);
  return all.when(
    data: (list) {
      if (filter == 'all') return list;
      return list.where((n) => n.type == filter).toList();
    },
    loading: () => [],
    error: (_, __) => [],
  );
});

// ── Notification Notifier ───────────────────────────────────────────────────────
class NotificationNotifier extends StateNotifier<void> {
  final FirebaseFirestore _db;

  NotificationNotifier(this._db) : super(null);

  Future<void> markAsRead(String userId, String notifId) async {
    await _db
        .collection(AppConstants.usersCollection)
        .doc(userId)
        .collection(AppConstants.notificationsCollection)
        .doc(notifId)
        .update({'isRead': true});
  }

  Future<void> markAllRead(String userId) async {
    final batch = _db.batch();
    final snap = await _db
        .collection(AppConstants.usersCollection)
        .doc(userId)
        .collection(AppConstants.notificationsCollection)
        .where('isRead', isEqualTo: false)
        .get();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }

  Future<void> deleteNotification(String userId, String notifId) async {
    await _db
        .collection(AppConstants.usersCollection)
        .doc(userId)
        .collection(AppConstants.notificationsCollection)
        .doc(notifId)
        .delete();
  }
}

final notificationNotifierProvider =
    StateNotifierProvider<NotificationNotifier, void>((ref) {
  return NotificationNotifier(ref.watch(firestoreProvider));
});

// ── Subscriptions Stream ────────────────────────────────────────────────────────
final subscriptionsProvider = StreamProvider<List<SubscriptionModel>>((ref) {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return Stream.value([]);
  return FirebaseFirestore.instance
      .collection(AppConstants.usersCollection)
      .doc(user.uid)
      .collection(AppConstants.subscriptionsCollection)
      .snapshots()
      .map((snap) =>
          snap.docs.map((d) => SubscriptionModel.fromFirestore(d)).toList());
});
