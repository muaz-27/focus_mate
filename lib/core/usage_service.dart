import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:installed_apps/installed_apps.dart'; // ✅ Using your preferred package
import 'package:installed_apps/app_info.dart';

class UsageService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<bool> hasPermission() async {
    final result = await UsageStats.checkUsagePermission();
    return result ?? false;
  }

  Future<void> requestPermission() async {
    await UsageStats.grantUsagePermission();
  }

  // Helper to filter system junk
  bool _isIgnoredApp(String packageName) {
    final List<String> ignored = [
      'com.android.systemui',
      'com.google.android.googlequicksearchbox',
      'com.osp.app.signin',
      'com.samsung.android.incallui',
      'com.sec.android.app.launcher',
      'com.google.android.gms',
      'android',
    ];
    if (packageName.startsWith('com.android.providers')) return true;
    if (packageName.contains('overlay')) return true;
    return ignored.contains(packageName);
  }

  Future<void> syncUsageToFirebase(String userId) async {
    try {
      if (!await hasPermission()) return;

      DateTime end = DateTime.now();
      DateTime start = end.subtract(const Duration(hours: 24));

      // 1. Fetch Raw Stats from Android
      List<UsageInfo> rawStats = await UsageStats.queryUsageStats(start, end);

      // ---------------------------------------------------------
      // 🔹 STEP 1: AGGREGATE DUPLICATES
      // We sum up time for apps that appear multiple times
      // ---------------------------------------------------------
      Map<String, double> appUsageMap = {};

      for (var info in rawStats) {
        if (info.packageName == null) continue;

        double ms = double.tryParse(info.totalTimeInForeground ?? "0") ?? 0;

        if (appUsageMap.containsKey(info.packageName)) {
          appUsageMap[info.packageName!] = appUsageMap[info.packageName!]! + ms;
        } else {
          appUsageMap[info.packageName!] = ms;
        }
      }

      // 2. Fetch Real App Names using installed_apps
      // We fetch the whole list once to create a lookup map (Much faster)
      List<AppInfo> installedApps = await InstalledApps.getInstalledApps(
        true,
        true,
      );

      Map<String, String> appNameMap = {
        for (var app in installedApps) app.packageName: app.name ?? "Unknown",
      };

      // 3. Process & Filter
      List<Map<String, dynamic>> processedApps = [];
      int totalMinutes = 0;

      for (var entry in appUsageMap.entries) {
        String pkg = entry.key;
        double totalMs = entry.value;
        int minutes = (totalMs / 1000 / 60).round();

        // Filter: Usage > 1 minute AND not ignored
        if (minutes > 1 && !_isIgnoredApp(pkg)) {
          // Get Real Name from our map
          String realName = appNameMap[pkg] ?? pkg;

          // Manual Fixes for common apps
          if (pkg == 'com.google.android.youtube') realName = 'YouTube';
          if (pkg == 'com.instagram.android') realName = 'Instagram';
          if (pkg == 'com.whatsapp') realName = 'WhatsApp';
          if (pkg == 'com.snapchat.android') realName = 'Snapchat';

          totalMinutes += minutes;
          processedApps.add({
            'appName': realName,
            'packageName': pkg,
            'usageMs': totalMs.toInt(),
            'usageMinutes': minutes,
          });
        }
      }

      // Sort by usage
      processedApps.sort(
        (a, b) => b['usageMinutes'].compareTo(a['usageMinutes']),
      );

      // 4. Upload
      final todayDocId = DateTime.now().toIso8601String().split('T')[0];

      print(
        "✅ Uploading Sync: $totalMinutes mins, ${processedApps.length} apps.",
      );

      await _firestore
          .collection('users')
          .doc(userId)
          .collection('daily_stats')
          .doc(todayDocId)
          .set({
            'lastUpdated': FieldValue.serverTimestamp(),
            'totalScreenTime': totalMinutes,
            'apps': processedApps,
          }, SetOptions(merge: true));
    } catch (e) {
      print("❌ Error syncing usage: $e");
    }
  }
}
