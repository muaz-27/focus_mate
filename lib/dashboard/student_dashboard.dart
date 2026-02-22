import 'dart:async';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:focus_mate/main.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../core/auth_service.dart';
import '../core/models/user_model.dart';
import '../core/screen_capture_service.dart';
import '../core/permission_manager.dart';
import '../core/usage_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import './analytics_screen.dart';
import './app_lock_screen.dart';
import './companion_request_page.dart';
import './session_setup_screen.dart';
import './study_workspace_screen.dart';
import './companion_controlled_page.dart';
import './waiting_for_companion_page.dart';
import '../core/widgets/custom_dialog.dart';
import '../core/native_blocker.dart';

/// Entry point for the student dashboard.
/// 
/// Handles initial authentication verification and profile data loading.
/// Redirects to [AuthGate] if user is not authenticated or profile is missing.
class StudentDashboardLoader extends StatelessWidget {
  const StudentDashboardLoader({super.key});

  @override
  Widget build(BuildContext context) {
    final initialUser = FirebaseAuth.instance.currentUser;

    if (initialUser == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthGate()),
          (route) => false,
        );
      });
      
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text("Signing out..."),
            ],
          ),
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(initialUser.uid)
          .snapshots(),
      builder: (context, snapshot) {
        print("F_MATE: StudentDashboardLoader builder triggered! connectionState=${snapshot.connectionState}, hasData=${snapshot.hasData}");
        // Dynamic check to handle logout race conditions
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser == null) {
           WidgetsBinding.instance.addPostFrameCallback((_) {
             Navigator.of(context).pushAndRemoveUntil(
               MaterialPageRoute(builder: (_) => const AuthGate()),
               (route) => false,
             );
           });
           return const Scaffold(body: Center(child: Text("Signing out...")));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: CircularProgressIndicator(color: Colors.cyanAccent),
            ),
          );
        }

        if (snapshot.hasError) {
          if (FirebaseAuth.instance.currentUser == null) {
             WidgetsBinding.instance.addPostFrameCallback((_) {
               Navigator.of(context).pushAndRemoveUntil(
                 MaterialPageRoute(builder: (_) => const AuthGate()),
                 (route) => false,
               );
             });
             return const Scaffold(body: Center(child: Text("Signing out...")));
          }
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: CircularProgressIndicator(color: Colors.cyanAccent),
            ),
          );
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: Text(
                "Error loading profile",
                style: TextStyle(color: Colors.white),
              ),
            ),
          );
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        data['id'] = currentUser.uid;
        
        print("F_MATE: StreamBuilder received data update. snapshotRequest=${data['snapshotRequest']}");

        final int studyTime = data['todayStudyMinutes'] ?? 0;
        final int? dailyGoal = data['dailyGoal'];
        final bool appsUnlocked =
            (data['appLockMode'] ?? 'normal') == 'unlocked';
        final bool companionActive = data['linkedCompanion'] != null;

        return StudentDashboard(
          userData: data,
          studyTime: studyTime,
          dailyGoal: dailyGoal,
          activeSession: false,
          companionActive: companionActive,
          appsUnlocked: appsUnlocked,
          onLogout: () => AuthService().signOut(),
          onStartSession: (_) {},
        );
      },
    );
  }
}

