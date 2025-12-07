import 'package:flutter/services.dart';

class NativeBlocker {
  static const MethodChannel _channel = MethodChannel('com.example.focus_mate/blocker');

  /// Updates the list of apps blocked by the USER.
  /// This list is stored separately from the companion's list.
  static Future<void> setBlockedApps(List<String> packageNames) async {
    try {
      await _channel.invokeMethod('setBlockedApps', {'apps': packageNames});
      print("FocusMate: User block list updated: $packageNames");
    } on PlatformException catch (e) {
      print("FocusMate: Failed to update user list: '${e.message}'.");
    }
  }

  /// Updates the list of apps blocked by the COMPANION.
  /// Call this when your Firestore listener detects a change.
  static Future<void> setCompanionBlockedApps(List<String> packageNames) async {
    try {
      await _channel.invokeMethod('setCompanionBlockedApps', {'apps': packageNames});
      print("FocusMate: Companion block list updated: $packageNames");
    } on PlatformException catch (e) {
      print("FocusMate: Failed to update companion list: '${e.message}'.");
    }
  }

  /// Checks if the Accessibility Service is currently enabled in Android Settings.
  static Future<bool> isAccessibilityEnabled() async {
    try {
      final bool result = await _channel.invokeMethod('isAccessibilityEnabled');
      return result;
    } on PlatformException catch (e) {
      print("FocusMate: Failed to check permission: '${e.message}'.");
      return false;
    }
  }
}