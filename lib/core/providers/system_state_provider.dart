// lib/core/providers/system_state_provider.dart
//
// Streams the global system operating mode from Firestore.
// The `system_state/global` document is written ONLY by:
//   1. The Admin Portal Kill Switch (api/kill-switch/route.ts)
//   2. Backend Cloud Functions that detect degraded external APIs
//
// All financial action screens MUST watch this provider and gate
// their actions accordingly. Non-NORMAL modes are surfaced to users
// via a banner on the DashboardScreen.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SystemMode {
  /// Fully operational. All features available.
  normal,

  /// External APIs (Bridgecard/Paystack) are unstable.
  /// Card creation and funding are queued; read operations continue.
  degraded,

  /// Emergency lockdown. All financial operations suspended immediately.
  /// Activated via Admin Portal Kill Switch or automated anomaly detection.
  lockdown;

  static SystemMode fromString(String? raw) {
    switch (raw) {
      case 'DEGRADED':
        return SystemMode.degraded;
      case 'LOCKDOWN':
        return SystemMode.lockdown;
      default:
        return SystemMode.normal;
    }
  }
}

class SystemState {
  final SystemMode mode;
  final String? reason;
  final String? activatedBy;
  final DateTime? updatedAt;

  const SystemState({
    required this.mode,
    this.reason,
    this.activatedBy,
    this.updatedAt,
  });

  // ── Convenience getters ─────────────────────────────────────────────────────
  bool get isOperational => mode == SystemMode.normal;
  bool get isDegraded => mode == SystemMode.degraded;
  bool get isLockedDown => mode == SystemMode.lockdown;

  /// Returns true if the user should be blocked from initiating a financial op.
  bool get blocksFinancialOps => !isOperational;

  /// The message to show in the system mode banner.
  String get bannerMessage {
    switch (mode) {
      case SystemMode.normal:
        return '';
      case SystemMode.degraded:
        return '⚠️  System temporarily limited — card operations may be delayed.';
      case SystemMode.lockdown:
        return '🔒  Emergency lockdown active — all card operations are suspended.';
    }
  }

  /// The default SystemState assumed when the Firestore document doesn't exist.
  static const normal = SystemState(mode: SystemMode.normal);
}

/// Streams the live system operating mode from Firestore.
///
/// Usage in any screen:
/// ```dart
/// final systemState = ref.watch(systemStateProvider).valueOrNull
///     ?? SystemState.normal;
/// if (systemState.blocksFinancialOps) { /* show error */ return; }
/// ```
final systemStateProvider = StreamProvider.autoDispose<SystemState>((ref) {
  return FirebaseFirestore.instance
      .doc('system_state/global')
      .snapshots()
      .map((snap) {
    if (!snap.exists || snap.data() == null) {
      return SystemState.normal;
    }
    final data = snap.data()!;
    return SystemState(
      mode: SystemMode.fromString(data['mode'] as String?),
      reason: data['reason'] as String?,
      activatedBy: data['activated_by'] as String?,
      updatedAt: data['updated_at'] is Timestamp
          ? (data['updated_at'] as Timestamp).toDate()
          : null,
    );
  });
});
