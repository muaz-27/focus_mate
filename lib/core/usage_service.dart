import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:device_apps/device_apps.dart';
import 'dart:convert';


class UsageService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Check if the user has given us permission to see app usage
  Future<bool> hasPermission() async {
    final result = await UsageStats.checkUsagePermission();
    return result ?? false;
  }

  // Ask the user for permission
  Future<void> requestPermission() async {
    await UsageStats.grantUsagePermission();
  }

  // We don't want to track system apps, so we ignore them
  bool _isIgnoredApp(String packageName) {
    final List<String> ignored = [
      'com.android.systemui',
      'com.google.android.googlequicksearchbox',
      'com.osp.app.signin',
      'com.samsung.android.incallui',
      'com.sec.android.app.launcher',
      'com.google.android.gms',
      'android',
      'com.android.traceur', // System Tracing
    ];

    if (packageName.startsWith('com.android.providers')) return true;
    if (packageName.contains('overlay')) return true;

    return ignored.contains(packageName);
  }

  // Get a list of all apps installed on the phone
  Future<List<Application>> getInstalledAppsList() async {
    try {
      final apps = await DeviceApps.getInstalledApplications(
        includeAppIcons: true,
        includeSystemApps: true,
        onlyAppsWithLaunchIntent: true,
      );
      // Filter out ignored apps immediately so they don't show in App Lock or Analytics
      return apps.where((app) => !_isIgnoredApp(app.packageName)).toList();
    } catch (e) {
      print("❌ Error fetching installed apps: $e");
      return [];
    }
  }

  // This is the main function that sends usage data to the database
  Future<void> syncUsageToFirebase(String userId) async {
    try {
      if (!await hasPermission()) return;

      DateTime end = DateTime.now();
      DateTime start = DateTime(end.year, end.month, end.day);

      // 1. Get detailed event data for precise calculation
      // 'queryEvents' gives us a stream of exactly when apps were opened/closed.
      // We calculate the duration manually to ensure we ONLY count time after Midnight.
      List<EventUsageInfo> events = await UsageStats.queryEvents(start, end);

      // 2. Calculate duration from events
      Map<String, double> appUsageMap = {};
      Map<String, int> currentOpenStartTime = {};

      for (var event in events) {
        int type = int.tryParse(event.eventType ?? "0") ?? 0;
        int time = int.tryParse(event.timeStamp ?? "0") ?? 0;
        String? pkg = event.packageName;

        if (pkg == null) continue;

        if (type == 1) { // MOVE_TO_FOREGROUND
          currentOpenStartTime[pkg] = time;
        } else if (type == 2) { // MOVE_TO_BACKGROUND
          if (currentOpenStartTime.containsKey(pkg)) {
            int startTime = currentOpenStartTime[pkg]!;
            // Add the duration
            double duration = (time - startTime).toDouble();
            appUsageMap[pkg] = (appUsageMap[pkg] ?? 0) + duration;
            
            // Clear the start time as the session ended
            currentOpenStartTime.remove(pkg);
          }
        }
      }

      // Handle apps that are currently open (Foreground but no Background event yet)
      for (var entry in currentOpenStartTime.entries) {
        String pkg = entry.key;
        int startTime = entry.value;
        // Add time from start until Now
        double duration = (end.millisecondsSinceEpoch - startTime).toDouble();
        appUsageMap[pkg] = (appUsageMap[pkg] ?? 0) + duration;
      }

      // 3. Get app names and icons from our "Launchable" list
      List<Application> installedApps = await getInstalledAppsList();

      // 4. Resolve missing apps
      // Some apps (like background services or specific helpers) might have usage
      // but NOT have a launch intent, so they aren't in `installedApps`.
      // We want to fetch their real names to avoid "com.blabla.bla" in analytics.
      Set<String> knownPackages = installedApps.map((a) => a.packageName).toSet();
      Set<String> usedPackages = appUsageMap.keys.toSet();
      Set<String> missingPackages = usedPackages.difference(knownPackages);

      for (String pkg in missingPackages) {
        // Only fetch if it has significant usage (> 1 min) and isn't ignored
        double usageMs = appUsageMap[pkg] ?? 0;
        if ((usageMs / 1000 / 60) >= 1 && !_isIgnoredApp(pkg)) {
           try {
             // Try to fetch specific app details
             Application? app = await DeviceApps.getApp(pkg, true);
             if (app != null) {
               installedApps.add(app);
             }
           } catch (e) {
             print("Could not fetch info for missing pkg: $pkg");
           }
        }
      }

      Map<String, String> appNameMap = {
        for (var app in installedApps)
          app.packageName: app.appName,
      };

      Map<String, String> appIconMap = {
        for (var app in installedApps)
          if (app is ApplicationWithIcon)
            app.packageName: base64Encode(app.icon)
      };

      // 5. Prepare the data for upload
      List<Map<String, dynamic>> processedApps = [];
      int totalMinutes = 0;

      for (var entry in appUsageMap.entries) {
        String pkg = entry.key;
        double totalMs = entry.value;
        int minutes = (totalMs / 1000 / 60).round();

        if (minutes >= 1 && !_isIgnoredApp(pkg)) {
          String realName = appNameMap[pkg] ?? pkg;
          String? iconBase64 = appIconMap[pkg];

          // Fix some common app names
          if (pkg == 'com.google.android.youtube') realName = 'YouTube';
          if (pkg == 'com.whatsapp') realName = 'WhatsApp';
          if (pkg == 'com.instagram.android') realName = 'Instagram';

          totalMinutes += minutes;

          processedApps.add({
            'appName': realName,
            'packageName': pkg,
            'usageMs': totalMs.toInt(),
            'usageMinutes': minutes,
            'iconBytes': iconBase64, // We include the icon here
          });
        }
      }

      // Sort so the most used apps are at the top
      processedApps.sort((a, b) => b['usageMinutes'].compareTo(a['usageMinutes']));

      // 6. Send everything to Firebase
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

  // NEW: Get the total usage minutes locally for immediate UI display
  Future<int> getTodayUsageMinutes() async {
    try {
      if (!await hasPermission()) return 0;

      DateTime end = DateTime.now();
      DateTime start = DateTime(end.year, end.month, end.day);
      
      List<EventUsageInfo> events = await UsageStats.queryEvents(start, end);
      Map<String, double> appUsageMap = {};
      Map<String, int> currentOpenStartTime = {};

      for (var event in events) {
         int type = int.tryParse(event.eventType ?? "0") ?? 0;
         int time = int.tryParse(event.timeStamp ?? "0") ?? 0;
         String? pkg = event.packageName;
         if (pkg == null) continue;

         if (type == 1) { // MOVE_TO_FOREGROUND
           currentOpenStartTime[pkg] = time;
         } else if (type == 2) { // MOVE_TO_BACKGROUND
           if (currentOpenStartTime.containsKey(pkg)) {
             int startTime = currentOpenStartTime[pkg]!;
             appUsageMap[pkg] = (appUsageMap[pkg] ?? 0) + (time - startTime);
             currentOpenStartTime.remove(pkg);
           }
         }
      }

      for (var entry in currentOpenStartTime.entries) {
        double duration = (end.millisecondsSinceEpoch - entry.value).toDouble();
        appUsageMap[entry.key] = (appUsageMap[entry.key] ?? 0) + duration;
      }

      int totalMinutes = 0;
      for (var entry in appUsageMap.entries) {
        String pkg = entry.key;
        int minutes = (entry.value / 1000 / 60).round();
        if (minutes >= 1 && !_isIgnoredApp(pkg)) {
           totalMinutes += minutes;
        }
      }
      return totalMinutes;
    } catch (e) {
      print("Error calculating usage: $e");
      return 0;
    }
  }

  // NEW: Sync the full list of installed apps (names + package names) to Firestore
  // This allows the companion to see apps even if they don't have them installed.
  Future<void> syncInstalledAppsToFirebase(String userId) async {
    try {
      List<Application> apps = await getInstalledAppsList();
      
      // We only upload names and package names to save bandwidth/space.
      // Icons are heavy and might exceed Firestore 1MB limit for a full list.
      // UPDATE: User requested icons. We will try to include them. 
      // Risk: Document size limit.
      List<Map<String, String>> appList = apps.map((app) {
        String? iconBase64;
        if (app is ApplicationWithIcon) {
          iconBase64 = base64Encode(app.icon);
        }
        
        return {
          'packageName': app.packageName,
          'appName': app.appName,
          if (iconBase64 != null) 'iconBytes': iconBase64,
        };
      }).toList();

      appList.sort((a, b) => a['appName']!.toLowerCase().compareTo(b['appName']!.toLowerCase()));

      await _firestore.collection('users').doc(userId).update({
        'installedApps': appList,
        'installedAppsLastUpdated': FieldValue.serverTimestamp(),
      });
      
      print("✅ Synced ${appList.length} installed apps to Firestore.");
    } catch (e) {
      print("❌ Error syncing installed apps: $e");
    }
  }
}
