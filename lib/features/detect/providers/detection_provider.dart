import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── Firestore live stream ────────────────────────────────────────────────────
final detectedSubscriptionsProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return Stream.value([]);

  return FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('detected_subscriptions')
      .orderBy('detectedAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map((d) => d.data()).toList());
});

// ── Scan state ───────────────────────────────────────────────────────────────
class DetectionScanState {
  final bool isLoading;
  final double progress;
  final int? lastCount;

  const DetectionScanState({
    this.isLoading = false,
    this.progress = 0.0,
    this.lastCount,
  });

  DetectionScanState copyWith({bool? isLoading, double? progress, int? lastCount}) =>
      DetectionScanState(
        isLoading: isLoading ?? this.isLoading,
        progress: progress ?? this.progress,
        lastCount: lastCount ?? this.lastCount,
      );
}

class DetectionScanNotifier extends StateNotifier<DetectionScanState> {
  DetectionScanNotifier() : super(const DetectionScanState());

  /// [messages] — SMS/email text messages to analyze. Pass real user messages from
  /// the device's SMS inbox or email API. Passing an empty list returns 0 results
  /// without error, which is the correct behavior when no connectors are active.
  Future<int> runScan({List<String> messages = const []}) async {
    if (state.isLoading) return 0;
    state = state.copyWith(isLoading: true, progress: 0.0);

    // Animate progress bar while waiting
    Timer? ticker;
    ticker = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (state.progress < 0.92) {
        state = state.copyWith(progress: state.progress + 0.018);
      } else {
        ticker?.cancel();
      }
    });

    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('detectSubscriptions')
          .call({'messages': messages});

      ticker.cancel();
      final dataMap = result.data as Map<dynamic, dynamic>;
      final count = (dataMap['count'] ?? 0) as int;
      state = state.copyWith(isLoading: false, progress: 1.0, lastCount: count);
      return count;
    } catch (_) {
      ticker.cancel();
      state = state.copyWith(isLoading: false, progress: 0.0);
      rethrow;
    }
  }
}

final detectionScanProvider =
    StateNotifierProvider<DetectionScanNotifier, DetectionScanState>(
        (_) => DetectionScanNotifier());

