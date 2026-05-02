import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:focus_mate/core/auth_gate.dart';
import 'package:focus_mate/core/screen_capture_service.dart';
import 'package:focus_mate/core/permission_manager.dart';
import 'package:focus_mate/core/usage_service.dart';
import 'package:focus_mate/theme/app_colors.dart';
import 'package:focus_mate/theme/app_theme.dart';
import 'package:focus_mate/core/notification_service.dart';
import 'package:focus_mate/screens/analytics/analytics_screen.dart';
import 'package:focus_mate/screens/locks/app_lock_screen.dart';
import 'package:focus_mate/screens/companion/companion_request_page.dart';
import 'package:focus_mate/screens/companion/companion_controlled_page.dart';
import 'package:focus_mate/core/widgets/custom_dialog.dart';
import 'package:focus_mate/core/native_blocker.dart';
import 'package:focus_mate/core/schedule_service.dart';
import 'package:focus_mate/screens/student/widgets/dashboard_action_grid.dart';
import 'package:focus_mate/screens/student/widgets/dashboard_header.dart';
import 'package:focus_mate/screens/student/widgets/session_banner.dart';

/// Entry point for the student dashboard.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:focus_mate/providers/schedule_provider.dart';

/// Entry point that redirects back to the auth gate.
///
/// Used when returning from companion session or other deep navigation.
/// Since [AuthGate] now uses Riverpod providers for reactive routing,
/// this simply navigates back to the root route.
class StudentDashboardLoader extends StatelessWidget {
  const StudentDashboardLoader({super.key});

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (route) => false,
      );
    });

    return const Scaffold(
      backgroundColor: Color(0xFF121212),
      body: Center(child: CircularProgressIndicator(color: Colors.cyanAccent)),
    );
  }
}

/// Main dashboard widget for students.
///
/// Displays daily study statistics, goal progress, and allows access to
/// session features and settings.
class StudentDashboard extends ConsumerStatefulWidget {
  final Map<String, dynamic> userData;
  final int studyTime;
  final int? dailyGoal;
  final bool activeSession;
  final bool companionActive;
  final bool appsUnlocked;
  final Function onLogout;
  final Function(String) onStartSession;

  const StudentDashboard({
    super.key,
    required this.userData,
    required this.studyTime,
    this.dailyGoal,
    required this.activeSession,
    required this.companionActive,
    required this.appsUnlocked,
    required this.onLogout,
    required this.onStartSession,
  });

  @override
  ConsumerState<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends ConsumerState<StudentDashboard>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final UsageService _usageService = UsageService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  // static const platform = MethodChannel('com.example.focus_mate/blocker'); // REMOVED: Using NativeBlocker class

  Timer? _ruleSyncTimer;
  Timer? _usageSyncTimer;
  Timer? _heartbeatTimer;
  Timer? _scheduleWarningTimer;
  DateTime? _lockEndTime;
  List<String> _blockedList = [];
  bool companionActive = false;

  /// Local state for companion name to avoid UI flicker.
  String? _companionName;
  String? _companionId;
  String? _companionRole; // NEW: Track role to enforce restrictions

  /// Local state for optimistic daily goal updates.
  int? _dailyGoal;

  /// Local state for immediate daily usage display.
  int? _localStudyTime;

  bool _isLoading = false;
  bool _isRefreshingUsage = false;
  bool _hasPermission = false;
  final TextEditingController _companionCodeController =
      TextEditingController();

  /// Data for any currently active or requested companion session.
  Map<String, dynamic>? _activeSessionData;
  StreamSubscription? _activeSessionSubscription;
  StreamSubscription<DocumentSnapshot>? _userDocSubscription;
  List<AppSchedule> _schedules = [];

  bool _limitExceededNotified = false;
  String? _lastSessionId;
  String? _lastSessionStatus;

