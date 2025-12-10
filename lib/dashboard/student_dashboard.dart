// student_dashboard.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/auth_service.dart';
import '../core/permission_manager.dart';
import '../core/usage_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import './analytics_screen.dart';
import './app_lock_screen.dart';
import './app_lock_mode_selection.dart';
import './session_setup_screen.dart';
import './study_workspace_screen.dart';
import './companion_controlled_page.dart';
import './waiting_for_companion_page.dart';
import '../core/widgets/custom_dialog.dart';

// ==========================================
// 1. LOADER (Entry Point) - ADD THIS BACK
// ==========================================
import 'package:focus_mate/main.dart'; 

class StudentDashboardLoader extends StatelessWidget {
  const StudentDashboardLoader({super.key});

  @override
  Widget build(BuildContext context) {
    // We get the ID here just to start the stream, but we'll re-check auth inside
    final initialUser = FirebaseAuth.instance.currentUser;

    if (initialUser == null) {
      // FORCE NAVIGATION TO AUTH GATE (Login)
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
        // 1. Critical Check: Is user still logged in?
        // We check this DYNAMICALLY here to handle the logout race condition.
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser == null) {
           // FORCE NAVIGATION TO AUTH GATE (Login)
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
          // If error implies permission issues, check auth again just in case
          if (FirebaseAuth.instance.currentUser == null) {
             // FORCE NAVIGATION TO AUTH GATE (Login)
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

// ==========================================
// 2. MAIN DASHBOARD (YOUR ORIGINAL VERSION)
// ==========================================
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
  static const platform = MethodChannel('com.example.focus_mate/blocker');

  Timer? _ruleSyncTimer;
  Timer? _usageSyncTimer; // Timer for usage stats
  DateTime? _lockEndTime;
  List<String> _blockedList = [];
  bool companionActive = false;
  String? _companionName; // New local state
  int? _dailyGoal; // Local state for optimistic updates
  int? _localStudyTime; // Local state for immediate usage display
  bool _isLoading = false; 
  bool _isRefreshingUsage = false;
  final TextEditingController _companionCodeController =
      TextEditingController();
  
  // New state variable for active session re-entry
  Map<String, dynamic>? _activeSessionData;
  StreamSubscription? _activeSessionSubscription;

  @override
  void initState() {
    super.initState();

    // Initialize companion state from passed user data
    if (widget.userData['linkedCompanion'] != null) {
      companionActive = true;
      _companionName = widget.userData['companionName']; // Init from props if avail
    }
    _dailyGoal = widget.dailyGoal; // Init daily goal
    _localStudyTime = widget.studyTime; // Init usage
    _refreshUsageStats(); // Fetch fresh immediately on load

    _startRuleSync();
    _getCompanionDetails();
    _checkActiveSession(); // Check for existing active session

    // Sync usage data in background
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _usageService.syncUsageToFirebase(widget.userData['id']);
      _usageService.syncInstalledAppsToFirebase(widget.userData['id']);
    });

    // POLLING: Sync usage stats every 1 minute to keep UI fresh
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
        } else {
             // If we just got linked via stream (e.g. approved), we might need name
             // but if we did it locally, we might already have it.
             // _getCompanionDetails will handle fetching if missing.
        }
      });
      _getCompanionDetails();
    }
    
    // Sync daily goal if it changed from upstream
    if (widget.dailyGoal != oldWidget.dailyGoal) {
       setState(() {
         _dailyGoal = widget.dailyGoal;
       });
    }

    if (widget.studyTime != oldWidget.studyTime) {
       // Only update if we aren't currently refreshing manually to avoiding jumping
       if (!_isRefreshingUsage) {
          setState(() => _localStudyTime = widget.studyTime);
       }
    }
  }
  
  void _checkActiveSession() {
    _activeSessionSubscription = _firestore
        .collection('companion_sessions')
        .where('userId', isEqualTo: widget.userData['id'])
        .where('status', whereIn: ['ACTIVE', 'REQUESTED'])
        //.orderBy('createdAt', descending: true) // optimization: implies index
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        // Filter locally if needed or just take the first one
        // Since we want the *latest* relevant one, and we can't easily orderBy with whereIn without index
        // We can sort them in memory if strictly needed, but limit(1) might give arbitrary one.
        
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
    _companionCodeController.dispose();
    super.dispose();
  }

  void _startRuleSync() {
    _ruleSyncTimer?.cancel();
    _ruleSyncTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      await _fetchLockRules();
      try {
        final appsToSend =
            (_lockEndTime != null && DateTime.now().isBefore(_lockEndTime!))
            ? _blockedList
            : <String>[];
        await platform.invokeMethod('setBlockedApps', {'apps': appsToSend});
      } catch (e) {}
    });
  }

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
      print("Error fetching lock rules: $e");
    }
  }

  Future<void> _getCompanionDetails() async {
    if (_companionName != null) return; // Use local state check
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
              _companionName = doc['name']; // Update local state
              companionActive = true;
            });
          }
        }
      } catch (e) {}
    }
  }

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

    String? companionId = widget.userData['linkedCompanion'];
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
          // Do NOT mutate widget.userData anymore
          _companionName = null;
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
      batch.update(userRef, {'linkedCompanion': companionDoc.id});
      
      final companionRef = _firestore.collection('users').doc(companionDoc.id);
      batch.update(companionRef, {
        'linkedStudents': FieldValue.arrayUnion([widget.userData['id']]),
      });

      await batch.commit();

      if (mounted) {
        setState(() {
          companionActive = true;
          _companionName = companionDoc.data()['name'];
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
    // Progress calculation
    final currentUsage = _localStudyTime ?? widget.studyTime;
    final hasGoal = _dailyGoal != null;
    final progress = hasGoal ? (currentUsage / _dailyGoal!).clamp(0.0, 1.0) : 0.0;
    final remaining = hasGoal ? (_dailyGoal! - currentUsage) : 0;
    
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white70 : Colors.black54; // Lighter subtitle

    return Scaffold(
      extendBodyBehindAppBar: true, 
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark 
              ? [const Color(0xFF1A1F35), const Color(0xFF0B0E17)] // Deep Navy / Space Gray
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
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), // Increased padding
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_activeSessionData != null) ...[
                        _buildActiveSessionBanner(),
                        const SizedBox(height: 24),
                      ],
                      _buildDailyFocusHero(progress, remaining, isDark),
                      const SizedBox(height: 32), // More whitespace
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
                      const SizedBox(height: 48), // Bottom padding
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
                ? [const Color(0xFFEF4444), const Color(0xFFDC2626)] // Red 500, Red 600
                : [const Color(0xFFF59E0B), const Color(0xFFD97706)], // Amber 500, Amber 600
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

  Future<void> _editDailyGoal() async {
    // 1. Ensure we can even track usage before setting a goal
    bool hasPermission = await PermissionManager.checkUsageStats(context);
    if (!hasPermission) return;

    if (!mounted) return;

    // 2. Show Dialog
    int? currentGoal = _dailyGoal;
    int selectedGoal = currentGoal ?? 60; // Default to 60m if unset

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
                     max: 480, // 8 hours max
                     divisions: 31, // 15 min steps
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
          // Optimistic Update
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
            // Revert on error
            if (mounted) {
               setState(() => _dailyGoal = widget.dailyGoal);
               ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
            }
          }
       }
    });
  }

  Future<void> _refreshUsageStats() async {
    if (_isRefreshingUsage) return;
    setState(() => _isRefreshingUsage = true);

    try {
      // 1. Get local stats immediately
      final minutes = await _usageService.getTodayUsageMinutes();
      if (mounted) {
        setState(() {
          _localStudyTime = minutes;
        });
      }
      
      // 2. Sync to cloud in background
      _usageService.syncUsageToFirebase(widget.userData['id']);

    } catch (e) {
      print("Error refreshing usage: $e");
    } finally {
       if (mounted) setState(() => _isRefreshingUsage = false);
    }
  }

  Widget _buildDailyFocusHero(double progress, int remaining, bool isDark) {
    final displayTime = _localStudyTime ?? widget.studyTime;
    if (_dailyGoal == null) {
      // EMPTY STATE: No Goal Set
      return Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark 
              ? [const Color(0xFF1E293B), const Color(0xFF0F172A)] 
              : [Colors.white, Colors.grey.shade50],
          ),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 10)),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text("DAILY USAGE", style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 12)),
                    const SizedBox(width: 8),
                    if (_isRefreshingUsage) 
                      const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent))
                    else
                      InkWell(
                        onTap: _refreshUsageStats,
                        child: Icon(Icons.refresh, size: 14, color: Colors.cyanAccent.withOpacity(0.7)),
                      )
                  ],
                ),
                const SizedBox(height: 8),
                Text(_formatMinutes(displayTime), style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 36, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text("No limit set", style: TextStyle(color: isDark ? Colors.white54 : Colors.grey)),
              ],
            ),
            ElevatedButton(
              onPressed: _editDailyGoal,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent.withOpacity(0.2),
                foregroundColor: Colors.cyanAccent,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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

    return Container(
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
            crossAxisAlignment: CrossAxisAlignment.start,
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
                              color: isDark ? Colors.white : Colors.black87, 
                              fontSize: 36, 
                              fontWeight: FontWeight.bold,
                              height: 1.0,
                            )
                          ),
                          TextSpan(
                            text: " / ${_formatMinutes(_dailyGoal!)}", 
                            style: TextStyle(
                              color: isDark ? Colors.white54 : Colors.black45, 
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
              )
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionGrid(bool isDark) {
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
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AppLockModeSelection(
                        userId: widget.userData['id'],
                        companionId: widget.userData['linkedCompanion'],
                        companionName: widget.userData['companionName'],
                      ),
                    ),
                  );
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
        // Removed fixed height to prevent overflow
        constraints: const BoxConstraints(minHeight: 110), 
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark 
               ? [Colors.white.withOpacity(0.07), Colors.white.withOpacity(0.03)]
               : [Colors.white, Colors.white.withOpacity(0.9)],
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
            const SizedBox(height: 16), // Add spacing instead of spaceBetween if needed
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
                    color: companionActive ? Colors.cyan.withOpacity(0.2) : (isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.group, color: companionActive ? Colors.cyanAccent : (isDark ? Colors.white70 : Colors.black54), size: 28),
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
                      // backgroundColor: Colors.redAccent.withOpacity(0.05),
                    ),
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
                           foregroundColor: Colors.black87, // Dark text on bright button
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