/// Main dashboard widget for students.
/// 
/// Displays daily study statistics, goal progress, and allows access to 
/// session features and settings.
class StudentDashboard extends StatefulWidget {
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
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard>
    with WidgetsBindingObserver {
  final UsageService _usageService = UsageService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  // static const platform = MethodChannel('com.example.focus_mate/blocker'); // REMOVED: Using NativeBlocker class

  Timer? _ruleSyncTimer;
  Timer? _usageSyncTimer;
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

  @override
  void initState() {
    super.initState();
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
        
    // Apply locks immediately (don't wait for timer)
    _applyNativeLock();
    
    _refreshUsageStats();
    _startRuleSync();
    _getCompanionDetails();
    _checkActiveSession();

    // Direct listener to handle snapshotRequest in real-time
    // Skip the first event so stale snapshotRequest from a previous session doesn't race with permission flow
    bool _snapshotListenerReady = false;
    _userDocSubscription = FirebaseFirestore.instance.collection('users').doc(widget.userData['id']).snapshots().listen((docSnap) {
      if (!mounted) return;
      if (!_snapshotListenerReady) {
        _snapshotListenerReady = true;
        return; // Skip the first event — it reflects old state, not a new parent request
      }
      if (docSnap.exists) {
        final data = docSnap.data() as Map<String, dynamic>;
        print("F_MATE: Direct Listener saw snapshotRequest=${data['snapshotRequest']}");
        if (data['snapshotRequest'] == true) {
           _handleSnapshotRequest();
        }
      }
    });

    // Sync usage data in background
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _usageService.syncUsageToFirebase(widget.userData['id']);
      _usageService.syncInstalledAppsToFirebase(widget.userData['id']);
      if (companionActive) {
        print("F_MATE: companionActive=true, calling _initScreenCapture");
        _initScreenCapture();
      } else {
        print("F_MATE: companionActive=false, skipping screen capture init. linkedCompanion=${widget.userData['linkedCompanion']}");
      }
    });

