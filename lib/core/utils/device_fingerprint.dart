import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeviceFingerprint {
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  /// Gets a unique persistent UUID for this device, generating it if it doesn't exist.
  static Future<String> getDeviceUuid() async {
    final prefs = await SharedPreferences.getInstance();
    const key = 'gk_device_uuid';
    String? uuid = prefs.getString(key);
    if (uuid == null || uuid.isEmpty) {
      uuid = const Uuid().v4();
      await prefs.setString(key, uuid);
    }
    return uuid;
  }

  /// Generates a human-readable name of the device.
  static Future<String> getDeviceName() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        return '${androidInfo.manufacturer} ${androidInfo.model}';
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        return iosInfo.name;
      }
    } catch (_) {}
    return 'Unknown Device';
  }

  /// Calculates a stable hardware/software device fingerprint.
  static Future<String> getDeviceFingerprint() async {
    final uuid = await getDeviceUuid();
    final name = await getDeviceName();
    final os = Platform.isAndroid ? 'Android' : 'iOS';
    final osVersion = Platform.operatingSystemVersion;
    
    // Create a composite string and hash/strip it to make a clean fingerprint ID
    final rawFingerprint = '${os}_${name}_${uuid}_$osVersion';
    return rawFingerprint.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
  }

  /// Gets full device metadata for registration.
  static Future<Map<String, dynamic>> getDeviceDetails() async {
    final fingerprint = await getDeviceFingerprint();
    final name = await getDeviceName();
    final uuid = await getDeviceUuid();
    
    return {
      'fingerprint': fingerprint,
      'name': name,
      'uuid': uuid,
      'os': Platform.isAndroid ? 'Android' : 'iOS',
      'os_version': Platform.operatingSystemVersion,
      'last_active': FieldValue.serverTimestamp(),
      'registered_at': FieldValue.serverTimestamp(),
      'is_trusted': true,
    };
  }

  /// Registers the current device fingerprint in Firestore if not already registered.
  static Future<void> registerDevice(String userId) async {
    try {
      final details = await getDeviceDetails();
      final fingerprint = details['fingerprint'] as String;

      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('trusted_devices')
          .doc(fingerprint);

      final doc = await docRef.get();
      if (!doc.exists) {
        await docRef.set(details);
      } else {
        await docRef.update({
          'last_active': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      // Fail silently to prevent interrupting core login flow
      debugPrint('[DeviceFingerprint] Failed to register device fingerprint: $e');
    }
  }

  /// Validates if the current device is registered and trusted for this user.
  static Future<bool> isDeviceTrusted(String userId) async {
    try {
      final fingerprint = await getDeviceFingerprint();
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('trusted_devices')
          .doc(fingerprint)
          .get();
      
      return doc.exists && (doc.data()?['is_trusted'] == true);
    } catch (_) {
      return false;
    }
  }
}
