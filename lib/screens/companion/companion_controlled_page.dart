import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:focus_mate/theme/app_colors.dart';
import 'package:focus_mate/core/native_blocker.dart';
// 👇 IMPORTANT: Ensure this import points to your dashboard file
import 'package:focus_mate/screens/student/student_dashboard.dart'; 
import 'package:focus_mate/core/widgets/custom_dialog.dart'; 
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focus_mate/providers/companion_session_provider.dart';

class CompanionControlledPage extends ConsumerStatefulWidget {
  final String sessionId;
  final String userId;

  const CompanionControlledPage({
    super.key,
    required this.sessionId,
    required this.userId,
  });

  @override
  ConsumerState<CompanionControlledPage> createState() => _CompanionControlledPageState();
}

class _CompanionControlledPageState extends ConsumerState<CompanionControlledPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _reasonController = TextEditingController();
  
  Timer? _timer;
  Map<String, dynamic> _sessionData = {};
  List<String> _lockedApps = [];
  String _timeLeft = "--:--:--";
  
  bool _emergencyRequestPending = false;
  String? _emergencyApp; 

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTimeLeft());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _reasonController.dispose();
    super.dispose();
  }

  void _handleSessionEnded() {
    _timer?.cancel();
    NativeBlocker.setCompanionBlockedApps([]);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // We are automatically navigated away by DashboardRouter, this ensures any overlay is gone
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Session ended by companion")),
      );
    });
  }

  void _showEmergencyResponseDialog(bool? allowed) {
    if (!mounted) return;

    setState(() {
      _emergencyRequestPending = false;
      _emergencyApp = null;
    });

    showCustomDialog(
      context: context,
      barrierDismissible: false,
      title: allowed == true ? "✅ Approved" : "❌ Denied",
      titleColor: allowed == true ? Colors.green : Colors.red,
      content: Text(
        allowed == true
            ? "Your companion approved the unlock."
            : "Your companion denied the unlock.",
        style: const TextStyle(color: Colors.white),
      ),
      actions: [
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
            _firestore.collection('companion_sessions').doc(widget.sessionId).update({
              'emergencyResponded': null,
              'emergencyRequested': false,
              'emergencyApp': null,
            });
          },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
          child: const Text("OK", style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  bool _autoEndTriggered = false;

  void _updateTimeLeft() {
    if (_sessionData['startedAt'] == null) return;

    final startedAt = _sessionData['startedAt'].toDate();
    final duration = Duration(minutes: _sessionData['duration'] ?? 60);
    final endTime = startedAt.add(duration);
    final now = DateTime.now();
    
    if (now.isAfter(endTime)) {
      if (mounted && !_autoEndTriggered) {
        _autoEndTriggered = true;
        _autoEndSession();
      }
      return;
    }
    
    final diff = endTime.difference(now);
    if (mounted) {
      setState(() {
        _timeLeft =
            "${diff.inHours.toString().padLeft(2, '0')}:${(diff.inMinutes % 60).toString().padLeft(2, '0')}:${(diff.inSeconds % 60).toString().padLeft(2, '0')}";
      });
    }
  }

  /// Automatically ends the session when the timer expires.
  Future<void> _autoEndSession() async {
    try {
      await _firestore.collection('companion_sessions').doc(widget.sessionId).update({
        'status': 'ENDED',
        'endedAt': FieldValue.serverTimestamp(),
        'endReason': 'timer_expired',
      });
    } catch (e) {
      debugPrint("Error auto-ending session: $e");
    }
    // _handleSessionEnded() will be triggered by the Firestore listener
  }

  Future<void> _requestEmergencyUnlock(String appName) async {
    setState(() {
      _emergencyApp = appName;
    });

    await showCustomDialog(
      context: context,
      title: "Emergency Unlock",
      titleColor: Colors.orange,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            appName == "ALL_APPS"
                ? "Requesting Full Session Exit"
                : "App: ${appName.split('.').last}",
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _reasonController,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: "Why do you need this?",
              hintStyle: const TextStyle(color: Colors.grey),
              enabledBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: Colors.orange),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            style: const TextStyle(color: Colors.white),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            setState(() => _emergencyApp = null);
            _reasonController.clear();
          },
          child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: () async {
            if (_reasonController.text.isEmpty) return;

            final reason = _reasonController.text;
            _reasonController.clear();
            Navigator.pop(context);

            setState(() => _emergencyRequestPending = true);

            try {
              await _firestore
                  .collection('companion_sessions')
                  .doc(widget.sessionId)
                  .update({
                'emergencyRequested': true,
                'emergencyApp': appName,
                'emergencyReason': reason,
                'emergencyRequestedAt': FieldValue.serverTimestamp(),
              });
            } catch (e) {
              if (mounted) setState(() => _emergencyRequestPending = false);
            }
          },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
          child: const Text("Send", style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Future<void> _endSessionEarly() async {
    final confirm = await showCustomDialog<bool>(
      context: context,
      title: "End Session?",
      content: const Text(
        "Are you sure you want to terminate this session?",
        style: TextStyle(color: Colors.grey),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          child: const Text("Terminate", style: TextStyle(color: Colors.white)),
        ),
      ],
    );
    
    if (confirm == true && mounted) {
      await _firestore.collection('companion_sessions').doc(widget.sessionId).update({
        'status': 'ENDED',
        'endedAt': FieldValue.serverTimestamp(),
        'endedBy': 'student',
      });
      
      await _firestore.collection('users').doc(widget.userId).update({
        'lockedApps': [],
        'lockEndTime': null,
      });

      // Clear native locks
      await NativeBlocker.setCompanionBlockedApps([]);

      if (mounted) {
        // No explicit manual push here! DashboardRouter automatically pops/swaps.
      }
    }
  }

  String _getDisplayName(String packageName) {
    return packageName.split('.').last;
  }

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(activeCompanionSessionProvider);

    return sessionAsync.when(
      loading: () => const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: Colors.cyanAccent)),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: Text("Error: $e", style: const TextStyle(color: Colors.white))),
      ),
      data: (sessionData) {
        if (sessionData == null) {
          // Sync Native Locks empty if session dies
          WidgetsBinding.instance.addPostFrameCallback((_) {
            NativeBlocker.setCompanionBlockedApps([]);
            _handleSessionEnded();
          });
          return const Scaffold(backgroundColor: AppColors.background);
        }

        _sessionData = sessionData;
        _lockedApps = List<String>.from(sessionData['lockedApps'] ?? []);

        // Sync Native Locks outside of build via postFrameCallback
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) NativeBlocker.setCompanionBlockedApps(_lockedApps);
        });

        if (sessionData['emergencyResponded'] != null && _emergencyRequestPending) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showEmergencyResponseDialog(sessionData['emergencyResponded']);
          });
        }

        final companionName = _sessionData['companionName'] ?? 'Companion';
    
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Session Active", style: TextStyle(color: Colors.white)),
        backgroundColor: AppColors.cardOverlay,
        centerTitle: true,
        automaticallyImplyLeading: false, 
      ),
      body: Column(
        children: [
          // 1. Timer & Info
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withValues(alpha: 0.1),
              border: Border(bottom: BorderSide(color: Colors.blueAccent.withValues(alpha: 0.2))),
            ),
            child: Column(
              children: [
                Text(
                  _timeLeft,
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.security, size: 16, color: Colors.blueAccent),
                    const SizedBox(width: 8),
                    Text(
                      "Controlled by $companionName",
                      style: const TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 2. Pending Status
          if (_emergencyRequestPending)
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.orange.withValues(alpha: 0.2),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange)),
                  SizedBox(width: 10),
                  Text("Unlock request pending...", style: TextStyle(color: Colors.orange)),
                ],
              ),
            ),
          
          // 3. Locked Apps List
          Expanded(
            child: _lockedApps.isEmpty
                ? const Center(
                    child: Text(
                      "No apps currently locked",
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _lockedApps.length,
                    itemBuilder: (context, index) {
                      final app = _lockedApps[index];
                      final isThisAppLoading = _emergencyRequestPending && _emergencyApp == app;
                      
                      return Card(
                        color: AppColors.cardOverlay,
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: const Icon(Icons.lock, color: Colors.redAccent),
                          title: Text(_getDisplayName(app), style: const TextStyle(color: Colors.white)),
                          trailing: _emergencyRequestPending
                              ? (isThisAppLoading 
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.orange, strokeWidth: 2))
                                  : const Icon(Icons.lock_clock, color: Colors.grey))
                              : IconButton(
                                  icon: const Icon(Icons.key, color: Colors.orange),
                                  onPressed: () => _requestEmergencyUnlock(app),
                                ),
                        ),
                      );
                    },
                  ),
          ),

          // 4. BOTTOM ACTION BUTTONS
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardOverlay,
              border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    // BUTTON 1: Redirect to Dashboard (Leaves session running in background)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (context) => const StudentDashboardLoader()),
                          );
                        },
                        icon: const Icon(Icons.dashboard, color: Colors.white),
                        label: const Text("Dashboard", style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // BUTTON 2: Request Emergency Exit (requires companion approval)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _emergencyRequestPending ? null : () => _requestEmergencyUnlock("ALL_APPS"),
                        icon: const Icon(Icons.emergency, color: Colors.white),
                        label: Text(
                          _emergencyRequestPending ? "Pending..." : "Emergency Exit",
                          style: const TextStyle(color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          disabledBackgroundColor: Colors.redAccent.withValues(alpha: 0.4),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  "Your companion controls this session. Use Emergency Exit if needed.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    },
   );
  }
}