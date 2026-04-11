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

  static const List<String> _sampleMessages = [
    "Your NGN 4,500 Netflix subscription renewal was successful. Receipt from Netflix.",
    "Monthly billing from Spotify NGN 1,500. Your subscription plan auto-renewed.",
    "AWS S3 NGN 8,500 recurring monthly charge processed. Billed to your account.",
    "Apple receipt from App Store NGN 3,000 annual subscription renewed.",
    "Receipt from Showmax NGN 2,100 for your monthly membership.",
  ];

  Future<int> runScan() async {
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
          .call({'messages': _sampleMessages});

      ticker.cancel();
      final count = (result.data['count'] ?? 0) as int;
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