  @override
  void initState() {
    super.initState();
    NotificationService().requestPermissions();
    WidgetsBinding.instance.addObserver(this);

    // Initialize companion state from passed user data
    if (widget.userData['linkedCompanion'] != null) {
      companionActive = true;
      _companionName = widget.userData['companionName'];
      _companionId = widget.userData['linkedCompanion'];
      _companionRole = widget.userData['linkedCompanionRole']; // NEW
    }
    _dailyGoal = widget.dailyGoal;
    _localStudyTime = widget.studyTime;

    // Initialize lock state immediately
    _blockedList = List<String>.from(widget.userData['lockedApps'] ?? []);
    _lockEndTime = widget.userData['lockEndTime'] != null
        ? (widget.userData['lockEndTime'] as Timestamp).toDate()
        : null;

    // Apply locks immediately ONLY if we have lock data.
    // If lockedApps wasn't provided yet (FutureBuilder hasn't loaded),
    // the Firestore real-time listener below will handle it reactively.
    // This prevents a race condition where we clear native locks before
    // knowing the actual lock state from Firestore.
    if (_blockedList.isNotEmpty) {
      _applyNativeLock();
    }

    _refreshUsageStats();
    // _startRuleSync(); // REMOVED: Moving to reactive listener

    // Sync scheduled locks to Native Service initially
    ScheduleService().syncSchedulesToNative(widget.userData['id']);

    // Listen to schedule changes via Riverpod provider
    ref.listenManual(schedulesProvider(widget.userData['id']), (
      previous,
      next,
    ) {
      next.whenData((schedules) {
        if (mounted) {
          setState(() {
            _schedules = schedules;
          });
        }
        ScheduleService().syncSchedulesToNative(widget.userData['id']);
      });
    }, fireImmediately: true);

    _startScheduleWarningChecker();

    _getCompanionDetails();
    _checkActiveSession();

    // Permission flow: sequential for parent-linked children, parallel otherwise
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        if (companionActive && _companionRole == 'parent') {
          // Sequential flow: Accessibility → Battery → Screen Capture (one dialog at a time)
          debugPrint("F_MATE: Running sequential parental permission flow");
          PermissionManager.runParentalPermissionFlow(context);
        } else {
          PermissionManager.checkAccessibility(context);
          PermissionManager.checkBatteryOptimizations(context);
        }
      }
    });

    // Direct listener to handle snapshotRequest in real-time
    // Skip the first event so stale snapshotRequest from a previous session doesn't race with permission flow
    bool _snapshotListenerReady = false;
    _userDocSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userData['id'])
        .snapshots()
        .listen((docSnap) {
          if (!mounted) return;

          if (docSnap.exists) {
            final data = docSnap.data() as Map<String, dynamic>;

            // 1. Reactive Lock Sync (REPLACES POLLING)
            final List<String> newBlockedList = List<String>.from(
              data['lockedApps'] ?? [],
            );
            final DateTime? newLockEndTime = data['lockEndTime'] != null
                ? (data['lockEndTime'] as Timestamp).toDate()
                : null;

            if (newBlockedList.toString() != _blockedList.toString() ||
                newLockEndTime != _lockEndTime) {
              debugPrint("F_MATE: Reactive Sync -> Applying new lock rules");
              setState(() {
                _blockedList = newBlockedList;
                _lockEndTime = newLockEndTime;
              });
              _applyNativeLock();
            }

            // 2. Snapshot Request Listener
            // We only skip the first event if it's 'false' (stale). If it's 'true', handle it!
            final bool isRequest = data['snapshotRequest'] == true;
            if (!_snapshotListenerReady) {
              _snapshotListenerReady = true;
              if (!isRequest)
                return; // Skip first event only if no active request
            }

            debugPrint(
              "F_MATE: Snapshot listener triggered. request=$isRequest",
            );
            if (isRequest) {
              if (_companionRole == 'parent') {
                _handleSnapshotRequest();
              } else if (_companionRole != null) {
                debugPrint(
                  "F_MATE: Snapshot ignored — companion role is '$_companionRole' (not parent)",
                );
                _firestore
                    .collection('users')
                    .doc(widget.userData['id'])
                    .update({'snapshotRequest': false});
              }
            }

            // 3. Apps Refresh Request (triggered by parent opening the lock screen)
            if (data['appsRefreshRequest'] == true) {
              debugPrint("F_MATE: appsRefreshRequest detected — force syncing apps...");
              // Clear the flag first so we don't double-trigger
              _firestore
                  .collection('users')
                  .doc(widget.userData['id'])
                  .update({'appsRefreshRequest': false}).catchError((_) {});
              // Force a fresh sync to Firestore, bypassing the hash cache
              _usageService.syncInstalledAppsToFirebase(
                widget.userData['id'],
                forceSync: true,
              );
            }
          }
        });

    // Sync usage data in background
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _usageService.syncUsageToFirebase(widget.userData['id']);
      _usageService.syncInstalledAppsToFirebase(widget.userData['id']);
    });

    // Sync usage stats every 1 minute to keep UI fresh
    _usageSyncTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _refreshUsageStats();
    });

    // Heartbeat: write lastSeen every 60s so parents know the device is online
    _firestore
        .collection('users')
        .doc(widget.userData['id'])
        .update({
          'lastSeen': FieldValue.serverTimestamp(),
          'deviceOnline': true,
        })
        .catchError((_) {});
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _firestore
          .collection('users')
          .doc(widget.userData['id'])
          .update({
            'lastSeen': FieldValue.serverTimestamp(),
            'deviceOnline': true,
          })
          .catchError((_) {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ruleSyncTimer?.cancel();
    _usageSyncTimer?.cancel();
    _heartbeatTimer?.cancel();
    _scheduleWarningTimer?.cancel();
    _activeSessionSubscription?.cancel();
    _userDocSubscription?.cancel();
    _companionCodeController.dispose();
    // Mark device as offline when dashboard is disposed
    _firestore
        .collection('users')
        .doc(widget.userData['id'])
        .update({'deviceOnline': false})
        .catchError((_) {});
    super.dispose();
  }

  void _startScheduleWarningChecker() {
    _scheduleWarningTimer?.cancel();
    _scheduleWarningTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      final nowMinutes = now.hour * 60 + now.minute;
      final today = now.weekday; // 1=Mon, 7=Sun
      for (var schedule in _schedules) {
        if (schedule.status == 'active' && schedule.days.contains(today)) {
          final startMinutes = schedule.startTime.hour * 60 + schedule.startTime.minute;
          final diff = startMinutes - nowMinutes;
          // Check if exactly 5 minutes away
          if (diff == 5) {
            NotificationService().showInstantNotification(
              id: schedule.id.hashCode,
              title: "Upcoming Session",
              body: "Your scheduled session '${schedule.name}' starts in 5 minutes.",
            );
          }
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      debugPrint("F_MATE: App resumed — checking screen capture service...");

      // Update heartbeat immediately on resume
      _firestore
          .collection('users')
          .doc(widget.userData['id'])
          .update({
            'lastSeen': FieldValue.serverTimestamp(),
            'deviceOnline': true,
          })
          .catchError((_) {});

      // Re-initialize screen capture if linked to parent and service is dead
      if (companionActive && _companionRole == 'parent') {
        _ensureScreenCaptureRunning();
      }

      // Re-apply locks immediately in case native service restarted
      _fetchLockRules().then((_) => _applyNativeLock());

      // Refresh usage stats and active sessions on resume
      _refreshUsageStats();
      _checkActiveSession();
    } else if (state == AppLifecycleState.paused) {
      // Update heartbeat when going to background
      _firestore
          .collection('users')
          .doc(widget.userData['id'])
          .update({'lastSeen': FieldValue.serverTimestamp()})
          .catchError((_) {});
    }
  }

  /// Checks if the SnapshotService is running. If not, silently re-requests
  /// screen capture permission. This ensures the service survives app restarts.
  Future<void> _ensureScreenCaptureRunning() async {
    try {
      final bool running = await ScreenCaptureService.isServiceRunning();
      debugPrint("F_MATE: ScreenCapture service running=$running");
      if (!running) {
        debugPrint(
          "F_MATE: Service dead on resume — re-requesting screen capture...",
        );
        await ScreenCaptureService.requestPermission();
      }
    } catch (e) {
      debugPrint("F_MATE: Error checking/restarting capture service: $e");
    }
  }

  @override
  void didUpdateWidget(StudentDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Check if linkedCompanion changed
    if (widget.userData['linkedCompanion'] !=
        oldWidget.userData['linkedCompanion']) {
      setState(() {
        companionActive = widget.userData['linkedCompanion'] != null;
        if (!companionActive) {
          _companionName = null;
          _companionId = null;
          _companionRole = null;
        } else {
          _companionId = widget.userData['linkedCompanion'];
          _companionRole = widget.userData['linkedCompanionRole'];
          if (widget.userData['companionName'] != null) {
            _companionName = widget.userData['companionName'];
          }
        }
      });
      _getCompanionDetails();

      if (companionActive &&
          _companionRole == 'parent' &&
          oldWidget.userData['linkedCompanion'] == null) {
        ScreenCaptureService.requestPermission();
      } else if ((!companionActive || _companionRole != 'parent') &&
          oldWidget.userData['linkedCompanion'] != null) {
        // Parent unlinked child or changed role — stop the background capture service
        ScreenCaptureService.stopService();
      }
    }

    // Sync daily goal if it changed from upstream
    if (widget.dailyGoal != oldWidget.dailyGoal) {
      setState(() {
        _dailyGoal = widget.dailyGoal;
      });
    }

    if (widget.studyTime != oldWidget.studyTime) {
      // Only update if we aren't currently refreshing manually to avoid jumping
      if (!_isRefreshingUsage) {
        setState(() => _localStudyTime = widget.studyTime);
      }
    }

    // NEW: Sync blocked apps immediately when parent data changes
    final List<String> oldLocked = List<String>.from(
      oldWidget.userData['lockedApps'] ?? [],
    );
    final List<String> newLocked = List<String>.from(
      widget.userData['lockedApps'] ?? [],
    );
    final DateTime? oldEndTime = oldWidget.userData['lockEndTime'] != null
        ? (oldWidget.userData['lockEndTime'] as Timestamp).toDate()
        : null;
    final DateTime? newEndTime = widget.userData['lockEndTime'] != null
        ? (widget.userData['lockEndTime'] as Timestamp).toDate()
        : null;

    if (newLocked.toString() != oldLocked.toString() ||
        newEndTime != oldEndTime) {
      setState(() {
        _blockedList = newLocked;
        _lockEndTime = newEndTime;
      });
      _applyNativeLock();
    }

    // Check for snapshotRequest
    final bool oldSnapshotRequest =
        oldWidget.userData['snapshotRequest'] == true;
    final bool newSnapshotRequest = widget.userData['snapshotRequest'] == true;

    debugPrint(
      "F_MATE: didUpdateWidget -> oldSnapshotReq: $oldSnapshotRequest, newSnapshotReq: $newSnapshotRequest",
    );

    if (!oldSnapshotRequest && newSnapshotRequest) {
      if (_companionRole == 'parent') {
        _handleSnapshotRequest();
      } else {
        _firestore.collection('users').doc(widget.userData['id']).update({
          'snapshotRequest': false,
        });
      }
    }
  }

  /// Clears any stale snapshotRequest from a previous session, then requests
  /// screen capture permission. Called once at startup when companion is active.
  Future<void> _initScreenCapture() async {
    final String childId = widget.userData['id'];
    // Clear any leftover request from a previous session so the listener doesn't
    // fire immediately and race with the permission dialog.
    try {
      await FirebaseFirestore.instance.collection('users').doc(childId).update({
        'snapshotRequest': false,
      });
    } catch (_) {}
    // Now request permission — the dialog appears in the foreground
    await ScreenCaptureService.requestPermission();
  }

  bool _isProcessingSnapshot = false;

  Future<void> _handleSnapshotRequest() async {
    if (_isProcessingSnapshot) return;
    _isProcessingSnapshot = true;

    debugPrint("F_MATE: _handleSnapshotRequest started...");
    final String childId = widget.userData['id'];

    Uint8List? bytes;
    try {
      // Check if the native SnapshotService is running
      bool serviceRunning = await ScreenCaptureService.isServiceRunning();
      debugPrint("F_MATE: SnapshotService isRunning=$serviceRunning");

      // If service is not running, attempt to restart it
      if (!serviceRunning) {
        debugPrint(
          "F_MATE: Service not running, attempting to re-request permission...",
        );
        await ScreenCaptureService.requestPermission();
        // Wait for service to initialize
        await Future.delayed(const Duration(seconds: 2));
        serviceRunning = await ScreenCaptureService.isServiceRunning();
        debugPrint("F_MATE: After recovery attempt, isRunning=$serviceRunning");
      }

      if (!serviceRunning) {
        debugPrint(
          "F_MATE: Service still not running after recovery. Reporting error.",
        );
        await _firestore.collection('users').doc(childId).update({
          'snapshotRequest': false,
          'snapshotError':
              'Screen monitoring service is not active. Ask child to open the app and grant screen capture permission.',
        });
        _isProcessingSnapshot = false;
        return;
      }

      // Retry loop: waits up to ~12 seconds for the capture to succeed
      // Each attempt needs ~500ms native delay + up to 5s for frame delivery
      for (int attempt = 0; attempt < 4; attempt++) {
        bytes = await ScreenCaptureService.captureScreen();
        if (bytes != null) break;
        debugPrint(
          "F_MATE: capture attempt $attempt failed, retrying in 3s...",
        );
        await Future.delayed(const Duration(seconds: 3));
      }

      if (bytes != null) {
        debugPrint(
          "F_MATE: Captured ${bytes.length} bytes. Attempting Storage upload...",
        );

        String? downloadUrl;

        // Try Firebase Storage first
        try {
          final String fileName =
              "${DateTime.now().millisecondsSinceEpoch}.jpg";
          final storageRef = FirebaseStorage.instance.ref().child(
            'snapshots/$childId/$fileName',
          );
          final uploadTask = storageRef.putData(
            bytes,
            SettableMetadata(contentType: 'image/jpeg'),
          );
          final taskSnapshot = await uploadTask;

          if (taskSnapshot.state == TaskState.success) {
            downloadUrl = await taskSnapshot.ref.getDownloadURL();
            debugPrint("F_MATE: Storage upload SUCCESS. URL: $downloadUrl");
          }
        } catch (storageError) {
          debugPrint("F_MATE: Storage upload failed: $storageError");
          debugPrint("F_MATE: Falling back to Firestore base64 storage...");
        }

        if (downloadUrl != null) {
          // Save with Storage URL
          await _firestore
              .collection('users')
              .doc(childId)
              .collection('snapshots')
              .add({
                'timestamp': FieldValue.serverTimestamp(),
                'imageUrl': downloadUrl,
                'capturedBy': 'parent',
              });
          debugPrint("F_MATE: Snapshot saved with Storage URL.");
        } else {
          // Fallback: store as base64 directly in Firestore
          final String base64Image = base64Encode(bytes);
          debugPrint(
            "F_MATE: Saving as base64 (${base64Image.length} chars)...",
          );

          await _firestore
              .collection('users')
              .doc(childId)
              .collection('snapshots')
              .add({
                'timestamp': FieldValue.serverTimestamp(),
                'imageBase64': base64Image,
                'capturedBy': 'parent',
              });
          debugPrint("F_MATE: Snapshot saved as base64 in Firestore.");
        }
      } else {
        debugPrint("F_MATE: All capture attempts failed.");
        await _firestore.collection('users').doc(childId).update({
          'snapshotError':
              'Capture failed after multiple attempts. The child may have denied the permission.',
        });
      }
    } catch (e) {
      debugPrint("F_MATE: Screenshot process failed: $e");
      try {
        await _firestore.collection('users').doc(childId).update({
          'snapshotError':
              'Capture error: ${e.toString().length > 100 ? e.toString().substring(0, 100) : e.toString()}',
        });
      } catch (_) {}
    } finally {
      await _firestore.collection('users').doc(childId).update({
        'snapshotRequest': false,
      });
      _isProcessingSnapshot = false;
      debugPrint("F_MATE: Snapshot request cycle complete.");
    }
  }

  /// Listens for active or requested companion sessions from Firestore.
  ///
  /// Updates [_activeSessionData] to show the session banner if needed.
  void _checkActiveSession() {
    _activeSessionSubscription = _firestore
        .collection('companion_sessions')
        .where('userId', isEqualTo: widget.userData['id'])
        .where('status', whereIn: ['ACTIVE', 'REQUESTED'])
        .snapshots()
        .listen((snapshot) {
          if (mounted) {
            if (snapshot.docs.isNotEmpty) {
              // Sort in memory (newest first)
              final docs = snapshot.docs;
              docs.sort((a, b) {
                final aTime =
                    (a.data()['requestedAt'] as Timestamp?)?.toDate() ??
                    DateTime(2000);
                final bTime =
                    (b.data()['requestedAt'] as Timestamp?)?.toDate() ??
                    DateTime(2000);
                return bTime.compareTo(aTime);
              });

              // Find the first valid doc (Active, or Recent Request)
              DocumentSnapshot? validDoc;
              final now = DateTime.now();

              for (var doc in docs) {
                final data = doc.data();
                final status = data['status'];
                final requestedAt = (data['requestedAt'] as Timestamp?)
                    ?.toDate();

                if (status == 'ACTIVE') {
                  validDoc = doc;
                  break;
                } else if (status == 'REQUESTED') {
                  // Only show requests from the last 30 minutes
                  if (requestedAt != null &&
                      now.difference(requestedAt).inMinutes < 30) {
                    validDoc = doc;
                    break;
                  }
                }
              }

              if (validDoc != null) {
                final newStatus = (validDoc.data() as Map)['status'];
                final newId = validDoc.id;

                if (_lastSessionId == newId && _lastSessionStatus != newStatus) {
                  if (newStatus == 'ACTIVE') {
                    NotificationService().showInstantNotification(
                      id: validDoc.id.hashCode,
                      title: 'Session Approved',
                      body: 'Your companion approved your study session.',
                    );
                  }
                } else if (_lastSessionId != newId && newStatus == 'ACTIVE') {
                  NotificationService().showInstantNotification(
                    id: validDoc.id.hashCode,
                    title: 'Session Initiated',
                    body: 'A study session was started for your device.',
                  );
                }

                _lastSessionId = newId;
                _lastSessionStatus = newStatus;

                setState(() {
                  _activeSessionData = validDoc!.data() as Map<String, dynamic>;
                  _activeSessionData!['id'] = validDoc!.id;
                });
              } else {
                _lastSessionId = null;
                _lastSessionStatus = null;
                setState(() {
                  _activeSessionData = null;
                });
              }
            } else {
              _lastSessionId = null;
              _lastSessionStatus = null;
              setState(() {
                _activeSessionData = null;
              });
            }
          }
        });
  }

  /// Periodically syncs blocked apps to the native Android service.
  void _startRuleSync() {
    _ruleSyncTimer?.cancel();
    _ruleSyncTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      await _fetchLockRules();
      _applyNativeLock();
    });
  }

  /// Calculates which apps to block and invokes native method.
  ///
  /// IMPORTANT: This method ONLY manages the user's own block channel.
  /// The companion channel is exclusively managed by [CompanionControlledPage].
  /// Touching it here would race with active companion sessions.
  Future<void> _applyNativeLock() async {
    // 1. Check if Accessibility Service is even enabled
    bool isAlive = await NativeBlocker.isAccessibilityEnabled();
    if (!isAlive && mounted) {
      debugPrint(
        "F_MATE: Native Lock attempted but Accessibility Service is OFF.",
      );
      // Optional: Could show a snackbar here, but best to let the main UI handles it
      // to avoid spamming.
    }

    // 2. Determine effective block list
    bool shouldBlock =
        _blockedList.isNotEmpty &&
        (_lockEndTime == null || DateTime.now().isBefore(_lockEndTime!));
    final appsToSend = shouldBlock ? _blockedList : <String>[];

    try {
      await NativeBlocker.setBlockedApps(appsToSend);
      debugPrint(
        "F_MATE: Synced ${appsToSend.length} user-blocked apps to native.",
      );
    } catch (e) {
      debugPrint("F_MATE: Error syncing blocked apps: $e");
    }
  }

  /// Fetches the current list of blocked apps and lock duration from Firestore.
  Future<void> _fetchLockRules() async {
    try {
      final doc = await _firestore
          .collection('users')
          .doc(widget.userData['id'])
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        if (mounted) {
          setState(() {
            _blockedList = List<String>.from(data['lockedApps'] ?? []);
            _lockEndTime = data['lockEndTime'] != null
                ? (data['lockEndTime'] as Timestamp).toDate()
                : null;
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching lock rules: $e");
    }
  }

  /// Fetches details of the linked companion if not already available.
  Future<void> _getCompanionDetails() async {
    if (_companionName != null && _companionRole != null)
      return; // Wait until both are loaded
    String? companionId = widget.userData['linkedCompanion'];
    if (companionId != null) {
      try {
        DocumentSnapshot doc = await _firestore
            .collection('users')
            .doc(companionId)
            .get();
        if (doc.exists) {
          final docData = doc.data() as Map<String, dynamic>;
          if (mounted) {
            String resolvedRole = docData.containsKey('role')
                ? docData['role']
                : 'companion';
            setState(() {
              _companionName = docData['name'];
              _companionRole = resolvedRole;
              companionActive = true;
            });

            // FIX: If the companion is a parent, ensure screen capture service is requested.
            // This handles legacy linked accounts where 'linkedCompanionRole' was not saved on the child doc.
            if (resolvedRole == 'parent') {
              _initScreenCapture();

              // Backfill the role to the child document so future initializations are instant
              if (widget.userData['linkedCompanionRole'] == null) {
                _firestore
                    .collection('users')
                    .doc(widget.userData['id'])
                    .update({'linkedCompanionRole': 'parent'});
              }
            }
          }
        }
      } catch (e) {}
    }
  }

  /// Unlinks the current companion, removing their access to stats.
  Future<void> _unlinkCompanion() async {
    bool? confirm = await showCustomDialog<bool>(
      context: context,
      title: "Unlink Companion?",
      content: const Text("They will no longer see your stats."),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text("Cancel"),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text("Unlink", style: TextStyle(color: Colors.red)),
        ),
      ],
    );

    if (confirm != true) return;

    String? companionId = _companionId ?? widget.userData['linkedCompanion'];
    if (companionId == null) return;

    setState(() => _isLoading = true);

    try {
      final batch = _firestore.batch();

      // 1. Remove link from student
      final userRef = _firestore.collection('users').doc(widget.userData['id']);
      batch.update(userRef, {
        'linkedCompanion': null,
        'linkedCompanionRole': null,
        'companionName': null,
        'lockedApps': [],
        'lockEndTime': null,
      });

      // 2. Remove student from companion's list
      final companionRef = _firestore.collection('users').doc(companionId);
      batch.update(companionRef, {
        'linkedStudents': FieldValue.arrayRemove([widget.userData['id']]),
        'linkedUsers': FieldValue.arrayRemove([widget.userData['id']]),
      });

      // 3. End all active/requested sessions between these users
      final sessionsSnap = await _firestore
          .collection('companion_sessions')
          .where('userId', isEqualTo: widget.userData['id'])
          .where('companionId', isEqualTo: companionId)
          .where('status', whereIn: ['ACTIVE', 'REQUESTED'])
          .get();
      for (var doc in sessionsSnap.docs) {
        batch.update(doc.reference, {
          'status': 'ENDED',
          'endedAt': FieldValue.serverTimestamp(),
          'endReason': 'companion_unlinked',
        });
      }

      // 4. Clean up any pending unlock requests
      final unlockSnap = await _firestore
          .collection('unlock_requests')
          .where('studentId', isEqualTo: widget.userData['id'])
          .where('parentId', isEqualTo: companionId)
          .where('status', isEqualTo: 'pending')
          .get();
      for (var doc in unlockSnap.docs) {
        batch.update(doc.reference, {'status': 'cancelled'});
      }

      await batch.commit();

      // 5. Clear native locks since companion is gone
      NativeBlocker.setBlockedApps([]);
      NativeBlocker.setCompanionBlockedApps([]);

      if (mounted) {
        setState(() {
          companionActive = false;
          _companionName = null;
          _companionId = null;
          _companionRole = null;
          _activeSessionData = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Companion unlinked successfully")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Links a companion using the provided link code.
  Future<void> _linkCompanion() async {
    FocusScope.of(context).unfocus();
    final code = _companionCodeController.text.trim().toUpperCase();
    if (code.isEmpty) return;

    // Guard: already linked
    if (companionActive) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("You already have a companion linked. Unlink first."),
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      final query = await _firestore
          .collection('users')
          .where('linkCode', isEqualTo: code)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Invalid or expired code")),
          );
        }
        return;
      }

      final companionDoc = query.docs.first;
      final companionData = companionDoc.data();

      // Validate expiration
      final expiresAt = (companionData['linkCodeExpiresAt'] as Timestamp?)
          ?.toDate();
      if (expiresAt != null && DateTime.now().isAfter(expiresAt)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "This code has expired. Ask your companion for a new one.",
              ),
            ),
          );
        }
        return;
      }

      // Validate that target is actually a companion/parent, not another student
      final companionRole = companionData['role'] ?? 'user';
      if (companionRole == 'user') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Invalid code — this is not a companion account."),
            ),
          );
        }
        return;
      }

      // Prevent self-linking
      if (companionDoc.id == widget.userData['id']) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("You cannot link to yourself.")),
          );
        }
        return;
      }

      final batch = _firestore.batch();

      final userRef = _firestore.collection('users').doc(widget.userData['id']);
      batch.update(userRef, {
        'linkedCompanion': companionDoc.id,
        'linkedCompanionRole': companionRole,
        'companionName': companionDoc.data()['name'],
      });

      final companionRef = _firestore.collection('users').doc(companionDoc.id);
      batch.update(companionRef, {
        'linkedUsers': FieldValue.arrayUnion([widget.userData['id']]),
        'linkedStudents': FieldValue.arrayUnion([widget.userData['id']]),
      });

      await batch.commit();

      if (mounted) {
        setState(() {
          companionActive = true;
          _companionName = companionDoc.data()['name'];
          _companionId = companionDoc.id;
          _companionRole = companionDoc.data()['role'] ?? 'companion';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Successfully linked to $_companionName!")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showSettingsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? AppColors.cardOverlay : Colors.white.withValues(alpha: 0.95),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
        return SafeArea(
          child: Container(
            padding: const EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Settings", style: AppTheme.headerTitle(context)),
                const SizedBox(height: 24),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.redAccent),
                  title: Text(
                    "Log Out",
                    style: TextStyle(color: textColor),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onLogout();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUsage = _localStudyTime ?? widget.studyTime;
    final hasGoal = _dailyGoal != null;
    final progress = hasGoal
        ? (currentUsage / _dailyGoal!).clamp(0.0, 1.0)
        : 0.0;
    final remaining = hasGoal ? (_dailyGoal! - currentUsage) : 0;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white70 : Colors.black54;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: AppTheme.screenBackground(
          context,
          AppColors.roleGradients['user']!,
        ),
        child: SafeArea(
          child: Column(
            children: [
              DashboardHeader(
                userData: widget.userData,
                titleColor: textColor,
                subtitleColor: subTextColor,
                onSettingsTap: _showSettingsSheet,
              ),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.symmetric(
                    horizontal: 24.w,
                    vertical: 12.h,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_activeSessionData != null) ...[
                        SessionBanner(
                          activeSessionData: _activeSessionData!,
                          userId: widget.userData['id'],
                        ),
                        SizedBox(height: 24.h),
                      ],
                      if (_schedules.any(
                        (s) => ScheduleService().isCurrentlyActive(s),
                      )) ...[
                        _buildActiveScheduleBanner(),
                        SizedBox(height: 24.h),
                      ],
                      _buildDailyFocusHero(progress, remaining, isDark),
                      SizedBox(height: 32.h),
                      Text(
                        "QUICK ACTIONS",
                        style: TextStyle(
                          color: subTextColor.withValues(alpha: 0.5),
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                        ),
                      ),
                      SizedBox(height: 32.h),
                      DashboardActionGrid(
                        isDark: isDark,
                        studentId: widget.userData['id'],
                        studentName: widget.userData['name'] ?? "Student",
                        companionId: _companionId,
                        companionRole: _companionRole,
                        companionName: _companionName,
                        isSessionLocked: _activeSessionData != null,
                        appsUnlocked: widget.appsUnlocked,
                        onAppLockTap: _showAppLockModeDialog,
                      ),
                      SizedBox(height: 32.h),
                      _buildCompanionCard(isDark),
                      SizedBox(height: 48.h),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  /// Displays a banner when a companion session is active or requested.

  Widget _buildActiveScheduleBanner() {
    final activeCount = _schedules
        .where((s) => ScheduleService().isCurrentlyActive(s))
        .length;
    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("$activeCount schedule(s) currently active.")),
        );
      },
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(20.w),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
          ),
          borderRadius: BorderRadius.circular(24.r),
          boxShadow: [
            BoxShadow(
              color: Colors.purpleAccent.withValues(alpha: 0.4),
              blurRadius: 16.r,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(10.w),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Icon(Icons.schedule, color: Colors.white, size: 24.sp),
            ),
            SizedBox(width: 16.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Schedule Active",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16.sp,
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    "Apps are currently locked by a schedule.",
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 12.sp,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.info_outline, color: Colors.white70, size: 18.sp),
          ],
        ),
      ),
    );
  }

  String _formatMinutes(int minutes) {
    if (minutes < 60) return "${minutes}m";
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (m == 0) return "${h}h";
    return "${h}h ${m}m";
  }

  /// Shows a modal sheet to allow the user to set or update their daily focus goal.
  Future<void> _editDailyGoal() async {
    bool hasPermission = await PermissionManager.checkUsageStats(context);
    if (!hasPermission) return;

    if (!mounted) return;

    int? currentGoal = _dailyGoal;
    int selectedGoal = currentGoal ?? 60;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? AppColors.cardOverlay : Colors.white.withValues(alpha: 0.95),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheeState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
            final mutedColor = isDark ? Colors.grey[400]! : Colors.grey.shade600;
            return Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Set Daily Focus Goal",
                    style: AppTheme.headerTitle(context),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "How many minutes of screen time do you want to limit yourself to?",
                    style: TextStyle(color: mutedColor),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatMinutes(selectedGoal),
                        style: TextStyle(
                          color: isDark ? Colors.cyanAccent : Colors.cyan.shade700,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        "Limit",
                        style: TextStyle(
                          color: isDark ? Colors.white.withValues(alpha: 0.5) : Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: selectedGoal.toDouble(),
                    min: 15,
                    max: 480,
                    divisions: 31,
                    activeColor: Colors.cyanAccent,
                    inactiveColor: Colors.white10,
                    onChanged: (val) {
                      setSheeState(() => selectedGoal = val.toInt());
                    },
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      if (currentGoal != null)
                        Expanded(
                          child: TextButton(
                            onPressed: () {
                              Navigator.pop(context, -1); // -1 code for Remove
                            },
                            child: const Text(
                              "Remove Goal",
                              style: TextStyle(color: Colors.redAccent),
                            ),
                          ),
                        ),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context, selectedGoal),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.cyanAccent,
                            minimumSize: const Size(double.infinity, 50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            "Set Goal",
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    ).then((result) async {
      if (result != null) {
        setState(() {
          _dailyGoal = (result == -1) ? null : result;
        });

        try {
          if (result == -1) {
            await _firestore
                .collection('users')
                .doc(widget.userData['id'])
                .update({'dailyGoal': FieldValue.delete()});
          } else {
            await _firestore
                .collection('users')
                .doc(widget.userData['id'])
                .update({'dailyGoal': result});
          }
        } catch (e) {
          if (mounted) {
            setState(() => _dailyGoal = widget.dailyGoal);
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text("Error: $e")));
          }
        }
      }
    });
  }

  /// Refreshes local usage statistics and syncs with Firebase if permitted.
  Future<void> _refreshUsageStats() async {
    if (_isRefreshingUsage) return;
    setState(() => _isRefreshingUsage = true);

    try {
      final hasPerm = await _usageService.hasPermission();

      if (mounted) {
        setState(() => _hasPermission = hasPerm);
      }

      // Get local stats immediately (only if permitted, otherwise 0)
      final minutes = hasPerm ? await _usageService.getTodayUsageMinutes() : 0;
      if (mounted) {
        setState(() {
          _localStudyTime = minutes;
        });
        
        if (_dailyGoal != null && minutes >= _dailyGoal! && !_limitExceededNotified) {
          _limitExceededNotified = true;
          NotificationService().showInstantNotification(
            id: 999, // Specific ID for goal alert
            title: "Time Limit Exceeded",
            body: "You've exceeded your usage goal. Time to focus or take a rest!",
          );
        } else if (_dailyGoal != null && minutes < _dailyGoal!) {
          _limitExceededNotified = false; // Reset if they are somehow under again (e.g. next day)
        }
      }

      // Sync to cloud
      if (hasPerm) {
        _usageService.syncUsageToFirebase(widget.userData['id']);
      }
    } catch (e) {
      debugPrint("Error refreshing usage: $e");
    } finally {
      if (mounted) setState(() => _isRefreshingUsage = false);
    }
  }

  void _showAppLockModeDialog() {
    int? selectedMode; // null=none, 1=self, 2=companion

    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              title: Text(
                "Select Lock Mode",
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildLockModeOption(
                    isDark: isDark,
                    title: "Self Control",
                    subtitle: "You set the limits",
                    icon: Icons.person_outline,
                    color: Colors.blueAccent,
                    isSelected: selectedMode == 1,
                    onTap: () => setDialogState(() => selectedMode = 1),
                  ),
                  const SizedBox(height: 12),
                  _buildLockModeOption(
                    isDark: isDark,
                    title: "Companion Control",
                    subtitle: companionActive
                        ? "Request locks from companion"
                        : "Link a companion first",
                    icon: Icons.people_outline,
                    color: Colors.purpleAccent,
                    enabled: companionActive,
                    isSelected: selectedMode == 2,
                    onTap: () => setDialogState(() => selectedMode = 2),
                  ),
                  const SizedBox(height: 24),
                  // Confirm Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: selectedMode == null
                          ? null
                          : () {
                              Navigator.pop(context); // Close dialog
                              if (selectedMode == 1) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => AppLockScreen(
                                      userId: widget.userData['id'],
                                    ),
                                  ),
                                );
                              } else if (selectedMode == 2) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => CompanionRequestPage(
                                      userId: widget.userData['id'],
                                      companionId:
                                          _companionId ??
                                          widget.userData['linkedCompanion'],
                                      companionName:
                                          _companionName ??
                                          widget.userData['companionName'] ??
                                          "Companion",
                                    ),
                                  ),
                                );
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.cyanAccent,
                        foregroundColor: Colors.black,
                        disabledBackgroundColor: isDark
                            ? Colors.white10
                            : Colors.grey.shade300,
                        disabledForegroundColor: isDark
                            ? Colors.white38
                            : Colors.grey,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        "Confirm",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLockModeOption({
    required bool isDark,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool enabled = true,
    bool isSelected = false,
  }) {
    // Active border color if selected
    final borderColor = isSelected
        ? color
        : (enabled ? color.withValues(alpha: 0.3) : Colors.transparent);
    // Background color
    final bgColor = isSelected
        ? color.withValues(alpha: 0.15)
        : (enabled
              ? (isDark ? Colors.black26 : Colors.grey.shade50)
              : (isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.grey.shade200));

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: isSelected ? 2 : 1),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: enabled
                    ? color.withValues(alpha: 0.1)
                    : Colors.grey.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: enabled ? color : Colors.grey, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: enabled
                          ? (isDark ? Colors.white : Colors.black87)
                          : Colors.grey,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: enabled
                          ? (isDark ? Colors.white70 : Colors.black54)
                          : Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, size: 20, color: color)
            else if (enabled)
              Icon(
                Icons.radio_button_unchecked,
                size: 20,
                color: isDark ? Colors.white30 : Colors.black26,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyFocusHero(double progress, int remaining, bool isDark) {
    final displayTime = _localStudyTime ?? widget.studyTime;

    if (_dailyGoal == null) {
      // Empty State (No Goal)
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: isDark ? Colors.white10 : Colors.grey.shade200,
          ),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black26
                  : Colors.grey.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: (isDark ? Colors.blueAccent : Colors.blue).withValues(
                  alpha: 0.1,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.track_changes,
                color: isDark ? Colors.blueAccent : Colors.blue,
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "Set a Daily Goal",
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Track your screen time and stay focused.",
              textAlign: TextAlign.center,
              style: TextStyle(color: isDark ? Colors.white70 : Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _editDailyGoal,
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? Colors.blueAccent : Colors.blue,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text("Set Goal"),
            ),
          ],
        ),
      );
    }

    // DYNAMIC STATE
    // Colors: Green (<50%), Amber (50-99%), Red (>=100%)
    Color accentColor;
    String statusText;

    if (progress >= 1.0) {
      accentColor = Colors.redAccent;
      statusText = "Over Limit";
    } else if (progress > 0.5) {
      accentColor = Colors.orangeAccent;
      statusText = "Approaching Limit";
    } else {
      accentColor = Colors.greenAccent;
      statusText = "Safe Usage";
    }

    // Adjusted Palette for Card Background
    List<Color> bgColors = isDark
        ? (progress >= 1.0
              ? [
                  const Color(0xFF450A0A).withValues(alpha: 0.8),
                  const Color(0xFF250505),
                ] // Dark Red
              : progress > 0.5
              ? [
                  const Color(0xFF451A03).withValues(alpha: 0.8),
                  const Color(0xFF270E02),
                ] // Dark Orange
              : [
                  const Color(0xFF064E3B).withValues(alpha: 0.8),
                  const Color(0xFF022C22),
                ]) // Dark Green
        : (progress >= 1.0
              ? [Colors.red.shade50, Colors.red.shade100]
              : progress > 0.5
              ? [Colors.orange.shade50, Colors.orange.shade100]
              : [Colors.green.shade50, Colors.green.shade100]);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          if (await PermissionManager.checkUsageStats(context)) {
            if (context.mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AnalyticsScreen(
                    userId: widget.userData['id'],
                    userName: widget.userData['name'] ?? "My",
                  ),
                ),
              );
            }
          }
        },
        borderRadius: BorderRadius.circular(30),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: bgColors,
            ),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.3),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              "DAILY GOAL",
                              style: TextStyle(
                                color: accentColor,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5,
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Refresh Button
                            if (_isRefreshingUsage)
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.cyanAccent,
                                ),
                              )
                            else
                              InkWell(
                                onTap: _refreshUsageStats,
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.all(4.0),
                                  child: Icon(
                                    Icons.refresh,
                                    size: 16,
                                    color: accentColor.withValues(alpha: 0.8),
                                  ),
                                ),
                              ),
                            const SizedBox(width: 8),
                            // Edit Button
                            InkWell(
                              onTap: _editDailyGoal,
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.all(4.0),
                                child: Icon(
                                  Icons.edit,
                                  size: 16,
                                  color: accentColor.withValues(alpha: 0.8),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: _formatMinutes(displayTime),
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black,
                                  fontSize: 30,
                                  fontWeight: FontWeight.bold,
                                  height: 1.0,
                                ),
                              ),
                              TextSpan(
                                text: " / ${_formatMinutes(_dailyGoal!)}",
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.black54,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                  height: 1.0,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 4),
                        Text(
                          statusText,
                          style: TextStyle(
                            color: accentColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Progress Circle OR Enable Button
                  if (_hasPermission) ...[
                    Container(
                      width: 60,
                      height: 60,
                      child: Stack(
                        children: [
                          Center(
                            child: SizedBox(
                              width: 60,
                              height: 60,
                              child: CircularProgressIndicator(
                                value: progress,
                                backgroundColor: Colors.black12,
                                color: accentColor,
                                strokeWidth: 6,
                              ),
                            ),
                          ),
                          Center(
                            child: Text(
                              "${(progress * 100).toInt()}%",
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black87,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 14,
                      color: isDark ? Colors.white30 : Colors.black26,
                    ),
                  ] else ...[
                    ElevatedButton(
                      onPressed: () async {
                        if (await PermissionManager.checkUsageStats(context)) {
                          _refreshUsageStats();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor.withValues(alpha: 0.2),
                        foregroundColor: accentColor,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                      ),
                      child: const Text(
                        "Enable Usage",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompanionCard(bool isDark) {
    return Container(
      padding: EdgeInsets.all(28.w),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  Colors.white.withValues(alpha: 0.05),
                  Colors.white.withValues(alpha: 0.02),
                ]
              : [Colors.white, Colors.white.withValues(alpha: 0.9)],
        ),
        borderRadius: BorderRadius.circular(32.r),
        border: Border.all(
          color: companionActive
              ? Colors.cyan.withValues(alpha: 0.3)
              : (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.white),
          width: companionActive ? 1.5.w : 1.w,
        ),
        boxShadow: companionActive
            ? [
                BoxShadow(
                  color: Colors.cyanAccent.withValues(alpha: 0.15),
                  blurRadius: 24.r,
                  offset: const Offset(0, 8),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                  blurRadius: 16.r,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(12.w),
                decoration: BoxDecoration(
                  color: companionActive
                      ? Colors.cyan.withValues(alpha: 0.2)
                      : (isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.grey.shade200),
                  borderRadius: BorderRadius.circular(16.r),
                ),
                child: Icon(
                  Icons.group,
                  color: companionActive
                      ? Colors.cyanAccent
                      : (isDark ? Colors.white70 : Colors.black87),
                  size: 28.sp,
                ),
              ),
              SizedBox(width: 16.w),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "COMPANION MODE",
                    style: TextStyle(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.9)
                          : Colors.black87,
                      fontSize: 12.sp,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    companionActive ? "Active & Linked" : "Not connected",
                    style: TextStyle(
                      color: companionActive ? Colors.greenAccent : Colors.grey,
                      fontWeight: FontWeight.w600,
                      fontSize: 15.sp,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          if (companionActive) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? Colors.black26 : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? Colors.white10 : Colors.transparent,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.link,
                    color: isDark ? Colors.white54 : Colors.black45,
                    size: 20,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "LINKED TO",
                          style: TextStyle(
                            color: isDark
                                ? Colors.white38
                                : Colors.grey.shade600,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _companionName ??
                              widget.userData['companionName'] ??
                              'Unknown',
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // 5. Unlink Button (Hidden for Parent-linked students)
            if (_companionRole != 'parent')
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: (_isLoading || _activeSessionData != null)
                      ? null
                      : _unlinkCompanion,
                  icon: _isLoading
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.redAccent,
                          ),
                        )
                      : Icon(
                          Icons.link_off,
                          size: 18,
                          color: (_activeSessionData != null)
                              ? Colors.grey
                              : Colors.redAccent,
                        ),
                  label: Text(
                    _activeSessionData != null
                        ? "Session Active"
                        : (_isLoading ? "Processing..." : "Unlink Companion"),
                    style: TextStyle(
                      color: (_activeSessionData != null)
                          ? Colors.grey
                          : Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: (_activeSessionData != null)
                          ? Colors.white10
                          : Colors.redAccent.withValues(alpha: 0.3),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              )
            else
              // Parent Mode Info
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.security, color: Colors.orange, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "Parental Control Active. Unlinking is restricted.",
                        style: TextStyle(
                          color: isDark
                              ? Colors.orangeAccent
                              : Colors.orange.shade800,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ] else ...[
            Text(
              "Link a companion to unlock powerful accountability features.",
              style: TextStyle(
                color: isDark ? Colors.white54 : Colors.black54,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.black12 : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark ? Colors.white10 : Colors.grey.shade300,
                      ),
                    ),
                    child: TextField(
                      controller: _companionCodeController,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 16,
                      ),
                      decoration: InputDecoration(
                        hintText: "Enter Link Code",
                        hintStyle: TextStyle(
                          color: isDark ? Colors.white30 : Colors.black38,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 16,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  decoration: BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: Colors.cyan.withValues(alpha: 0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _linkCompanion,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyanAccent,
                      foregroundColor: Colors.black87,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : const Icon(
                            Icons.arrow_forward,
                            color: Colors.black87,
                          ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
