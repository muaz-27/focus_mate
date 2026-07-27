import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:focus_mate/core/screen_capture_service.dart';

class PermissionManager {
  static const MethodChannel _channel = MethodChannel('com.example.focus_mate/blocker');

  /// Tracks whether the user has already acknowledged the data-collection
  /// consent dialog in this app session. Reset to false on cold start.
  static bool _consentAcknowledged = false;

  /// Shows a one-time consent dialog disclosing data-collection practices.
  /// Returns [true] if the user taps "I Agree", [false] if they cancel.
  static Future<bool> _showConsentDialogIfNeeded(BuildContext context) async {
    if (_consentAcknowledged) return true;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final agreed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          "Data & Privacy Notice",
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          "This app collects device usage statistics and screen captures "
          "during active study schedules to enable linked parents/companions "
          "to monitor academic progress and block distracting apps.",
          style: TextStyle(
            color: isDark ? Colors.white70 : Colors.black54,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              "Cancel",
              style: TextStyle(
                color: isDark ? Colors.grey : Colors.grey.shade600,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("I Agree"),
          ),
        ],
      ),
    );

    final userAgreed = agreed ?? false;
    if (userAgreed) _consentAcknowledged = true;
    return userAgreed;
  }

  // Check if we have permission to see app usage, if not, ask for it
  static Future<bool> checkUsageStats(BuildContext context) async {
    bool granted = (await UsageStats.checkUsagePermission()) ?? false;
    if (granted) return true;

    if (context.mounted) {
      // Show consent dialog before redirecting to Android Settings
      final agreed = await _showConsentDialogIfNeeded(context);
      if (!agreed || !context.mounted) return false;

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
        // Show consent dialog before redirecting to Android Settings
        final agreed = await _showConsentDialogIfNeeded(context);
        if (!agreed || !context.mounted) return false;

        await _showDialogAsync(
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
        // Show consent dialog before redirecting to Android Settings
        final agreed = await _showConsentDialogIfNeeded(context);
        if (!agreed || !context.mounted) return false;

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
        // Show consent dialog before redirecting to Android Settings
        final agreed = await _showConsentDialogIfNeeded(context);
        if (!agreed || !context.mounted) return false;

        await _showDialogAsync(
          context,
          "Allow Background Activity",
          "To keep the app lock active even when you close the app, please allow FocusMate to ignore battery optimizations.",
          () => openAppSettings(),
        );
      }
    }
    return false;
  }

  /// Runs all parental-mode permissions sequentially so the user
  /// sees one dialog at a time instead of a confusing stack.
  ///
  /// Order: Accessibility → Battery Optimization → Screen Capture
  static Future<void> runParentalPermissionFlow(BuildContext context) async {
    // 1. Accessibility Service
    await checkAccessibility(context);
    // Small delay to let the Settings app open/close before next prompt
    await Future.delayed(const Duration(milliseconds: 800));

    if (!context.mounted) return;

    // 2. Battery Optimizations
    await checkBatteryOptimizations(context);
    await Future.delayed(const Duration(milliseconds: 500));

    if (!context.mounted) return;

    // 3. Screen Capture Permission (MediaProjection)
    final bool serviceRunning = await ScreenCaptureService.isServiceRunning();
    if (!serviceRunning) {
      await ScreenCaptureService.requestPermission();
    }
  }

  // A helper function to show a dialog box that asks the user to open settings
  static void _showDialog(
    BuildContext context,
    String title,
    String content,
    VoidCallback onRedirect,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
        content: Text(content, style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("Cancel", style: TextStyle(color: isDark ? Colors.grey : Colors.grey.shade600)),
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

  /// Async version of _showDialog that awaits until the dialog is dismissed.
  /// This is used by the sequential permission flow.
  static Future<void> _showDialogAsync(
    BuildContext context,
    String title,
    String content,
    VoidCallback onRedirect,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
        content: Text(content, style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("Cancel", style: TextStyle(color: isDark ? Colors.grey : Colors.grey.shade600)),
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
