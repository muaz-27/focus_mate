import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:installed_apps/installed_apps.dart';
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

  Future<List<AppInfo>> getInstalledAppsList() async {
    try {
      return await InstalledApps.getInstalledApps(true, false);
    } catch (e) {
      print("Error fetching apps: $e");
      return [];
    }
  }

  // 🔹 MAIN SYNC FUNCTION
  Future<void> syncUsageToFirebase(String userId) async {
    try {
      if (!await hasPermission()) return;

      DateTime end = DateTime.now();
      DateTime start = DateTime(end.year, end.month, end.day);

      // 1. Fetch Raw Stats
      List<UsageInfo> rawStats = await UsageStats.queryUsageStats(start, end);

      // 2. Aggregate Duplicates
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

      // 3. Fetch App Names
      List<AppInfo> installedApps = await InstalledApps.getInstalledApps(true, false);
      Map<String, String> appNameMap = {
        for (var app in installedApps) app.packageName: app.name ?? "Unknown",
      };

      // 4. Process & Filter
      List<Map<String, dynamic>> processedApps = [];
      int totalMinutes = 0;

      for (var entry in appUsageMap.entries) {
        String pkg = entry.key;
        double totalMs = entry.value;
        int minutes = (totalMs / 1000 / 60).round();

        if (minutes >= 1 && !_isIgnoredApp(pkg)) {
          String realName = appNameMap[pkg] ?? pkg;

          // Manual Fixes
          if (pkg == 'com.google.android.youtube') realName = 'YouTube';
          if (pkg == 'com.whatsapp') realName = 'WhatsApp';
          if (pkg == 'com.instagram.android') realName = 'Instagram';

          totalMinutes += minutes;
          processedApps.add({
            'appName': realName,
            'packageName': pkg,
            'usageMs': totalMs.toInt(),
            'usageMinutes': minutes,
          });
        }
      }

      processedApps.sort((a, b) => b['usageMinutes'].compareTo(a['usageMinutes']));

      // 5. Upload (Overwrite previous stats)
      final todayDocId = DateTime.now().toIso8601String().split('T')[0];

      print("✅ Uploading Today's Stats: $totalMinutes mins.");

      await _firestore
          .collection('users')
          .doc(userId)
          .collection('daily_stats')
          .doc(todayDocId)
          .set({
        'lastUpdated': FieldValue.serverTimestamp(),
        'totalScreenTime': totalMinutes,
        'apps': processedApps,
      }); // Removed merge to overwrite
    } catch (e) {
      print("❌ Error syncing usage: $e");
    }
  }
}
