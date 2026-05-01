import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_apps/device_apps.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:focus_mate/core/usage_service.dart';
import 'package:focus_mate/theme/app_colors.dart';
import 'package:focus_mate/theme/app_theme.dart';
import 'package:flutter/cupertino.dart';

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

  List<Application> installedApps = [];
  List<String> lockedPackages = [];
  DateTime? lockEndTime;
  bool loading = true;
  bool _isCompanionControlled = false;
  String? _companionName;
  int _selectedDuration = 60; // Default 1 hour

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
      final doc = await _firestore.collection('users').doc(widget.userId).get();

      if (mounted) {
        setState(() {
          // Filter out our own app to prevent accidental self-locking
          installedApps = apps
              .where((app) => app.packageName != 'com.example.focus_mate')
              .toList();
          installedApps.sort(
            (a, b) =>
                a.appName.toLowerCase().compareTo(b.appName.toLowerCase()),
          );

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
      debugPrint("Error loading app lock data: $e");
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> _syncToNative() async {
    try {
      final isActive =
          lockEndTime != null && DateTime.now().isBefore(lockEndTime!);
      final appsToSend = isActive ? lockedPackages : <String>[];
      await platform.invokeMethod('setBlockedApps', {'apps': appsToSend});
    } catch (e) {
      debugPrint("Error syncing to native: $e");
    }
  }

  Future<void> _terminateLock() async {
    setState(() => lockEndTime = null);

    // Sync immediately to unlock apps
    await _syncToNative();

    await _firestore.collection('users').doc(widget.userId).update({
      'lockEndTime': null,
    });
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

    await _firestore.collection('users').doc(widget.userId).update({
      'lockedApps': lockedPackages,
    });
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

    // Default to 1 hour if not set or zero
    if (_selectedDuration == 0) _selectedDuration = 60;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent, // Transparent to show glass effect
      builder: (ctx) {
        // Theme Detection inside modal builder
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Container(
          height: 350,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 20,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: Column(
            children: [
              // Handle Bar
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              const SizedBox(height: 10),
              Text(
                "Select Lock Duration",
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),

              // Timer Picker
              Expanded(
                child: CupertinoTheme(
                  data: CupertinoThemeData(
                    brightness: isDark ? Brightness.dark : Brightness.light,
                    textTheme: CupertinoTextThemeData(
                      pickerTextStyle: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                        fontSize: 24,
                      ),
                    ),
                  ),
                  child: CupertinoTimerPicker(
                    mode: CupertinoTimerPickerMode.hm,
                    initialTimerDuration: Duration(minutes: _selectedDuration),
                    onTimerDurationChanged: (Duration newDuration) {
                      setState(() {
                        _selectedDuration = newDuration.inMinutes;
                      });
                    },
                  ),
                ),
              ),

              // confirm button
              Padding(
                padding: const EdgeInsets.all(24),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () {
                      if (_selectedDuration == 0) return;
                      Navigator.pop(context);
                      _activateLock(_selectedDuration);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyanAccent,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      "Start Blocking",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _activateLock(int minutes) async {
    DateTime targetTime = DateTime.now().add(Duration(minutes: minutes));

    setState(() => lockEndTime = targetTime);

    // Sync immediately to start blocking
    await _syncToNative();

    await _firestore.collection('users').doc(widget.userId).update({
      'lockEndTime': Timestamp.fromDate(targetTime),
    });
  }

  // Build companion controlled UI
  Widget _buildCompanionControlledUI(bool isDark) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.supervised_user_circle_outlined,
              size: 80,
              color: isDark ? Colors.blueAccent : Colors.blue,
            ),
            const SizedBox(height: 24),
            Text(
              "Companion Active",
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              _companionName != null
                  ? "'${_companionName!}' is managing your apps"
                  : "Your companion is managing your apps",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black54,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 30),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.white70,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? Colors.white10 : Colors.black12,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "SESSION RULES",
                    style: TextStyle(
                      color: isDark ? Colors.cyanAccent : Colors.blueAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildFeatureItem("⛔ You cannot edit locks", isDark),
                  _buildFeatureItem(
                    "👤 Companion controls app blocking",
                    isDark,
                  ),
                  _buildFeatureItem("⏰ Companion sets the duration", isDark),
                  _buildFeatureItem("🔓 Emergency unlock available", isDark),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureItem(String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 16,
            color: isDark ? Colors.white54 : Colors.black54,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black87,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 1. Theme Detection
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // If companion controlled, show different UI (Refactored below)
    if (_isCompanionControlled) {
      return _buildCompanionControlledPage(isDark);
    }

    bool isLockActive =
        lockEndTime != null && DateTime.now().isBefore(lockEndTime!);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text(
          "Block Distractions",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_accessibility),
            tooltip: "Accessibility Settings",
            onPressed: _openAccessibilitySettings,
          ),
        ],
      ),

      body: Stack(
        children: [
          // Gradient Background
          Container(
            height: double.infinity,
            width: double.infinity,
            decoration: AppTheme.screenBackground(
              context,
              AppColors.roleGradients['user']!,
            ),
          ),

          // Content
          Column(
            children: [
              // Safe Area for the top part
              SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    // Lock timer display (Floating Glass Card)
                    if (isLockActive && lockEndTime != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        child: LockTimerWidget(
                          endTime: lockEndTime!,
                          onTimerFinished: _terminateLock,
                          isDark: isDark,
                        ),
                      ),
                  ],
                ),
              ),

              // Apps list
              Expanded(
                child: loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Colors.cyanAccent,
                        ),
                      )
                    : GridView.builder(
                        padding: EdgeInsets.only(
                          left: 20,
                          right: 20,
                          top: 10,
                          bottom:
                              MediaQuery.of(context).padding.bottom +
                              80, // avoid FAB overlap
                        ),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3, // larger icons
                              childAspectRatio: 0.8,
                              crossAxisSpacing: 15,
                              mainAxisSpacing: 15,
                            ),
                        itemCount: installedApps.length,
                        itemBuilder: (context, index) {
                          final app = installedApps[index];
                          final isSelected = lockedPackages.contains(
                            app.packageName,
                          );

                          // Check if app has icon
                          Uint8List? iconData;
                          if (app is ApplicationWithIcon) {
                            iconData = app.icon;
                          } else {
                            debugPrint(
                              "App ${app.packageName} is not ApplicationWithIcon, it is ${app.runtimeType}",
                            );
                          }

                          return GestureDetector(
                            onTap: () =>
                                _toggleLock(app.packageName, !isSelected),
                            child: Container(
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.redAccent.withValues(alpha: 0.2)
                                    : (isDark
                                          ? Colors.white.withValues(alpha: 0.05)
                                          : Colors.white70),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? Colors.redAccent
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      color: Colors.black.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                    child:
                                        iconData != null && iconData.isNotEmpty
                                        ? _buildIconImage(iconData)
                                        : FutureBuilder<Application?>(
                                            future: DeviceApps.getApp(
                                              app.packageName,
                                              true,
                                            ),
                                            builder: (context, snapshot) {
                                              if (snapshot.connectionState ==
                                                      ConnectionState.done &&
                                                  snapshot.data
                                                      is ApplicationWithIcon) {
                                                final lazyIcon =
                                                    (snapshot.data
                                                            as ApplicationWithIcon)
                                                        .icon;
                                                if (lazyIcon.isNotEmpty) {
                                                  return _buildIconImage(
                                                    lazyIcon,
                                                  );
                                                }
                                              }
                                              return Icon(
                                                Icons.apps,
                                                color: isDark
                                                    ? Colors.white54
                                                    : Colors.black54,
                                                size: 28,
                                              );
                                            },
                                          ),
                                  ),

                                  Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Text(
                                      app.appName,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black87,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),

                                  if (isSelected)
                                    const Icon(
                                      Icons.lock,
                                      color: Colors.redAccent,
                                      size: 12,
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ],
      ),

      floatingActionButton: isLockActive
          ? FloatingActionButton.extended(
              backgroundColor: Colors.redAccent,
              elevation: 4,
              icon: const Icon(Icons.stop_circle_outlined, color: Colors.white),
              label: const Text(
                "STOP LOCK",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              onPressed: _terminateLock,
            )
          : FloatingActionButton.extended(
              backgroundColor: Colors.cyanAccent,
              elevation: 4,
              icon: const Icon(Icons.timer, color: Colors.black),
              label: const Text(
                "Set Timer",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              onPressed: _showDurationPicker,
            ),
    );
  }

  Widget _buildCompanionControlledPage(bool isDark) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text(
          "Companion Mode",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          Container(
            height: double.infinity,
            width: double.infinity,
            decoration: AppTheme.screenBackground(
              context,
              AppColors.roleGradients['companion']!,
            ),
          ),
          _buildCompanionControlledUI(isDark),
        ],
      ),
    );
  }

  Widget _buildIconImage(Uint8List iconData) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: Image.memory(
          iconData,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) =>
              Icon(Icons.apps, color: Colors.white54, size: 28),
        ),
      ),
    );
  }
}

class LockTimerWidget extends StatefulWidget {
  final DateTime endTime;
  final VoidCallback onTimerFinished;
  final bool isDark;

  const LockTimerWidget({
    super.key,
    required this.endTime,
    required this.onTimerFinished,
    this.isDark = true,
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
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: widget.isDark
              ? [
                  Colors.blueAccent.withValues(alpha: 0.2),
                  Colors.purpleAccent.withValues(alpha: 0.2),
                ]
              : [
                  Colors.blue.withValues(alpha: 0.1),
                  Colors.purple.withValues(alpha: 0.1),
                ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      child: Column(
        children: [
          const Text(
            "LOCK ACTIVE",
            style: TextStyle(
              color: Colors.blueAccent,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _timeLeft,
            style: TextStyle(
              color: widget.isDark ? Colors.white : Colors.black87,
              fontSize: 32,
              fontWeight: FontWeight.bold,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
