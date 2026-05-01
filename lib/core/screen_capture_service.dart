import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ScreenCaptureService {
  static const platform = MethodChannel('com.example.focus_mate/blocker');

  /// Checks if the native SnapshotService is currently running.
  static Future<bool> isServiceRunning() async {
    try {
      final bool result = await platform.invokeMethod(
        'isSnapshotServiceRunning',
      );
      return result;
    } on PlatformException catch (e) {
      debugPrint("Failed to check service status: '${e.message}'.");
      return false;
    }
  }

  static Future<bool> requestPermission() async {
    try {
      final bool result = await platform.invokeMethod(
        'requestScreenCapturePermission',
      );
      return result;
    } on PlatformException catch (e) {
      debugPrint("Failed to request permission: '${e.message}'.");
      return false;
    }
  }

  static Future<Uint8List?> captureScreen() async {
    try {
      final Uint8List result = await platform.invokeMethod('captureScreen');
      return result;
    } on PlatformException catch (e) {
      debugPrint("Failed to capture screen: '${e.message}'.");
      return null;
    }
  }

  static Future<void> stopService() async {
    try {
      await platform.invokeMethod('stopScreenCaptureService');
    } on PlatformException catch (e) {
      debugPrint("Failed to stop service: '${e.message}'.");
    }
  }
}