    // Sync usage stats every 1 minute to keep UI fresh
    _usageSyncTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _refreshUsageStats();
    });
  }

  @override
  void didUpdateWidget(StudentDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Check if linkedCompanion changed
    if (widget.userData['linkedCompanion'] != oldWidget.userData['linkedCompanion']) {
      setState(() {
        companionActive = widget.userData['linkedCompanion'] != null;
        if (!companionActive) {
          _companionName = null;
          _companionId = null;
          _companionRole = null;
        } else {
             _companionId = widget.userData['linkedCompanion'];
             _companionRole = widget.userData['linkedCompanionRole'];
        }
      });
      _getCompanionDetails();
      
      if (companionActive && oldWidget.userData['linkedCompanion'] == null) {
        ScreenCaptureService.requestPermission();
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
    final List<String> oldLocked = List<String>.from(oldWidget.userData['lockedApps'] ?? []);
    final List<String> newLocked = List<String>.from(widget.userData['lockedApps'] ?? []);
    final DateTime? oldEndTime = oldWidget.userData['lockEndTime'] != null 
        ? (oldWidget.userData['lockEndTime'] as Timestamp).toDate() 
        : null;
    final DateTime? newEndTime = widget.userData['lockEndTime'] != null 
        ? (widget.userData['lockEndTime'] as Timestamp).toDate() 
        : null;

    if (newLocked.toString() != oldLocked.toString() || newEndTime != oldEndTime) {
       setState(() {
         _blockedList = newLocked;
         _lockEndTime = newEndTime;
       });
       _applyNativeLock();
    }

    // Check for snapshotRequest
    final bool oldSnapshotRequest = oldWidget.userData['snapshotRequest'] == true;
    final bool newSnapshotRequest = widget.userData['snapshotRequest'] == true;
    
    print("F_MATE: didUpdateWidget -> oldSnapshotReq: $oldSnapshotRequest, newSnapshotReq: $newSnapshotRequest");
    
    if (!oldSnapshotRequest && newSnapshotRequest) {
      _handleSnapshotRequest();
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

  Future<void> _handleSnapshotRequest() async {
    print("F_MATE: _handleSnapshotRequest triggered!");
    final String childId = widget.userData['id'];

    Uint8List? bytes;
    // Retry loop: waits up to ~12 seconds for the user to accept the permission dialog
    for (int attempt = 0; attempt < 8; attempt++) {
      bytes = await ScreenCaptureService.captureScreen();
      if (bytes != null) break;
      print("F_MATE: capture attempt $attempt failed (service not ready), retrying...");
      await Future.delayed(const Duration(milliseconds: 1500));
    }

    try {
      if (bytes != null) {
        final String base64Image = base64Encode(bytes);
        await _firestore.collection('users').doc(childId).collection('snapshots').add({
          'timestamp': FieldValue.serverTimestamp(),
          'imageBase64': base64Image,
          'capturedBy': 'parent',
        });
        print("F_MATE: snapshot saved successfully.");
      } else {
        print("F_MATE: all capture attempts failed — service not available.");
      }
    } catch (e) {
      debugPrint("F_MATE: Save failed: $e");
    } finally {
      await _firestore.collection('users').doc(childId).update({'snapshotRequest': false});
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
             final aTime = (a.data()['requestedAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
             final bTime = (b.data()['requestedAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
             return bTime.compareTo(aTime);
           });
           
           // Find the first valid doc (Active, or Recent Request)
           DocumentSnapshot? validDoc;
           final now = DateTime.now();
           
           for (var doc in docs) {
             final data = doc.data();
             final status = data['status'];
             final requestedAt = (data['requestedAt'] as Timestamp?)?.toDate();
             
             if (status == 'ACTIVE') {
               validDoc = doc;
               break; 
             } else if (status == 'REQUESTED') {
               // Only show requests from the last 30 minutes
               if (requestedAt != null && now.difference(requestedAt).inMinutes < 30) {
                 validDoc = doc;
                 break;
               }
             }
           }
           
           if (validDoc != null) {
              setState(() {
                _activeSessionData = validDoc!.data() as Map<String, dynamic>;
                _activeSessionData!['id'] = validDoc!.id;
              });
           } else {
             setState(() {
              _activeSessionData = null;
             });
           }
        } else {
          setState(() {
            _activeSessionData = null;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _ruleSyncTimer?.cancel();
    _usageSyncTimer?.cancel();
    _activeSessionSubscription?.cancel();
    _userDocSubscription?.cancel();
    _companionCodeController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (mounted) {
         _refreshUsageStats();
         _checkActiveSession();
      }
    }
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
  Future<void> _applyNativeLock() async {
    // Determine effective block list
    bool shouldBlock = _blockedList.isNotEmpty && (_lockEndTime == null || DateTime.now().isBefore(_lockEndTime!));
    final appsToSend = shouldBlock ? _blockedList : <String>[];
    
    try {
      if (appsToSend.isEmpty) {
        // HARD RESET: If unlocking, clear ALL channels to ensure no zombie locks remain
        await NativeBlocker.setBlockedApps([]);
        await NativeBlocker.setCompanionBlockedApps([]);
      } else {
        // Applying lock: Use main channel, clear secondary channel to avoid conflicts
        await NativeBlocker.setBlockedApps(appsToSend);
        await NativeBlocker.setCompanionBlockedApps([]);
      }
    } catch (e) {
      debugPrint("Error syncing blocked apps: $e");
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
    if (_companionName != null) return;
    String? companionId = widget.userData['linkedCompanion'];
    if (companionId != null) {
      try {
        DocumentSnapshot doc = await _firestore
            .collection('users')
            .doc(companionId)
            .get();
        if (doc.exists) {
          if (mounted) {
            setState(() {
              _companionName = doc['name'];
              // If role is missing, assume companion for backward compatibility, unless explicitly parent
              _companionRole = doc.data().toString().contains('role') ? doc['role'] : 'companion'; 
              companionActive = true;
            });
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
      
      final userRef = _firestore.collection('users').doc(widget.userData['id']);
      batch.update(userRef, {'linkedCompanion': null});
      
      final companionRef = _firestore.collection('users').doc(companionId);
      batch.update(companionRef, {
        'linkedStudents': FieldValue.arrayRemove([widget.userData['id']]),
      });

      await batch.commit();

      if (mounted) {
        setState(() {
          companionActive = false;
          _companionName = null;
          _companionId = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Links a companion using the provided link code.
  Future<void> _linkCompanion() async {
    final code = _companionCodeController.text.trim();
    if (code.isEmpty) return;
    
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
            const SnackBar(content: Text("Invalid code")),
          );
        }
        return;
      }

      final companionDoc = query.docs.first;
      
      final batch = _firestore.batch();
      
      final userRef = _firestore.collection('users').doc(widget.userData['id']);
      // NEW: Store role for quick access
      batch.update(userRef, {
        'linkedCompanion': companionDoc.id,
        'linkedCompanionRole': companionDoc.data()['role'] ?? 'companion',
      });
      
      final companionRef = _firestore.collection('users').doc(companionDoc.id);
      batch.update(companionRef, {
        'linkedUsers': FieldValue.arrayUnion([widget.userData['id']]),
      });

      await batch.commit();

      if (mounted) {
        setState(() {
          companionActive = true;
          _companionName = companionDoc.data()['name'];
          _companionId = companionDoc.id;
          _companionRole = companionDoc.data()['role'] ?? 'companion';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
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
      backgroundColor: AppColors.cardOverlay,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Settings", style: AppTheme.headerTitle),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.battery_std, color: Colors.cyanAccent),
              title: const Text("Battery Optimization", style: TextStyle(color: Colors.white)),
              subtitle: const Text("Prevent app from being killed", style: TextStyle(color: Colors.white54)),
              onTap: () async {
                Navigator.pop(context);
                await PermissionManager.checkBatteryOptimizations(context);
              },
            ),
            const Divider(color: Colors.white12),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: const Text("Log Out", style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                AuthService().signOut();
              },
            ),
          ],
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final currentUsage = _localStudyTime ?? widget.studyTime;
    final hasGoal = _dailyGoal != null;
    final progress = hasGoal ? (currentUsage / _dailyGoal!).clamp(0.0, 1.0) : 0.0;
    final remaining = hasGoal ? (_dailyGoal! - currentUsage) : 0;
    
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white70 : Colors.black54;

    return Scaffold(
      extendBodyBehindAppBar: true, 
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark 
              ? [const Color(0xFF1A1F35), const Color(0xFF0B0E17)] 
              : [const Color(0xFFF8FAFC), const Color(0xFFE2E8F0)],
            stops: const [0.0, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(textColor, subTextColor),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_activeSessionData != null) ...[
                        _buildActiveSessionBanner(),
                        const SizedBox(height: 24),
                      ],
                      _buildDailyFocusHero(progress, remaining, isDark),
                      const SizedBox(height: 32), 
                      Text("QUICK ACTIONS", 
                        style: TextStyle(
                          color: subTextColor.withOpacity(0.5), 
                          fontSize: 12, 
                          fontWeight: FontWeight.w600, 
                          letterSpacing: 1.2
                        )
                      ),
                      const SizedBox(height: 12),
                      _buildActionGrid(isDark),
                      const SizedBox(height: 32),
                      Text("MANAGEMENT", 
                        style: TextStyle(
                          color: subTextColor.withOpacity(0.5), 
                          fontSize: 12, 
                          fontWeight: FontWeight.w600, 
                          letterSpacing: 1.2
                        )
                      ),
                      const SizedBox(height: 12),
                      _buildManagementGrid(isDark),
                      const SizedBox(height: 32),
                      _buildCompanionCard(isDark), 
                      const SizedBox(height: 48),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(Color titleColor, Color subtitleColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Welcome back,",
                style: TextStyle(color: subtitleColor, fontSize: 13, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              Text(
                widget.userData['name'] ?? "Student",
                style: AppTheme.headerTitle.copyWith(
                  color: titleColor, 
                  fontSize: 28, 
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.5
                ),
              ),
            ],
          ),
          Container(
            decoration: BoxDecoration(
              color: titleColor.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: titleColor.withOpacity(0.1)),
            ),
            child: IconButton(
              onPressed: _showSettingsSheet,
              icon: Icon(Icons.settings, color: titleColor),
            ),
          ),
        ],
      ),
    );
  }

  /// Displays a banner when a companion session is active or requested.
  Widget _buildActiveSessionBanner() {
    final isActive = _activeSessionData!['status'] == 'ACTIVE';
    return GestureDetector(
      onTap: () {
         final status = _activeSessionData!['status'];
         final sessionId = _activeSessionData!['id'];

         if (status == 'ACTIVE') {
           Navigator.push(context, MaterialPageRoute(builder: (_) => CompanionControlledPage(sessionId: sessionId, userId: widget.userData['id'])));
         } else if (status == 'REQUESTED') {
            Navigator.push(context, MaterialPageRoute(builder: (_) => WaitingForCompanionPage(sessionId: sessionId, userId: widget.userData['id'])));
         }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isActive 
                ? [const Color(0xFFEF4444), const Color(0xFFDC2626)]
                : [const Color(0xFFF59E0B), const Color(0xFFD97706)],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: (isActive ? Colors.redAccent : Colors.orangeAccent).withOpacity(0.4),
              blurRadius: 16,
              offset: const Offset(0, 8),
            )
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(isActive ? Icons.lock_clock : Icons.hourglass_top, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isActive ? "Session Active" : "Waiting for Companion",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isActive ? "Your app access is currently managed." : "Tap to verify your connection status.",
                    style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 14),
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
      backgroundColor: AppColors.cardOverlay,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheeState) {
            return Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   const Text("Set Daily Focus Goal", style: AppTheme.headerTitle),
                   const SizedBox(height: 8),
                   const Text("How many minutes of screen time do you want to limit yourself to?", 
                     style: TextStyle(color: Colors.grey)
                   ),
                   const SizedBox(height: 32),
                   Row(
                     mainAxisAlignment: MainAxisAlignment.spaceBetween,
                     children: [
                        Text(_formatMinutes(selectedGoal), 
                          style: const TextStyle(color: Colors.cyanAccent, fontSize: 24, fontWeight: FontWeight.bold)
                        ),
                        Text("Limit", style: TextStyle(color: Colors.white.withOpacity(0.5))),
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
                             child: const Text("Remove Goal", style: TextStyle(color: Colors.redAccent)),
                           ),
                         ),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(context, selectedGoal),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.cyanAccent,
                              minimumSize: const Size(double.infinity, 50),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text("Set Goal", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                          ),
                        ),
                     ],
                   ),
                   const SizedBox(height: 20),
                ],
              ),
            );
          }
        );
      }
    ).then((result) async {
       if (result != null) {
          setState(() {
             _dailyGoal = (result == -1) ? null : result;
          });

          try {
            if (result == -1) {
              await _firestore.collection('users').doc(widget.userData['id']).update({
                'dailyGoal': FieldValue.delete(),
              });
            } else {
              await _firestore.collection('users').doc(widget.userData['id']).update({
                'dailyGoal': result,
              });
            }
          } catch (e) {
            if (mounted) {
               setState(() => _dailyGoal = widget.dailyGoal);
               ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
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
              title: Text("Select Lock Mode", style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
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
                    subtitle: companionActive ? "Request locks from companion" : "Link a companion first",
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
                      onPressed: selectedMode == null ? null : () {
                        Navigator.pop(context); // Close dialog
                        if (selectedMode == 1) {
                           Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => AppLockScreen(userId: widget.userData['id'])),
                          );
                        } else if (selectedMode == 2) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CompanionRequestPage(
                                userId: widget.userData['id'],
                                companionId: _companionId ?? widget.userData['linkedCompanion'],
                                companionName: _companionName ?? widget.userData['companionName'] ?? "Companion",
                              ),
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.cyanAccent,
                        foregroundColor: Colors.black,
                        disabledBackgroundColor: isDark ? Colors.white10 : Colors.grey.shade300,
                        disabledForegroundColor: isDark ? Colors.white38 : Colors.grey,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text("Confirm", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  )
                ],
              ),
            );
          }
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
    final borderColor = isSelected ? color : (enabled ? color.withOpacity(0.3) : Colors.transparent);
    // Background color
    final bgColor = isSelected 
        ? color.withOpacity(0.15)
        : (enabled 
            ? (isDark ? Colors.black26 : Colors.grey.shade50) 
            : (isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade200));

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
                color: enabled ? color.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: enabled ? color : Colors.grey, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: enabled ? (isDark ? Colors.white : Colors.black87) : Colors.grey, fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(color: enabled ? (isDark ? Colors.white70 : Colors.black54) : Colors.grey, fontSize: 12)),
                ],
              ),
            ),
            if (isSelected) 
              Icon(Icons.check_circle, size: 20, color: color)
            else if (enabled) 
              Icon(Icons.radio_button_unchecked, size: 20, color: isDark ? Colors.white30 : Colors.black26),
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
          border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.black26 : Colors.grey.withOpacity(0.05),
              blurRadius: 16,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: (isDark ? Colors.blueAccent : Colors.blue).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.track_changes, color: isDark ? Colors.blueAccent : Colors.blue, size: 32),
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
              style: TextStyle(color: isDark ? Colors.white54 : Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _editDailyGoal,
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? Colors.blueAccent : Colors.blue,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("Set Goal"),
            )
          ],
        ),
      );
    }

    // DYNAMIC STATE
    // Colors: Green (<50%), Amber (50-99%), Red (>=100%)
    List<Color> gradientColors;
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
            ? [const Color(0xFF450A0A).withOpacity(0.8), const Color(0xFF250505)] // Dark Red
            : progress > 0.5 
                ? [const Color(0xFF451A03).withOpacity(0.8), const Color(0xFF270E02)] // Dark Orange
                : [const Color(0xFF064E3B).withOpacity(0.8), const Color(0xFF022C22)]) // Dark Green
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
            border: Border.all(color: accentColor.withOpacity(0.3), width: 1),
            boxShadow: [
              BoxShadow(
                color: accentColor.withOpacity(0.15),
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
                         Text("DAILY GOAL", 
                          style: TextStyle(
                            color: accentColor, 
                            fontSize: 12, 
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          )
                        ),
                        const SizedBox(width: 8),
                        // Refresh Button
                        if (_isRefreshingUsage) 
                          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent))
                        else
                          InkWell(
                            onTap: _refreshUsageStats,
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: Icon(Icons.refresh, size: 16, color: accentColor.withOpacity(0.8)),
                            ),
                          ),
                        const SizedBox(width: 8),
                        // Edit Button
                        InkWell(
                          onTap: _editDailyGoal,
                          borderRadius: BorderRadius.circular(12),
                          child:  Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Icon(Icons.edit, size: 16, color: accentColor.withOpacity(0.8)),
                          ),
                        )
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
                            )
                          ),
                          TextSpan(
                            text: " / ${_formatMinutes(_dailyGoal!)}", 
                            style: TextStyle(
                              color: isDark ? Colors.white54 : Colors.black54, 
                              fontSize: 18, 
                              fontWeight: FontWeight.w500,
                              height: 1.0,
                            )
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 4),
                    Text(statusText, style: TextStyle(color: accentColor, fontWeight: FontWeight.bold, fontSize: 13)),
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
                           width: 60, height: 60,
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
                           style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 14),
                         ),
                       ),
                     ],
                   ),
                ),
                 const SizedBox(width: 16),
                 Icon(Icons.arrow_forward_ios, size: 14, color: isDark ? Colors.white30 : Colors.black26),
              ] else ...[
                 ElevatedButton(
                   onPressed: () async {
                      if (await PermissionManager.checkUsageStats(context)) {
                        _refreshUsageStats();
                      }
                   },
                   style: ElevatedButton.styleFrom(
                     backgroundColor: accentColor.withOpacity(0.2),
                     foregroundColor: accentColor,
                     elevation: 0,
                     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                     padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                   ),
                   child: const Text("Enable Usage", style: TextStyle(fontWeight: FontWeight.bold)),
                 )
              ]
            ],
          ),
        ],
      ),
    )));
  }

  Widget _buildActionGrid(bool isDark) {
    // If Parent Mode, hide "Start Session"
    if (_companionRole == 'parent') {
      return Row(
        children: [
           Expanded(
            child: _buildGlassTile(
              isDark: isDark,
              title: "Workspace",
              icon: Icons.book,
              color: Colors.purpleAccent,
              onTap: () {
                 Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StudyWorkspaceScreen(userId: widget.userData['id']),
                  ),
                );
              },
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: _buildGlassTile(
            isDark: isDark,
            title: "Start Session",
            icon: Icons.play_circle_fill,
            color: Colors.cyan,
            onTap: () {
               Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SessionSetupScreen(userId: widget.userData['id']),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildGlassTile(
            isDark: isDark,
            title: "Workspace",
            icon: Icons.book,
            color: Colors.purpleAccent,
            onTap: () {
               Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StudyWorkspaceScreen(userId: widget.userData['id']),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildManagementGrid(bool isDark) {
    final bool isSessionLocked = _activeSessionData != null;
    
    // If Parent Mode, hide "App Lock" (Only Analytics)
    if (_companionRole == 'parent') {
       return Row(
        children: [
          Expanded(
            child: _buildGlassTile(
              isDark: isDark,
              title: "Analytics",
              icon: Icons.bar_chart,
              color: Colors.green,
              subtitle: "Stats",
              onTap: () async {
                if (await PermissionManager.checkUsageStats(context)) {
                  if (context.mounted) {
                    Navigator.push(
                      context, 
                      MaterialPageRoute(
                        builder: (_) => AnalyticsScreen(
                          userId: widget.userData['id'],
                          userName: "My Stats",
                        ) 
                      )
                    );
                  }
                }
              },
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: _buildGlassTile(
            isDark: isDark,
            title: "App Lock",
            icon: isSessionLocked ? Icons.lock : Icons.phonelink_lock,
            color: isSessionLocked ? Colors.grey : Colors.orangeAccent,
            subtitle: isSessionLocked ? "Locked" : widget.appsUnlocked ? "Unlocked" : "Active",
            onTap: () async {
              if (isSessionLocked) {
                 ScaffoldMessenger.of(context).showSnackBar(
                   const SnackBar(content: Text("App Lock is managed by active session."))
                 );
                 return;
              }
              if (await PermissionManager.checkAccessibility(context)) {
                if (context.mounted) {
                   _showAppLockModeDialog();
                }
              }
            },
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildGlassTile(
            isDark: isDark,
            title: "Analytics",
            icon: Icons.bar_chart,
            color: Colors.green,
            subtitle: "Stats",
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
          ),
        ),
      ],
    );
  }
  
  Widget _buildGlassTile({
    required bool isDark,
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    String? subtitle,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 110), 
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark 
               ? [Colors.white.withOpacity(0.07), Colors.white.withOpacity(0.03)]
               : [Colors.white, Colors.grey.shade50],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: isDark ? Colors.white.withOpacity(0.08) : Colors.white, width: 1),
          boxShadow: [
             BoxShadow(
               color: isDark ? Colors.black.withOpacity(0.2) : Colors.grey.withOpacity(0.1), 
               blurRadius: 16, 
               offset: const Offset(0, 8)
             )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 16), 
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, 
                  style: TextStyle(
                    color: isDark ? Colors.white.withOpacity(0.9) : Colors.black87, 
                    fontWeight: FontWeight.bold, 
                    fontSize: 16
                  )
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle, 
                    style: TextStyle(
                      color: isDark ? Colors.white54 : Colors.black54, 
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    )
                  ),
                ]
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompanionCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
         gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark 
               ? [Colors.white.withOpacity(0.05), Colors.white.withOpacity(0.02)]
               : [Colors.white, Colors.white.withOpacity(0.9)],
         ),
         borderRadius: BorderRadius.circular(32),
         border: Border.all(
           color: companionActive ? Colors.cyan.withOpacity(0.3) : (isDark ? Colors.white.withOpacity(0.08) : Colors.white),
           width: companionActive ? 1.5 : 1
         ),
         boxShadow: companionActive
            ? [BoxShadow(color: Colors.cyanAccent.withOpacity(0.15), blurRadius: 24, offset: const Offset(0, 8))]
            : [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.2 : 0.05), blurRadius: 16, offset: const Offset(0, 8))],
      ),
       child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: companionActive ? Colors.cyan.withOpacity(0.2) : (isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade200),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.group, color: companionActive ? Colors.cyanAccent : (isDark ? Colors.white70 : Colors.black87), size: 28),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "COMPANION MODE", 
                      style: TextStyle(
                        color: isDark ? Colors.white.withOpacity(0.9) : Colors.black87, 
                        fontSize: 12, 
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      )
                    ),
                    const SizedBox(height: 4),
                    Text(
                      companionActive ? "Active & Linked" : "Not connected",
                      style: TextStyle(
                        color: companionActive ? Colors.greenAccent : Colors.grey,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
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
                   border: Border.all(color: isDark ? Colors.white10 : Colors.transparent),
                 ),
                 child: Row(
                   children: [
                     Icon(Icons.link, color: isDark ? Colors.white54 : Colors.black45, size: 20),
                     const SizedBox(width: 16),
                     Expanded(
                       child: Column(
                         crossAxisAlignment: CrossAxisAlignment.start,
                         children: [
                           Text(
                             "LINKED TO",
                             style: TextStyle(color: isDark ? Colors.white38 : Colors.grey.shade600, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                           ),
                           const SizedBox(height: 2),
                           Text(
                             _companionName ?? widget.userData['companionName'] ?? 'Unknown',
                             style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 18, fontWeight: FontWeight.bold),
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
                      onPressed: (_isLoading || _activeSessionData != null) ? null : _unlinkCompanion,
                      icon: _isLoading 
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Icon(Icons.link_off, size: 18, color: (_activeSessionData != null) ? Colors.grey : Colors.redAccent), 
                      label: Text(
                         _activeSessionData != null ? "Session Active" : (_isLoading ? "Processing..." : "Unlink Companion"),
                         style: TextStyle(color: (_activeSessionData != null) ? Colors.grey : Colors.redAccent, fontWeight: FontWeight.bold),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: (_activeSessionData != null) ? Colors.white10 : Colors.redAccent.withOpacity(0.3)),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                   ),
                 )
               else
                 // Parent Mode Info
                 Container(
                   width: double.infinity,
                   padding: const EdgeInsets.all(16),
                   decoration: BoxDecoration(
                     color: Colors.orange.withOpacity(0.1),
                     borderRadius: BorderRadius.circular(16),
                     border: Border.all(color: Colors.orange.withOpacity(0.3)),
                   ),
                   child: Row(
                     children: [
                       const Icon(Icons.security, color: Colors.orange, size: 20),
                       const SizedBox(width: 12),
                       Expanded(
                         child: Text(
                           "Parental Control Active. Unlinking is restricted.",
                           style: TextStyle(color: isDark ? Colors.orangeAccent : Colors.orange.shade800, fontSize: 13, fontWeight: FontWeight.w500),
                         ),
                       ),
                     ],
                   ),
                 ),
            ] else ...[
              Text("Link a companion to unlock powerful accountability features.", 
                style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 13, height: 1.5)
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
                          border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade300),
                        ),
                        child: TextField(
                          controller: _companionCodeController,
                          style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16),
                          decoration: InputDecoration(
                            hintText: "Enter Link Code",
                            hintStyle: TextStyle(color: isDark ? Colors.white30 : Colors.black38),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                   ),
                   const SizedBox(width: 12),
                   Container(
                     decoration: BoxDecoration(
                       boxShadow: [
                         BoxShadow(color: Colors.cyan.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4))
                       ]
                     ),
                     child: ElevatedButton(
                        onPressed: _isLoading ? null : _linkCompanion,
                         style: ElevatedButton.styleFrom(
                           backgroundColor: Colors.cyanAccent,
                           foregroundColor: Colors.black87, 
                           padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                           elevation: 0,
                         ),
                        child: _isLoading 
                           ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                           : const Icon(Icons.arrow_forward, color: Colors.black87),
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
