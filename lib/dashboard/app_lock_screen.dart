import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:installed_apps/app_info.dart';
import 'package:android_intent_plus/android_intent.dart';
import '../core/usage_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'dart:typed_data';

class AppLockScreen extends StatefulWidget {
  final String userId;

  const AppLockScreen({super.key, required this.userId});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  final UsageService _usageService = UsageService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const platform = MethodChannel('com.example.focus_mate/blocker');

  List<AppInfo> installedApps = [];
  List<String> lockedPackages = [];
  DateTime? lockEndTime;
  bool loading = true;
  bool _isCompanionControlled = false;
  String? _companionName;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      // Check if user is in companion session
      final companionSession = await _firestore
          .collection('companion_sessions')
          .where('userId', isEqualTo: widget.userId)
          .where('status', isEqualTo: 'ACTIVE')
          .limit(1)
          .get();

      if (companionSession.docs.isNotEmpty) {
        // User is in companion mode
        final sessionData = companionSession.docs.first.data();
        setState(() {
          _isCompanionControlled = true;
          _companionName = sessionData['companionName'];
          loading = false;
        });
        return;
      }

      // Normal mode - load user's own app locks
      final apps = await _usageService.getInstalledAppsList();
      final doc = await _firestore
          .collection('users')
          .doc(widget.userId)
          .get();

