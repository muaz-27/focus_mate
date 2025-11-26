import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For MethodChannel

import '../core/auth_service.dart';
import '../core/usage_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'analytics_screen.dart';
import 'app_lock_screen.dart';
import 'focus_session_screen.dart';

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

class _StudentDashboardState extends State<StudentDashboard> with WidgetsBindingObserver {
  bool showModeSelector = false;
  final TextEditingController _companionCodeController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final UsageService _usageService = UsageService(); 
  late bool companionActive;

  // 🔹 NATIVE CHANNEL
  static const platform = MethodChannel('com.example.focus_mate/blocker');

  Timer? _syncTimer;
  List<String> _blockedList = [];
  DateTime? _lockEndTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    companionActive = widget.companionActive;
    
    _syncUsageData();
    
    // 🚀 Start Syncing Rules to Native Service
    _startRuleSync();

    // 🔹 FIX: Fetch Companion Name if we have an ID but no name (e.g., after restart)
    if (companionActive) {
      _getCompanionDetails();
    }
  }

  // 🔹 NEW HELPER: Fetch real name from ID
  Future<void> _getCompanionDetails() async {
    // If name is already there, skip
    if (widget.userData['companionName'] != null) return;

    String? companionId = widget.userData['linkedCompanion'];
    if (companionId != null) {
      try {
        DocumentSnapshot doc = await _firestore.collection('users').doc(companionId).get();
        if (doc.exists) {
          setState(() {
            widget.userData['companionName'] = doc['name']; 
          });
        }
      } catch (e) {
        // Silent error
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------
  // 🔹 RULE SYNCHRONIZER (Sends List to Kotlin)
  // ---------------------------------------------------------
  void _startRuleSync() {
    // Sync rules every 5 seconds (Low battery usage)
    _syncTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      await _fetchLockRules();

      try {
        // If Timer is Active, send the Blocked List
        if (_lockEndTime != null && DateTime.now().isBefore(_lockEndTime!)) {
           // Send "Real" blocked list
           await platform.invokeMethod('setBlockedApps', {'apps': _blockedList});
        } else {
           // Send "Empty" list (Unlock everything)
           await platform.invokeMethod('setBlockedApps', {'apps': <String>[]});
        }
      } catch (e) {
        print("⚠️ Failed to talk to Native Service: $e");
      }
    });
  }

  Future<void> _fetchLockRules() async {
    try {
      final doc = await _firestore.collection('users').doc(widget.userData['id']).get();
      if (doc.exists) {
        final data = doc.data()!;
        _blockedList = List<String>.from(data['lockedApps'] ?? []);
        
        if (data['lockEndTime'] != null) {
          _lockEndTime = (data['lockEndTime'] as Timestamp).toDate();
        } else {
          _lockEndTime = null;
        }
      }
    } catch (e) {}
  }

  Future<void> _syncUsageData() async {
    if (widget.userData['id'] != null) {
      await _usageService.syncUsageToFirebase(widget.userData['id']);
    }
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
            onPressed: () => AuthService.signOut(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Quick Action Tiles
            Row(
              children: [
                Expanded(
                  child: _buildTile(
                    "Study Workspace",
                    widget.activeSession ? "Session Active" : "Start Studying",
                    AppColors.roleGradients['user']!,
                    () => setState(() => showModeSelector = true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTile(
                    "Study-Pass",
                    "Unlock Apps",
                    AppColors.roleGradients['user']!,
                    () {},
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
                    () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AppLockScreen(userId: widget.userData['id']),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTile(
                    "Analytics",
                    "Track Progress",
                    AppColors.roleGradients['user']!,
                    () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AnalyticsScreen(
                            userId: widget.userData['id'],
                            userName: widget.userData['name'] ?? "My",
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Daily Focus Card
            Container(
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
                      Text("${widget.studyTime}m / ${widget.dailyGoal}m", style: const TextStyle(color: Colors.cyanAccent)),
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
                        : "🎉 Goal achieved! Keep up the momentum!",
                    style: TextStyle(color: remaining > 0 ? Colors.grey.shade300 : Colors.greenAccent),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Companion Card
            GestureDetector(
              onTap: () {},
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: companionActive
                      ? const LinearGradient(colors: [Color(0xFF4F46E5), Color(0xFF3B82F6)])
                      : const LinearGradient(colors: [Color(0xFF1F2937), Color(0xFF374151)]),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: companionActive
                      ? [BoxShadow(color: Colors.blueAccent.withOpacity(0.5), blurRadius: 12, offset: const Offset(0, 4))]
                      : [],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.group, color: companionActive ? Colors.white : Colors.grey, size: 28),
                        const SizedBox(width: 12),
                        const Text("Companion Mode", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        if (companionActive)
                          Container(width: 12, height: 12, decoration: BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      companionActive ? "Connected to ${widget.userData['companionName'] ?? 'Unknown'}" : "No active companion",
                      style: TextStyle(color: Colors.grey.shade200),
                    ),
                    const SizedBox(height: 12),
                    if (!companionActive)
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _companionCodeController,
                              decoration: InputDecoration(
                                hintText: "Enter Companion Code",
                                filled: true,
                                fillColor: Colors.white12,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () async {
                              final code = _companionCodeController.text.trim();
                              if (code.isEmpty) return;
                              final query = await _firestore.collection('users').where('linkCode', isEqualTo: code).limit(1).get();
                              if (query.docs.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid code")));
                                return;
                              }
                              final companionDoc = query.docs.first;
                              await _firestore.collection('users').doc(widget.userData['id']).update({'linkedCompanion': companionDoc.id});
                              await _firestore.collection('users').doc(companionDoc.id).update({
                                'linkedStudents': FieldValue.arrayUnion([widget.userData['id']]),
                              });
                              setState(() {
                                companionActive = true;
                                widget.userData['companionName'] = companionDoc.data()['name'];
                              });
                            },
                            child: const Text("Link"),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            // Mode Selector
            if (showModeSelector)
              AlertDialog(
                title: const Text("Select Session Mode"),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        setState(() => showModeSelector = false);
                        Navigator.push(context, MaterialPageRoute(builder: (context) => FocusSessionScreen(userId: widget.userData['id'], mode: "Focused", durationMinutes: 45)));
                      },
                      child: const Text("Focused Mode"),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        setState(() => showModeSelector = false);
                        Navigator.push(context, MaterialPageRoute(builder: (context) => FocusSessionScreen(userId: widget.userData['id'], mode: "Pomodoro", durationMinutes: 25)));
                      },
                      child: const Text("Pomodoro Mode"),
                    ),
                  ],
                ),
                actions: [TextButton(onPressed: () => setState(() => showModeSelector = false), child: const Text("Cancel"))],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTile(String title, String subtitle, List<Color> gradient, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: AppTheme.cardContainer(gradient),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}