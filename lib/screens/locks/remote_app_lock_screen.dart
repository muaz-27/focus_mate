import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:focus_mate/theme/app_colors.dart';
import 'package:focus_mate/theme/app_theme.dart';
import '../../core/widgets/app_icon_widget.dart';

class RemoteAppLockScreen extends StatefulWidget {
  final String studentId;
  final String studentName;

  const RemoteAppLockScreen({
    super.key,
    required this.studentId,
    required this.studentName,
  });

  @override
  State<RemoteAppLockScreen> createState() => _RemoteAppLockScreenState();
}

class _RemoteAppLockScreenState extends State<RemoteAppLockScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Installed apps data (fetched once, then updated via stream)
  List<Map<String, dynamic>> installedApps = [];
  Map<String, String> _iconMap = {};

  // Lock state (drives the UI)
  List<String> lockedPackages = [];
  DateTime? lockEndTime;

  // UI state
  bool _appsLoading = true;
  bool _isRefreshingFromDevice = false;
  int _selectedDuration = 60;

  // Subscriptions
  StreamSubscription<QuerySnapshot>? _shardsSubscription;
  StreamSubscription<DocumentSnapshot>? _lockStateSubscription;

  @override
  void initState() {
    super.initState();
    _requestDeviceRefresh();
    _listenToShards();
    _listenToLockState();
    _loadIcons();
  }

  @override
  void dispose() {
    _shardsSubscription?.cancel();
    _lockStateSubscription?.cancel();
    super.dispose();
  }

  /// Signals the child's device to push a fresh installed-apps list to Firestore.
  ///
  /// The student dashboard detects [appsRefreshRequest] == true and calls
  /// [syncInstalledAppsToFirebase] with forceSync:true, then resets the flag.
  Future<void> _requestDeviceRefresh() async {
    try {
      await _firestore.collection('users').doc(widget.studentId).update({
        'appsRefreshRequest': true,
      });
      debugPrint('F_MATE: Parent requested app list refresh from child device.');
      if (mounted) {
        setState(() => _isRefreshingFromDevice = true);
      }
      // Auto-clear the "refreshing" indicator after 10 seconds regardless
      Future.delayed(const Duration(seconds: 10), () {
        if (mounted) setState(() => _isRefreshingFromDevice = false);
      });
    } catch (e) {
      debugPrint('F_MATE: Could not set appsRefreshRequest: $e');
    }
  }

  /// Listens to the data_v2 shard collection in real-time.
  ///
  /// When the child's device finishes syncing (after a force-refresh), Firestore
  /// emits an update here and the app list in the UI is automatically refreshed.
  void _listenToShards() {
    _shardsSubscription = _firestore
        .collection('users')
        .doc(widget.studentId)
        .collection('data_v2')
        .snapshots()
        .listen((snapshot) async {
      if (!mounted) return;

      List<Map<String, dynamic>> allApps = [];

      if (snapshot.docs.isNotEmpty) {
        for (var doc in snapshot.docs) {
          if (doc.data().containsKey('installedApps')) {
            final shardApps = List<Map<String, dynamic>>.from(
              doc.data()['installedApps'],
            );
            allApps.addAll(shardApps);
          }
        }
      }

      if (allApps.isEmpty) {
        // Fallback: legacy data/installed_apps
        try {
          final legacyDoc = await _firestore
              .collection('users')
              .doc(widget.studentId)
              .collection('data')
              .doc('installed_apps')
              .get();

          if (legacyDoc.exists && legacyDoc.data() != null) {
            final data = legacyDoc.data() as Map<String, dynamic>;
            if (data.containsKey('installedApps')) {
              allApps = List<Map<String, dynamic>>.from(data['installedApps']);
            }
          }
        } catch (_) {}
      }

      allApps.sort(
        (a, b) => (a['appName'] as String).toLowerCase().compareTo(
          (b['appName'] as String).toLowerCase(),
        ),
      );

      if (mounted) {
        setState(() {
          installedApps = allApps
              .where((app) => app['packageName'] != 'com.example.focus_mate')
              .map((app) {
                final newApp = Map<String, dynamic>.from(app);
                final pkg = newApp['packageName'] as String;
                final iconBase64 = _iconMap[pkg] ?? newApp['iconBytes'];
                if (iconBase64 != null && iconBase64 is String) {
                  try {
                    newApp['decodedIcon'] = base64Decode(iconBase64);
                  } catch (e) {
                    debugPrint('F_MATE: Error decoding icon for $pkg');
                  }
                }
                return newApp;
              })
              .toList();
          _appsLoading = false;
          _isRefreshingFromDevice = false; // Fresh data arrived
        });
      }
    });
  }

  /// Pre-fetches the icon map once and re-applies when apps update.
  Future<void> _loadIcons() async {
    try {
      final iconsSnapshot = await _firestore
          .collection('users')
          .doc(widget.studentId)
          .collection('app_icons')
          .get();

      final Map<String, String> iconMap = {};
      for (var doc in iconsSnapshot.docs) {
        if (doc.data().containsKey('icon')) {
          iconMap[doc.id] = doc.data()['icon'] as String;
        }
      }

      if (mounted) {
        setState(() => _iconMap = iconMap);
      }
    } catch (e) {
      debugPrint('F_MATE: Error loading icons: $e');
    }
  }

  /// Listens for lock state changes on the student's user document in real-time.
  void _listenToLockState() {
    _lockStateSubscription = _firestore
        .collection('users')
        .doc(widget.studentId)
        .snapshots()
        .listen((doc) {
      if (!mounted || !doc.exists) return;
      final data = doc.data()!;
      setState(() {
        lockedPackages = List<String>.from(data['lockedApps'] ?? []);
        lockEndTime = data['lockEndTime'] != null
            ? (data['lockEndTime'] as Timestamp).toDate()
            : null;
      });
    });
  }

  Future<void> _toggleLock(String packageName, bool isLocked) async {
    setState(() {
      isLocked
          ? lockedPackages.add(packageName)
          : lockedPackages.remove(packageName);
    });

    await _firestore.collection('users').doc(widget.studentId).update({
      'lockedApps': lockedPackages,
    });
  }

  Future<void> _activateLock(int minutes) async {
    final targetTime = DateTime.now().add(Duration(minutes: minutes));
    setState(() => lockEndTime = targetTime);

    await _firestore.collection('users').doc(widget.studentId).update({
      'lockEndTime': Timestamp.fromDate(targetTime),
    });
  }

  Future<void> _terminateLock() async {
    setState(() => lockEndTime = null);
    await _firestore.collection('users').doc(widget.studentId).update({
      'lockEndTime': null,
    });
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
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Container(
          height: 350,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 20),
              Text(
                "Select Lock Duration",
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Expanded(
                child: CupertinoTheme(
                  data: CupertinoThemeData(
                    brightness: isDark ? Brightness.dark : Brightness.light,
                  ),
                  child: CupertinoTimerPicker(
                    mode: CupertinoTimerPickerMode.hm,
                    initialTimerDuration: Duration(minutes: _selectedDuration),
                    onTimerDurationChanged: (val) =>
                        _selectedDuration = val.inMinutes,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _activateLock(
                        _selectedDuration == 0 ? 60 : _selectedDuration,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orangeAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      "Apply Lock",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLockActive =
        lockEndTime != null && DateTime.now().isBefore(lockEndTime!);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Lock ${widget.studentName}'s Apps",
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (_isRefreshingFromDevice)
              Text(
                "Refreshing from device...",
                style: TextStyle(
                  color: isDark ? Colors.orangeAccent : Colors.orange.shade700,
                  fontSize: 11,
                ),
              ),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new,
            color: isDark ? Colors.white : Colors.black87,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.refresh,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
            tooltip: "Request fresh app list from device",
            onPressed: () {
              setState(() => _isRefreshingFromDevice = true);
              _requestDeviceRefresh();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    "Requesting latest apps from child device...",
                  ),
                  duration: Duration(seconds: 3),
                ),
              );
            },
          ),
        ],
      ),
      body: Container(
        decoration: AppTheme.screenBackground(
          context,
          AppColors.roleGradients['parent']!,
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Refresh banner
              if (_isRefreshingFromDevice && !_appsLoading)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  color: Colors.orange.withValues(alpha: 0.15),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.orangeAccent,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        "Waiting for child's device to sync…",
                        style: TextStyle(
                          color: isDark
                              ? Colors.orangeAccent
                              : Colors.orange.shade800,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),

              // Active lock banner
              if (isLockActive)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.redAccent.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.lock_clock, color: Colors.redAccent),
                      const SizedBox(width: 12),
                      Text(
                        "Locks Active until ${_formatTime(lockEndTime!)}",
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

              Expanded(
                child: _appsLoading
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(
                              color: Colors.orangeAccent,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              "Loading apps from child's device…",
                              style: TextStyle(
                                color: isDark
                                    ? Colors.white54
                                    : Colors.black45,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      )
                    : installedApps.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.phone_android_outlined,
                              size: 60,
                              color: isDark ? Colors.white30 : Colors.black26,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              "No apps found on child's device.",
                              style: TextStyle(
                                color: isDark ? Colors.white54 : Colors.black45,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "Make sure the child's app is open so it can sync.",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: isDark ? Colors.white38 : Colors.black38,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              childAspectRatio: 0.72,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                            ),
                        itemCount: installedApps.length,
                        itemBuilder: (context, index) {
                          final app = installedApps[index];
                          final pkg = app['packageName'] as String;
                          final name = app['appName'] as String;
                          final isSelected = lockedPackages.contains(pkg);

                          return GestureDetector(
                            onTap: () => _toggleLock(pkg, !isSelected),
                            child: Container(
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.orangeAccent.withValues(alpha: 0.2)
                                    : (isDark
                                          ? Colors.white.withValues(alpha: 0.05)
                                          : Colors.white70),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? Colors.orangeAccent
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 8,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      color: Colors.black.withValues(alpha: 0.1),
                                    ),
                                    child: AppIconWidget(
                                      packageName: app['packageName'],
                                      appName: app['appName'],
                                      iconBytes: app['decodedIcon'],
                                      size: 38,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    name,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w500,
                                      height: 1.2,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (isSelected)
                                    const Padding(
                                      padding: EdgeInsets.only(top: 2),
                                      child: Icon(
                                        Icons.check_circle,
                                        color: Colors.orangeAccent,
                                        size: 11,
                                      ),
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
        ),
      ),
      floatingActionButton: isLockActive
          ? FloatingActionButton.extended(
              backgroundColor: Colors.redAccent,
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
              backgroundColor: Colors.orangeAccent,
              icon: const Icon(Icons.timer, color: Colors.white),
              label: const Text(
                "Set Timer",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              onPressed: _showDurationPicker,
            ),
    );
  }

  String _formatTime(DateTime time) {
    return "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}";
  }
}