      if (mounted) {
        setState(() {
          // Filter out our own app to prevent accidental self-locking
          installedApps = apps.where((app) => app.packageName != 'com.example.focus_mate').toList();
          installedApps.sort((a, b) => (a.name ?? "").compareTo(b.name ?? ""));

          if (doc.exists) {
            final data = doc.data()!;
            lockedPackages = List<String>.from(data['lockedApps'] ?? []);

            if (data['lockEndTime'] != null) {
              lockEndTime = (data['lockEndTime'] as Timestamp).toDate();
            }
          }

          loading = false;
        });
      }
    } catch (e) {
      print("Error loading app lock data: $e");
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> _syncToNative() async {
    try {
      final isActive = lockEndTime != null && DateTime.now().isBefore(lockEndTime!);
      final appsToSend = isActive ? lockedPackages : <String>[];
      await platform.invokeMethod('setBlockedApps', {'apps': appsToSend});
    } catch (e) {
      print("Error syncing to native: $e");
    }
  }

  Future<void> _terminateLock() async {
    setState(() => lockEndTime = null);
    
    // Sync immediately to unlock apps
    await _syncToNative();

    await _firestore  // FIXED: Changed from _firestore.instance to just _firestore
        .collection('users')
        .doc(widget.userId)
        .update({'lockEndTime': null});
  }

  Future<void> _toggleLock(String packageName, bool isLocked) async {
    setState(() {
      isLocked
          ? lockedPackages.add(packageName)
          : lockedPackages.remove(packageName);
    });

    // Sync immediately if lock is active
    if (lockEndTime != null && DateTime.now().isBefore(lockEndTime!)) {
      await _syncToNative();
    }

    await _firestore  // FIXED: Changed from _firestore.instance to just _firestore
        .collection('users')
        .doc(widget.userId)
        .update({'lockedApps': lockedPackages});
  }

  void _openAccessibilitySettings() {
    const AndroidIntent intent = AndroidIntent(
      action: 'android.settings.ACCESSIBILITY_SETTINGS',
    );
    intent.launch();
  }

  void _showDurationPicker() {
    if (lockedPackages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Select apps to lock first!")),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardOverlay,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          height: 280,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Select Lock Duration",
                style: AppTheme.headerTitle,
              ),
              const SizedBox(height: 20),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _timeOption(15, "15m"),
                  _timeOption(30, "30m"),
                  _timeOption(60, "1h"),
                ],
              ),

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: _timeOption(120, "2 Hours (Deep Work)"),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _timeOption(int minutes, String label) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blueAccent.withOpacity(0.2),
        foregroundColor: Colors.blueAccent,
        side: const BorderSide(color: Colors.blueAccent),
      ),
      onPressed: () {
        Navigator.pop(context);
        _activateLock(minutes);
      },
      child: Text(label),
    );
  }

  Future<void> _activateLock(int minutes) async {
    DateTime targetTime = DateTime.now().add(Duration(minutes: minutes));

    setState(() => lockEndTime = targetTime);
    
    // Sync immediately to start blocking
    await _syncToNative();

    await _firestore  // FIXED: Changed from _firestore.instance to just _firestore
        .collection('users')
        .doc(widget.userId)
        .update({'lockEndTime': Timestamp.fromDate(targetTime)});
  }

  // Build companion controlled UI
  Widget _buildCompanionControlledUI() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.group,
              size: 80,
              color: Colors.blueAccent.withOpacity(0.7),
            ),
            const SizedBox(height: 20),
            const Text(
              "App Lock Controlled by Companion",
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              _companionName != null
                  ? "Your companion '${_companionName!}' is managing your app locks"  // FIXED: Added ! to unwrap
                  : "Your companion is managing your app locks",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 16),
            ),
            const SizedBox(height: 30),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.cardOverlay,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  const Text(
                    "During companion session:",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildFeatureItem("❌ You cannot lock/unlock apps"),
                  _buildFeatureItem("👤 Companion selects which apps to lock"),
                  _buildFeatureItem("⏰ Companion controls the session duration"),
                  _buildFeatureItem("🔓 Companion can manually unlock apps"),
                  _buildFeatureItem("🚨 You can request emergency unlock"),
                ],
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context); // Go back to dashboard
              },
              icon: const Icon(Icons.arrow_back),
              label: const Text("Back to Dashboard"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // If companion controlled, show different UI
    if (_isCompanionControlled) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text("App Lock - Companion Mode"),
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          titleTextStyle: AppTheme.headerTitle,
        ),
        body: _buildCompanionControlledUI(),
      );
    }

    bool isLockActive =
        lockEndTime != null && DateTime.now().isBefore(lockEndTime!);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Block Distractions"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: AppTheme.headerTitle,
      ),

      body: Column(
        children: [
          // Accessibility reminder
          Container(
            width: double.infinity,
            color: Colors.blueAccent.withOpacity(0.2),
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.blueAccent),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    "Enable Accessibility for instant blocking.",
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: _openAccessibilitySettings,
                  child: const Text("OPEN"),
                ),
              ],
            ),
          ),

          // Lock timer display
          if (isLockActive && lockEndTime != null)
            LockTimerWidget(
              endTime: lockEndTime!,
              onTimerFinished: _terminateLock,
            ),

          // Apps list
          Expanded(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.cyanAccent),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: installedApps.length,
                    itemBuilder: (context, index) {
                      final app = installedApps[index];
                      final isSelected = lockedPackages.contains(
                        app.packageName,
                      );

                      Uint8List? iconData = app.icon != null
                          ? Uint8List.fromList(app.icon!)
                          : null;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: AppColors.cardOverlay,
                          borderRadius: BorderRadius.circular(12),
                          border: isSelected
                              ? Border.all(
                                  color: Colors.redAccent.withOpacity(0.6),
                                  width: 1.4,
                                )
                              : null,
                        ),

                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.black45,
                            radius: 22,
                            child: iconData != null
                                ? ClipOval(
                                    child: Image.memory(
                                      iconData,
                                      width: 40,
                                      height: 40,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : const Icon(Icons.apps, color: Colors.white70),
                          ),

                          title: Text(
                            app.name ?? "Unknown",
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.redAccent
                                  : Colors.white,
                              fontWeight: FontWeight.w500,
                              fontSize: 15,
                            ),
                          ),

                          trailing: Switch(
                            value: isSelected,
                            activeThumbColor: Colors.redAccent,
                            inactiveThumbColor: Colors.grey,
                            onChanged: (val) =>
                                _toggleLock(app.packageName, val),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),

      floatingActionButton: isLockActive
          ? FloatingActionButton.extended(
              backgroundColor: Colors.red,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text("STOP LOCK"),
              onPressed: _terminateLock,
            )
          : FloatingActionButton.extended(
              backgroundColor: Colors.blueAccent,
              icon: const Icon(Icons.timer),
              label: const Text("Set Lock Timer"),
              onPressed: _showDurationPicker,
            ),
    );
  }
}

class LockTimerWidget extends StatefulWidget {
  final DateTime endTime;
  final VoidCallback onTimerFinished;

  const LockTimerWidget({
    super.key,
    required this.endTime,
    required this.onTimerFinished,
  });

  @override
  State<LockTimerWidget> createState() => _LockTimerWidgetState();
}

class _LockTimerWidgetState extends State<LockTimerWidget> {
  late Timer _timer;
  String _timeLeft = "";

  @override
  void initState() {
    super.initState();
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _updateTime() {
    final now = DateTime.now();
    if (now.isAfter(widget.endTime)) {
      widget.onTimerFinished();
      _timer.cancel();
      return;
    }

    final diff = widget.endTime.difference(now);
    if (mounted) {
      setState(() {
        _timeLeft =
            "${diff.inHours.toString().padLeft(2, '0')}:${(diff.inMinutes % 60).toString().padLeft(2, '0')}:${(diff.inSeconds % 60).toString().padLeft(2, '0')}";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.green.withOpacity(0.2),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          const Text(
            "🔒 LOCK ACTIVE UNTIL:",
            style: TextStyle(
              color: Colors.greenAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            _timeLeft,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}