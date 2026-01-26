import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:device_apps/device_apps.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart'; // For debugPrint

class UsageService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Checks if the user has granted usage stats permission.
  Future<bool> hasPermission() async {
    final result = await UsageStats.checkUsagePermission();
    return result ?? false;
  }

  /// Prompts the user to grant usage stats permission.
  Future<void> requestPermission() async {
    await UsageStats.grantUsagePermission();
  }

  /// Determines if an app should be ignored (system apps, launchers, etc.).
  bool _isIgnoredApp(String packageName) {
    final List<String> ignored = [
      'com.android.systemui',
      'com.google.android.googlequicksearchbox',
      'com.osp.app.signin',
      'com.samsung.android.incallui',
      'com.sec.android.app.launcher',
      'com.google.android.gms',
      'android',
      'com.android.traceur',
    ];

    if (packageName.startsWith('com.android.providers')) return true;
    if (packageName.contains('overlay')) return true;

    return ignored.contains(packageName);
  }

  /// Retrieves a filtered list of installed applications.
  Future<List<Application>> getInstalledAppsList() async {
    try {
      final apps = await DeviceApps.getInstalledApplications(
        includeAppIcons: true,
        includeSystemApps: true,
        onlyAppsWithLaunchIntent: true,
      );
      return apps.where((app) => !_isIgnoredApp(app.packageName)).toList();
    } catch (e) {
      debugPrint("Error fetching installed apps: $e");
      return [];
    }
  }

  /// Syncs daily usage statistics to Firestore.
  /// 
  /// Calculates precise duration by analyzing MOVE_TO_FOREGROUND and MOVE_TO_BACKGROUND events.
  Future<void> syncUsageToFirebase(String userId) async {
    try {
      if (!await hasPermission()) return;

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
            double duration = (time - startTime).toDouble();
            appUsageMap[pkg] = (appUsageMap[pkg] ?? 0) + duration;
            currentOpenStartTime.remove(pkg);
          }
        }
      }

      // Handle currently open apps
      for (var entry in currentOpenStartTime.entries) {
        String pkg = entry.key;
        int startTime = entry.value;
        double duration = (end.millisecondsSinceEpoch - startTime).toDouble();
        appUsageMap[pkg] = (appUsageMap[pkg] ?? 0) + duration;
      }

      List<Application> installedApps = await getInstalledAppsList();
      Set<String> knownPackages = installedApps.map((a) => a.packageName).toSet();
      Set<String> usedPackages = appUsageMap.keys.toSet();
      Set<String> missingPackages = usedPackages.difference(knownPackages);

      for (String pkg in missingPackages) {
        double usageMs = appUsageMap[pkg] ?? 0;
        if ((usageMs / 1000 / 60) >= 1 && !_isIgnoredApp(pkg)) {
           try {
             Application? app = await DeviceApps.getApp(pkg, true);
             if (app != null) {
               installedApps.add(app);
             }
           } catch (e) {
             debugPrint("Could not fetch info for missing pkg: $pkg");
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

      List<Map<String, dynamic>> processedApps = [];
      int totalMinutes = 0;

      for (var entry in appUsageMap.entries) {
        String pkg = entry.key;
        double totalMs = entry.value;
        int minutes = (totalMs / 1000 / 60).round();

        if (minutes >= 1 && !_isIgnoredApp(pkg)) {
          String realName = appNameMap[pkg] ?? pkg;
          String? iconBase64 = appIconMap[pkg];

          // Normalize common package names
          if (pkg == 'com.google.android.youtube') realName = 'YouTube';
          if (pkg == 'com.whatsapp') realName = 'WhatsApp';
          if (pkg == 'com.instagram.android') realName = 'Instagram';

          totalMinutes += minutes;

          processedApps.add({
            'appName': realName,
            'packageName': pkg,
            'usageMs': totalMs.toInt(),
            'usageMinutes': minutes,
            'iconBytes': iconBase64,
          });
        }
      }

      processedApps.sort((a, b) => b['usageMinutes'].compareTo(a['usageMinutes']));

      final todayDocId = DateTime.now().toIso8601String().split('T')[0];

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

    } catch (e) {
      debugPrint("Error syncing usage: $e");
    }
  }

  /// Calculates total usage minutes for the current day locally.
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

         if (type == 1) {
           currentOpenStartTime[pkg] = time;
         } else if (type == 2) {
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
      debugPrint("Error calculating usage: $e");
      return 0;
    }
  }

  /// Syncs installed application metadata (name, package, icon) to Firestore.
  /// 
  /// Used to allow the companion app to view and manage apps even if they are not installed on the companion device.
  Future<void> syncInstalledAppsToFirebase(String userId) async {
    try {
      List<Application> apps = await getInstalledAppsList();
      
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
      
    } catch (e) {
      debugPrint("Error syncing installed apps: $e");
    }
  }
}
