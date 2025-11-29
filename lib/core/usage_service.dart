import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'dart:convert';


class UsageService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 🔹 Check permission
  Future<bool> hasPermission() async {
    final result = await UsageStats.checkUsagePermission();
    return result ?? false;
  }

  // 🔹 Request permission
  Future<void> requestPermission() async {
    await UsageStats.grantUsagePermission();
  }

  // 🔹 Ignore useless background/system packages
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

  // 🔹 Fetch all installed apps (with icons)
  Future<List<AppInfo>> getInstalledAppsList() async {
    try {
      return await InstalledApps.getInstalledApps(true, true); // include icons = true
    } catch (e) {
      print("❌ Error fetching installed apps: $e");
      return [];
    }
  }

  // 🔹 MAIN FUNCTION — Sync usage to Firebase
  Future<void> syncUsageToFirebase(String userId) async {
    try {
      if (!await hasPermission()) return;

      DateTime end = DateTime.now();
      DateTime start = DateTime(end.year, end.month, end.day);

      // 1️⃣ Fetch Raw Usage Stats
      List<UsageInfo> rawStats = await UsageStats.queryUsageStats(start, end);

      // 2️⃣ Aggregate usage per app
      Map<String, double> appUsageMap = {};
      for (var info in rawStats) {
        if (info.packageName == null) continue;

        double ms = double.tryParse(info.totalTimeInForeground ?? "0") ?? 0;

        if (appUsageMap.containsKey(info.packageName)) {
          appUsageMap[info.packageName!] =
              appUsageMap[info.packageName!]! + ms;
        } else {
          appUsageMap[info.packageName!] = ms;
        }
      }

      // 3️⃣ Fetch Installed Apps with Icons
      List<AppInfo> installedApps = await getInstalledAppsList();

      Map<String, String> appNameMap = {
        for (var app in installedApps)
          app.packageName: app.name ?? "Unknown",
      };

      Map<String, String> appIconMap = {
        for (var app in installedApps)
          if (app.icon != null)
            app.packageName: base64Encode(app.icon!)
      };

      // 4️⃣ Convert & Filter
      List<Map<String, dynamic>> processedApps = [];
      int totalMinutes = 0;

      for (var entry in appUsageMap.entries) {
        String pkg = entry.key;
        double totalMs = entry.value;
        int minutes = (totalMs / 1000 / 60).round();

        if (minutes >= 1 && !_isIgnoredApp(pkg)) {
          String realName = appNameMap[pkg] ?? pkg;
          String? iconBase64 = appIconMap[pkg];

          // Manual cleaning of names
          if (pkg == 'com.google.android.youtube') realName = 'YouTube';
          if (pkg == 'com.whatsapp') realName = 'WhatsApp';
          if (pkg == 'com.instagram.android') realName = 'Instagram';

          totalMinutes += minutes;

          processedApps.add({
            'appName': realName,
            'packageName': pkg,
            'usageMs': totalMs.toInt(),
            'usageMinutes': minutes,
            'iconBytes': iconBase64, // 🔹 icon included!
          });
        }
      }

      // Sort by usage descending
      processedApps.sort((a, b) => b['usageMinutes'].compareTo(a['usageMinutes']));

      // 5️⃣ Upload to Firebase
      final todayDocId = DateTime.now().toIso8601String().split('T')[0];

      print("📤 Uploading Stats ($totalMinutes mins) with icons.");

      await _firestore
          .collection('users')
          .doc(userId)
          .collection('daily_stats')
          .doc(todayDocId)
          .set({
        'lastUpdated': FieldValue.serverTimestamp(),
        'totalScreenTime': totalMinutes,
        'apps': processedApps,
      });

      print("✅ Upload success.");
    } catch (e) {
      print("❌ Error syncing usage: $e");
    }
  }
}
