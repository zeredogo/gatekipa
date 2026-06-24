// lib/core/services/force_update_service.dart
//
// Silently checks whether the installed build is below the minimum required
// build number set in Firebase Remote Config.
// The build number is NEVER rendered in the UI — only used for comparison.

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

class ForceUpdateService {
  static const _minBuildKey = 'min_build_number';

  /// Returns `true` if the currently installed build is below the minimum
  /// required build number defined in Firebase Remote Config.
  ///
  /// Always returns `false` on any error (network, parse, etc.) so that a
  /// failed check never blocks a legitimate user from accessing the app.
  static Future<bool> isUpdateRequired() async {
    try {
      final remoteConfig = FirebaseRemoteConfig.instance;

      await remoteConfig.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        // In production, 1 hour is the minimum allowed interval.
        // During debug, we use 0 so every launch re-fetches immediately.
        minimumFetchInterval:
            kReleaseMode ? const Duration(hours: 1) : Duration.zero,
      ));

      // Safe default: 0 means the check is a no-op if Remote Config
      // is unreachable on first launch.
      await remoteConfig.setDefaults(const {_minBuildKey: 0});

      await remoteConfig.fetchAndActivate();

      final minBuild = remoteConfig.getInt(_minBuildKey);
      if (minBuild == 0) return false; // Remote Config not yet configured

      final info = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(info.buildNumber) ?? 0;

      debugPrint(
        '[ForceUpdate] current=$currentBuild, required=$minBuild, '
        'needsUpdate=${currentBuild < minBuild}',
      );

      return currentBuild < minBuild;
    } catch (e) {
      // Never block the user if the check fails (e.g. device is offline,
      // Remote Config quota exceeded, etc.)
      debugPrint('[ForceUpdate] Check skipped due to error: $e');
      return false;
    }
  }
}
