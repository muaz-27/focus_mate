import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';

class PermissionManager {
  static const MethodChannel _channel = MethodChannel('com.example.focus_mate/blocker');

  // Check if we have permission to see app usage, if not, ask for it
  static Future<bool> checkUsageStats(BuildContext context) async {
    bool granted = (await UsageStats.checkUsagePermission()) ?? false;
    if (granted) return true;

    if (context.mounted) {
      _showDialog(
        context,
        "Usage Access Required",
        "To track your screen time and app usage, FocusMate needs usage access permissions.",
        () => UsageStats.grantUsagePermission(),
      );
    }
    return false;
  }

  // Check if the accessibility service is on, this is needed for app blocking
  static Future<bool> checkAccessibility(BuildContext context) async {
    try {
      final bool enabled = await _channel.invokeMethod('isAccessibilityServiceAlive');
      if (enabled) return true;

      if (context.mounted) {
        _showDialog(
          context,
          "Accessibility Service Required",
          "To block distracting apps effectively, FocusMate needs Accessibility permissions.",
          () {
            const AndroidIntent intent = AndroidIntent(
              action: 'android.settings.ACCESSIBILITY_SETTINGS',
              flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
            );
            intent.launch();
          },
        );
      }
      return false;
    } catch (e) {
      debugPrint("Error checking accessibility: $e");
      return false;
    }
  }

  // Check if we can show notifications
  static Future<bool> checkNotification(BuildContext context) async {
    if (await Permission.notification.isGranted) return true;

    if (context.mounted) {
      // We can request directly first, if denied then show dialog
      PermissionStatus status = await Permission.notification.request();
      if (status.isGranted) return true;

      if (context.mounted) {
        _showDialog(
          context,
          "Notifications Required",
          "To keep the app lock active in the background, please enable notifications.",
          () => openAppSettings(),
        );
      }
    }
    return false;
  }

  // Check if we can run in the background without being killed
  static Future<bool> checkBatteryOptimizations(BuildContext context) async {
    if (await Permission.ignoreBatteryOptimizations.isGranted) return true;

    if (context.mounted) {
      PermissionStatus status = await Permission.ignoreBatteryOptimizations.request();
      if (status.isGranted) return true;

      if (context.mounted) {
        _showDialog(
          context,
          "Allow Background Activity",
          "To keep the app lock active even when you close the app, please allow FocusMate to ignore battery optimizations.",
          () => openAppSettings(),
        );
      }
    }
    return false;
  }

  // A helper function to show a dialog box that asks the user to open settings
  static void _showDialog(
    BuildContext context,
    String title,
    String content,
    VoidCallback onRedirect,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(content, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              onRedirect();
            },
            child: const Text("Open Settings"),
          ),
        ],
      ),
    );
  }
}

