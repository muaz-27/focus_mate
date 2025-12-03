import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:usage_stats/usage_stats.dart';

import '../core/auth_service.dart';
import '../core/usage_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'analytics_screen.dart';
import 'app_lock_screen.dart';
import 'focus_session_screen.dart';
import 'session_setup_screen.dart';
import 'study_pass_screen.dart';
import 'study_workspace_screen.dart';
import '../core/permission_manager.dart';

class StudentDashboard extends StatefulWidget {
  final Map<String, dynamic> userData;
  final int studyTime;
  final int dailyGoal;
  final bool activeSession;
  final bool companionActive;
  final bool appsUnlocked;
  final Function onLogout;
  final Function(String) onStartSession;

  const StudentDashboard({
    super.key,
    required this.userData,
    required this.studyTime,
    required this.dailyGoal,
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
  DateTime? _lockEndTime;
  List<String> _blockedList = [];
  bool companionActive = false;
  final TextEditingController _companionCodeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    
    // Initialize companion state from passed user data
    if (widget.userData['linkedCompanion'] != null) {
      companionActive = true;
    }

    _startRuleSync();
    _getCompanionDetails();

    // Sync usage data in background
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _usageService.syncUsageToFirebase(widget.userData['id']);
    });
  }

  @override
  void dispose() {
    _ruleSyncTimer?.cancel();
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
    String? companionId = widget.userData['linkedCompanion'];
    if (companionId == null) return;

    // If we already have the name, just ensure active state is true
    if (widget.userData['companionName'] != null) {
      if (mounted) setState(() => companionActive = true);
      return;
    }

    try {
      DocumentSnapshot doc = await _firestore
          .collection('users')
          .doc(companionId)
          .get();
      if (doc.exists) {
        if (mounted) {
          setState(() {
            widget.userData['companionName'] = doc['name'];
            companionActive = true;
          });
        }
      }
    } catch (e) {}
  }

  Future<void> _unlinkCompanion() async {
    bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Unlink Companion?"),
        content: const Text("They will no longer see your stats."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Unlink", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    String? companionId = widget.userData['linkedCompanion'];
    if (companionId == null) return;

    try {
      await _firestore.collection('users').doc(widget.userData['id']).update({
        'linkedCompanion': null,
      });
      await _firestore.collection('users').doc(companionId).update({
        'linkedStudents': FieldValue.arrayRemove([widget.userData['id']]),
      });

      setState(() {
        companionActive = false;
        widget.userData['linkedCompanion'] = null;
        widget.userData['companionName'] = null;
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _linkCompanion() async {
    final code = _companionCodeController.text.trim();
    if (code.isEmpty) return;

    final query = await _firestore
        .collection('users')
        .where('linkCode', isEqualTo: code)
        .limit(1)
        .get();
    if (query.docs.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Invalid code")));
      return;
    }

    final companionDoc = query.docs.first;
    await _firestore.collection('users').doc(widget.userData['id']).update({
      'linkedCompanion': companionDoc.id,
    });
    await _firestore.collection('users').doc(companionDoc.id).update({
      'linkedStudents': FieldValue.arrayUnion([widget.userData['id']]),
    });

    setState(() {
      companionActive = true;
      widget.userData['companionName'] = companionDoc.data()['name'];
    });
  }

  @override
  Widget build(BuildContext context) {
    final progress = (widget.studyTime / widget.dailyGoal).clamp(0.0, 1.0);
    final remaining = widget.dailyGoal - widget.studyTime;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.cardOverlay,
        title: Text("Hi, ${widget.userData['name']}"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            onPressed: () => AuthService().signOut(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildQuickTiles(),
            const SizedBox(height: 16),
            _buildDailyFocusCard(progress, remaining),
            const SizedBox(height: 16),

            // This card shows your companion status
            _buildCompanionCard(),


          ],
        ),
      ),
    );
  }

  Widget _buildCompanionCard() {
    return GestureDetector(
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: companionActive
              ? const LinearGradient(
                  colors: [Color(0xFF4F46E5), Color(0xFF3B82F6)],
                )
              : const LinearGradient(
                  colors: [Color(0xFF1F2937), Color(0xFF374151)],
                ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: companionActive
              ? [
                  BoxShadow(
                    color: Colors.blueAccent.withValues(alpha: 0.5),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              children: [
                Icon(
                  Icons.group,
                  color: companionActive ? Colors.white : Colors.grey,
                  size: 28,
                ),
                const SizedBox(width: 12),
                const Text(
                  "Companion Mode",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),

                // Status Dot
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: companionActive ? Colors.greenAccent : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Connection Status Text
            Text(
              companionActive
                  ? "Connected to ${widget.userData['companionName'] ?? 'Unknown'}"
                  : "No active companion",
              style: TextStyle(color: Colors.grey.shade200),
            ),

            // Button to unlink the companion if one is connected
            if (companionActive)
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _unlinkCompanion,
                    icon: const Icon(Icons.link_off, color: Colors.white),
                    label: const Text(
                      "Unlink Companion",
                      style: TextStyle(color: Colors.white),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white30),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),

            // Input field to enter a code if no companion is connected
            if (!companionActive)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _companionCodeController,
                        decoration: InputDecoration(
                          hintText: "Enter Companion Code",
                          filled: true,
                          fillColor: Colors.white12,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _linkCompanion,
                      child: const Text("Link"),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyFocusCard(double progress, int remaining) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardOverlay,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.track_changes, color: Colors.cyanAccent),
                  SizedBox(width: 8),
                  Text("Daily Focus", style: TextStyle(color: Colors.white)),
                ],
              ),
              Text(
                "${widget.studyTime}m / ${widget.dailyGoal}m",
                style: const TextStyle(color: Colors.cyanAccent),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.grey.shade800,
            valueColor: const AlwaysStoppedAnimation(Colors.cyanAccent),
            minHeight: 8,
          ),
          const SizedBox(height: 6),
          Text(
            remaining > 0
                ? "You're $remaining mins away from hitting today's goal 🎯"
                : "🎉 Goal achieved!",
            style: TextStyle(
              color: remaining > 0 ? Colors.grey.shade300 : Colors.greenAccent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickTiles() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildTile(
                "Start Session",
                "Timer & Focus",
                AppColors.roleGradients['user']!,
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SessionSetupScreen(
                        userId: widget.userData['id'],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTile(
                "Study Workspace",
                "PDFs & Quizzes",
                AppColors.roleGradients['user']!,
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StudyWorkspaceScreen(
                        userId: widget.userData['id'],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildTile(
                "App Lock",
                widget.appsUnlocked ? "Unlocked" : "Manage Locks",
                AppColors.roleGradients['user']!,
                () async {
                  if (await PermissionManager.checkAccessibility(context)) {
                    if (context.mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              AppLockScreen(userId: widget.userData['id']),
                        ),
                      );
                    }
                  }
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTile(
                "Analytics",
                "Track Progress",
                AppColors.roleGradients['user']!,
                () async {
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
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildTile(
                "Battery Optimization",
                "Prevent App Killing",
                AppColors.roleGradients['user']!,
                () async {
                  await PermissionManager.checkBatteryOptimizations(context);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }



  Widget _buildTile(
    String title,
    String subtitle,
    List<Color> gradient,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: AppTheme.cardContainer(gradient),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: AppColors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
