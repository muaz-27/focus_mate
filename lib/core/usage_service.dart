import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:device_apps/device_apps.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart'; // For debugPrint
import 'package:flutter_image_compress/flutter_image_compress.dart';

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
        includeSystemApps: false,
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

      // OPTIMIZATION: Do not save icons in daily stats to save bandwidth/storage.
      // Icons are now looked up from the master list in users/{id}/data/installed_apps
      final appsForDailyStats = processedApps.map((app) {
        final newMap = Map<String, dynamic>.from(app);
        newMap.remove('iconBytes');
        return newMap;
      }).toList();

      await _firestore
          .collection('users')
          .doc(userId)
          .collection('daily_stats')
          .doc(todayDocId)
          .set({
        'lastUpdated': FieldValue.serverTimestamp(),
        'totalScreenTime': totalMinutes,
        'apps': appsForDailyStats, // usage stats without icons
      });

      // Award Study Passes: 1 pass per 30 mins
      final userRef = _firestore.collection('users').doc(userId);
      final userSnap = await userRef.get();
      if (userSnap.exists) {
        final userData = userSnap.data() as Map<String, dynamic>;
        
        // This is today's total study time
        final int oldStudyTime = userData['studyTime'] ?? 0;
        final int delta = totalMinutes - oldStudyTime;
        
        if (delta > 0) {
          int passesCount = userData['passes'] ?? 0;
          int pool = (userData['minutesTowardsNextPass'] ?? 0) + delta;
          
          int earned = pool ~/ 30;
          int remaining = pool % 30;
          
          await userRef.update({
            'studyTime': totalMinutes,
            'passes': passesCount + earned,
            'minutesTowardsNextPass': remaining,
          });
          
          if (earned > 0) {
            debugPrint("F_MATE: User earned $earned Study Pass(es)!");
          }
        }
      }

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
  /// MOVED: Writes to `users/{userId}/data/installed_apps` to reduce load on the main user document.
  /// Syncs installed application metadata (name, package, icon) to Firestore.
  /// 
  /// NEW: Uses SHARDING to split the list into multiple documents in `users/{userId}/data_v2`.
  /// This prevents hitting the Firestore 1MB document limit.
  Future<void> syncInstalledAppsToFirebase(String userId) async {
    try {
      List<Application> apps = await getInstalledAppsList();
      
      // OPTIMIZATION: Diff-check installed apps using a hash
      final List<String> pNames = apps.map((a) => a.packageName).toList();
      pNames.sort();
      final String packageNames = pNames.join(',');
      final int packageHash = packageNames.hashCode;
      
      final prefs = await SharedPreferences.getInstance();
      final int lastHash = prefs.getInt('last_synced_apps_hash_$userId') ?? 0;
      
      if (lastHash == packageHash) {
        debugPrint("F_MATE: Installed apps unchanged (hash match). Skipping sync.");
        return;
      }

      debugPrint("F_MATE: Starting App Sync for ${apps.length} apps...");

      // 1. Prepare Metadata List (No Icons)
      List<Map<String, String>> metadataList = [];
      
      // 2. Prepare Icons for separate upload
      Map<String, String> iconMap = {};

      for (var app in apps) {
        metadataList.add({
          'packageName': app.packageName,
          'appName': app.appName,
        });

        if (app is ApplicationWithIcon) {
          try {
            var compressed = await FlutterImageCompress.compressWithList(
              app.icon,
              minHeight: 48,
              minWidth: 48,
              quality: 50, 
              format: CompressFormat.png, 
            );
            if (compressed.isNotEmpty) {
               iconMap[app.packageName] = base64Encode(compressed);
            }
          } catch (e) {
            // Ignore compression errors
          }
        }
      }

      metadataList.sort((a, b) => a['appName']!.toLowerCase().compareTo(b['appName']!.toLowerCase()));

      // 3. Upload Metadata Shards (data_v2)
      int chunkSize = 200; // Can be larger now since no icons (200 * ~100B = 20KB)
      List<List<Map<String, String>>> chunks = [];
      for (var i = 0; i < metadataList.length; i += chunkSize) {
        chunks.add(metadataList.sublist(i, i + chunkSize > metadataList.length ? metadataList.length : i + chunkSize)); 
      }

      final batch = _firestore.batch();
      final collectionRef = _firestore.collection('users').doc(userId).collection('data_v2');

      for (var i = 0; i < chunks.length; i++) {
        final docRef = collectionRef.doc('shard_$i');
        batch.set(docRef, {
          'installedApps': chunks[i],
          'lastUpdated': FieldValue.serverTimestamp(),
          'shardIndex': i,
          'totalShards': chunks.length,
        });
      }
      
      // Cleanup extra shards
      for (var i = chunks.length; i < 20; i++) {
        batch.delete(collectionRef.doc('shard_$i'));
      }

      await batch.commit();
      debugPrint("F_MATE: Synced ${chunks.length} metadata shards.");


      // 4. Upload Icons to `app_icons` collection
      // We process only icons that aren't already there? 
      // For now, simpler to just overwrite or set.
      // Batch limit is 500.
      
      final iconCollection = _firestore.collection('users').doc(userId).collection('app_icons');
      
      List<String> packages = iconMap.keys.toList();
      int iconBatchSize = 400; // Safety margin under 500
      
      for (var i = 0; i < packages.length; i += iconBatchSize) {
        final end = (i + iconBatchSize < packages.length) ? i + iconBatchSize : packages.length;
        final sublist = packages.sublist(i, end);
        
        final iconBatch = _firestore.batch();
        for (var pkg in sublist) {
          iconBatch.set(iconCollection.doc(pkg), {
            'icon': iconMap[pkg],
            'lastUpdated': FieldValue.serverTimestamp(),
          });
        }
        await iconBatch.commit();
        debugPrint("F_MATE: Uploaded batch of ${sublist.length} icons.");
      }

      await prefs.setInt('last_synced_apps_hash_$userId', packageHash);
      debugPrint("F_MATE: App sync complete. Saved hash $packageHash.");

    } catch (e) {
      debugPrint("Error syncing installed apps: $e");
    }
  }
}

