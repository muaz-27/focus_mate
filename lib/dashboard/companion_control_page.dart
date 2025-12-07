import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'package:focus_mate/core/usage_service.dart';
import 'package:focus_mate/theme/app_colors.dart';
import 'dart:typed_data';

class CompanionControlPage extends StatefulWidget {
  final String sessionId;
  final String companionId;

  const CompanionControlPage({
    super.key,
    required this.sessionId,
    required this.companionId,
  });

  @override
  State<CompanionControlPage> createState() => _CompanionControlPageState();
}

class _CompanionControlPageState extends State<CompanionControlPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final UsageService _usageService = UsageService();
  late StreamSubscription _sessionSubscription;
  Map<String, dynamic> _sessionData = {};
  List<AppInfo> _installedApps = [];
  List<String> _selectedApps = [];
  List<String> _lockedApps = [];
  bool _isLoading = true;
  Timer? _timer;
  String _timeLeft = "";

  @override
  void initState() {
    super.initState();
    _loadData();
    _listenToSession();
  }

  @override
  void dispose() {
    _sessionSubscription.cancel();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      // Get student's installed apps
      final apps = await _usageService.getInstalledAppsList();
      
      // Get session data
      final sessionDoc = await _firestore
          .collection('companion_sessions')
          .doc(widget.sessionId)
          .get();
      
      if (sessionDoc.exists) {
        setState(() {
          _sessionData = sessionDoc.data()!;
          _installedApps = apps.where((app) => app.packageName != 'com.example.focus_mate').toList();
          _installedApps.sort((a, b) => (a.name ?? "").compareTo(b.name ?? ""));
          _lockedApps = List<String>.from(_sessionData['lockedApps'] ?? []);
          _selectedApps = List.from(_lockedApps); // Pre-select already locked apps
          _isLoading = false;
        });
        _updateTimeLeft();
        _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTimeLeft());
      }
    } catch (e) {
      print("Error loading data: $e");
    }
  }

  void _listenToSession() {
    _sessionSubscription = _firestore
        .collection('companion_sessions')
        .doc(widget.sessionId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists) {
        final data = snapshot.data()!;
        setState(() {
          _sessionData = data;
          _lockedApps = List<String>.from(data['lockedApps'] ?? []);
          // Update selected apps to match locked apps
          _selectedApps = List.from(_lockedApps);
        });
        
        // Check for emergency requests
        if (data['emergencyRequested'] == true) {
          _showEmergencyRequestDialog(data);
        }
      }
    });
  }

  void _showEmergencyRequestDialog(Map<String, dynamic> sessionData) {
    final emergencyApp = sessionData['emergencyApp'] ?? '';
    final isGlobalExit = emergencyApp == 'ALL_APPS';
    final appName = isGlobalExit ? 'ALL APPS (Global Exit)' : _getAppName(emergencyApp);
    final reason = sessionData['emergencyReason'] ?? '';
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardOverlay,
        title: Text(
          isGlobalExit ? "🚨 EMERGENCY EXIT REQUEST" : "🚨 Emergency Unlock Request",
          style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Student: ${sessionData['userName']}",
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 10),
            Text(
              isGlobalExit ? "Requesting to END SESSION immediately." : "App: $appName",
              style: TextStyle(
                color: Colors.white, 
                fontWeight: isGlobalExit ? FontWeight.bold : FontWeight.normal
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "Reason: $reason",
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => _respondToEmergency(false),
            child: const Text("Deny", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => _respondToEmergency(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: isGlobalExit ? Colors.red : Colors.blueAccent
            ),
            child: Text(isGlobalExit ? "End Session" : "Allow"),
          ),
        ],
      ),
    );
  }

  Future<void> _respondToEmergency(bool allow) async {
    Navigator.pop(context); // Close dialog first
    
    if (allow) {
      final app = _sessionData['emergencyApp'];
      if (app == 'ALL_APPS') {
         // Handle Global Exit -> End Session
         await _endSession(confirmed: true);
         return;
      }
      
      // Unlock specific app
      await _unlockSpecificApp(app);
    } 

    await _firestore
        .collection('companion_sessions')
        .doc(widget.sessionId)
        .update({
          'emergencyRequested': false,
          'emergencyResponded': allow,
          'emergencyRespondedAt': FieldValue.serverTimestamp(),
        });
  }

  Future<void> _unlockSpecificApp(String packageName) async {
    await _firestore
        .collection('companion_sessions')
        .doc(widget.sessionId)
        .update({
          'manuallyUnlockedApps': FieldValue.arrayUnion([packageName]),
        });
    
    // Also update student's locked apps
    final userId = _sessionData['userId'];
    final userDoc = await _firestore.collection('users').doc(userId).get();
    final currentLocked = List<String>.from(userDoc['lockedApps'] ?? []);
    currentLocked.remove(packageName);
    
    await _firestore.collection('users').doc(userId).update({
      'lockedApps': currentLocked,
    });
  }

  void _updateTimeLeft() {
    final startedAt = _sessionData['startedAt']?.toDate();
    final duration = Duration(minutes: _sessionData['duration'] ?? 60);
    
    if (startedAt != null) {
      final endTime = startedAt.add(duration);
      final now = DateTime.now();
      
      if (now.isAfter(endTime)) {
        setState(() => _timeLeft = "Session ended");
        return;
      }
      
      final diff = endTime.difference(now);
      setState(() {
        _timeLeft =
            "${diff.inHours.toString().padLeft(2, '0')}:${(diff.inMinutes % 60).toString().padLeft(2, '0')}:${(diff.inSeconds % 60).toString().padLeft(2, '0')}";
      });
    }
  }

  void _toggleAppSelection(String packageName) {
    setState(() {
      if (_selectedApps.contains(packageName)) {
        _selectedApps.remove(packageName);
      } else {
        _selectedApps.add(packageName);
      }
    });
  }

  Future<void> _applyLocks() async {
    if (_selectedApps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Select at least one app to lock")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final userId = _sessionData['userId'];
      
      // Update companion session
      await _firestore
          .collection('companion_sessions')
          .doc(widget.sessionId)
          .update({
            'status': 'ACTIVE',
            'startedAt': FieldValue.serverTimestamp(),
            'lockedApps': _selectedApps,
            'updatedAt': FieldValue.serverTimestamp(),
          });
      
      // Update student's locked apps
      await _firestore.collection('users').doc(userId).update({
        'lockedApps': _selectedApps,
        'lockEndTime': null, // Clear any existing timer
      });
      
      setState(() {
        _lockedApps = List.from(_selectedApps);
        _isLoading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${_selectedApps.length} apps locked for student")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
      setState(() => _isLoading = false);
    }
  }

  Future<void> _endSession({bool confirmed = false}) async {
    bool? confirm = confirmed;
    if (!confirmed) {
      confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardOverlay,
        title: const Text(
          "End Session?",
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          "This will unlock all apps for the student",
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
            child: const Text("End Session"),
          ),
        ],
      ),
    );
    }
    
    if (confirm == true) {
      await _firestore
          .collection('companion_sessions')
          .doc(widget.sessionId)
          .update({
            'status': 'ENDED',
            'endedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
      
      // Clear student's locked apps
      final userId = _sessionData['userId'];
      await _firestore.collection('users').doc(userId).update({
        'lockedApps': [],
        'lockEndTime': null,
      });
      
      Navigator.pop(context);
    }
  }

  String _getAppName(String packageName) {
    final appNames = {
      'com.instagram.android': 'Instagram',
      'com.facebook.katana': 'Facebook',
      'com.google.android.youtube': 'YouTube',
      'com.zhiliaoapp.musically': 'TikTok',
      'com.twitter.android': 'Twitter',
      'com.whatsapp': 'WhatsApp',
      'com.snapchat.android': 'Snapchat',
    };
    
    return appNames[packageName] ?? packageName.split('.').last;
  }

  @override
  Widget build(BuildContext context) {
    final studentName = _sessionData['userName'] ?? 'Student';
    final isActive = _sessionData['status'] == 'ACTIVE';
    
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text("Control - $studentName"),
        backgroundColor: AppColors.cardOverlay,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (isActive)
            IconButton(
              icon: const Icon(Icons.lock_open, color: Colors.red),
              onPressed: _endSession,
              tooltip: "End Session",
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))
          : Column(
              children: [
                // Session Info Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withOpacity(0.1),
                    border: Border(
                      bottom: BorderSide(color: Colors.blueAccent.withOpacity(0.3)),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            studentName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Chip(
                            label: Text(
                              isActive ? "ACTIVE" : "SETUP",
                              style: const TextStyle(color: Colors.white),
                            ),
                            backgroundColor: isActive ? Colors.green : Colors.orange,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _timeLeft,
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        isActive 
                            ? "${_lockedApps.length} apps locked"
                            : "Select apps to lock",
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                
                // Apps Selection Grid
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      childAspectRatio: 0.8,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: _installedApps.length,
                    itemBuilder: (context, index) {
                      final app = _installedApps[index];
                      final isSelected = _selectedApps.contains(app.packageName);
                      final isLocked = _lockedApps.contains(app.packageName);
                      
                      Uint8List? iconData = app.icon != null
                          ? Uint8List.fromList(app.icon!)
                          : null;
                      
                      return GestureDetector(
                        onTap: () => _toggleAppSelection(app.packageName),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isLocked 
                                ? Colors.red.withOpacity(0.2)
                                : isSelected
                                    ? Colors.blueAccent.withOpacity(0.2)
                                    : AppColors.cardOverlay,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isLocked
                                  ? Colors.redAccent
                                  : isSelected
                                      ? Colors.blueAccent
                                      : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // App Icon
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  color: Colors.black.withOpacity(0.3),
                                ),
                                child: iconData != null
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.memory(
                                          iconData,
                                          fit: BoxFit.cover,
                                        ),
                                      )
                                    : Center(
                                        child: Text(
                                          app.name?[0] ?? "?",
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                              ),
                              
                              // App Name
                              Padding(
                                padding: const EdgeInsets.all(4),
                                child: Text(
                                  app.name ?? "Unknown",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: isLocked 
                                        ? Colors.redAccent
                                        : Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              
                              // Status Indicator
                              if (isLocked)
                                const Icon(Icons.lock, color: Colors.red, size: 12)
                              else if (isSelected)
                                const Icon(Icons.check_circle, color: Colors.blueAccent, size: 12),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                
                // Control Buttons
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: isActive
                      ? Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _endSession,
                                icon: const Icon(Icons.lock_open),
                                label: const Text('End Session & Unlock All'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  padding: const EdgeInsets.symmetric(vertical: 15),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              "Student cannot unlock apps. You must end the session.",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                          ],
                        )
                      : SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _applyLocks,
                            icon: const Icon(Icons.lock),
                            label: Text(
                              'Lock ${_selectedApps.length} Selected Apps',
                              style: const TextStyle(fontSize: 16),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}