import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:focus_mate/core/usage_service.dart';
import 'package:focus_mate/theme/app_colors.dart';
import 'package:focus_mate/theme/app_theme.dart';
import 'dart:convert';
import 'package:focus_mate/core/widgets/custom_dialog.dart';
import 'package:focus_mate/core/widgets/app_icon_widget.dart';

/// Page for companions to restrict apps and manage active sessions for a student.
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

  List<Map<String, dynamic>> _installedApps = [];
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

  /// Loads session data and the student's installed apps.
  Future<void> _loadData() async {
    try {
      // Get session data
      final sessionDoc = await _firestore
          .collection('companion_sessions')
          .doc(widget.sessionId)
          .get();

      if (!sessionDoc.exists) return;

      _sessionData = sessionDoc.data()!;
      final studentId = _sessionData['userId'];

      // Get student's installed apps from Firestore
      // UPDATED: Now fetches from the 'data_v2' sharded subcollection
      final appsCollection = _firestore
          .collection('users')
          .doc(studentId)
          .collection('data_v2');

      final shardsSnapshot = await appsCollection.get();
      List<Map<String, dynamic>> apps = [];

      if (shardsSnapshot.docs.isNotEmpty) {
        // 1. New Sharded Data
        for (var doc in shardsSnapshot.docs) {
          if (doc.data().containsKey('installedApps')) {
            final shardApps = List<Map<String, dynamic>>.from(
              doc.data()['installedApps'],
            );
            apps.addAll(shardApps);
          }
        }
      } else {
        // 2. Fallback: Check 'data/installed_apps' (Previous version)
        DocumentSnapshot legacyDoc = await _firestore
            .collection('users')
            .doc(studentId)
            .collection('data')
            .doc('installed_apps')
            .get();

        if (legacyDoc.exists && legacyDoc.data() != null) {
          final data = legacyDoc.data() as Map<String, dynamic>;
          if (data.containsKey('installedApps')) {
            apps = List<Map<String, dynamic>>.from(data['installedApps']);
          }
        } else {
          // 3. Fallback: Check old location in user document (Oldest version)
          final userDoc = await _firestore
              .collection('users')
              .doc(studentId)
              .get();
          if (userDoc.exists && userDoc.data()!.containsKey('installedApps')) {
            apps = List<Map<String, dynamic>>.from(
              userDoc.data()!['installedApps'],
            );
          }
        }
      }

      // Get icons from app_icons collection
      final iconCollection = _firestore
          .collection('users')
          .doc(studentId)
          .collection('app_icons');
      final iconsSnapshot = await iconCollection.get();
      Map<String, String> iconMap = {};
      for (var doc in iconsSnapshot.docs) {
        if (doc.data().containsKey('icon')) {
          iconMap[doc.id] = doc.data()['icon'];
        }
      }

      if (mounted) {
        setState(() {
          // Blacklist of common system apps that typically don't need to be locked
          const ignoredPackages = [
            'android',
            'com.android.settings',
            'com.android.systemui',
            'com.android.vending',
            'com.google.android.gms',
            'com.google.android.googlequicksearchbox',
            'com.google.android.inputmethod.latin',
            'com.google.android.packageinstaller',
            'com.android.permissioncontroller',
            'com.google.android.apps.docs', // Drive (usually okay)
            'com.android.shell',
            'com.android.providers.calendar',
            'com.android.providers.contacts',
          ];

          // Filter out our own app and unnecessary system apps
          _installedApps = apps
              .where((app) {
                final pkg = app['packageName'] as String;
                if (pkg == 'com.example.focus_mate') return false;

                // Hide system apps that start with com.android or com.google.android.providers unless explicitly useful
                if (ignoredPackages.contains(pkg)) return false;
                if (pkg.startsWith('com.android.providers')) return false;
                if (pkg.contains('overlay')) return false;
                if (pkg.contains('service')) return false;

                return true;
              })
              .map((app) {
                final newApp = Map<String, dynamic>.from(app);
                final pkg = newApp['packageName'];
                final iconBase64 = iconMap[pkg] ?? newApp['iconBytes'];

                if (iconBase64 != null && iconBase64 is String) {
                  try {
                    newApp['decodedIcon'] = base64Decode(iconBase64);
                  } catch (e) {
                    debugPrint("Error decoding icon for $pkg: $e");
                  }
                }
                return newApp;
              })
              .toList();

          // Sort alphabetically
          _installedApps.sort(
            (a, b) => (a['appName'] as String).toLowerCase().compareTo(
              (b['appName'] as String).toLowerCase(),
            ),
          );

          _lockedApps = List<String>.from(_sessionData['lockedApps'] ?? []);
          _selectedApps = List.from(_lockedApps);
          _isLoading = false;
        });

        _updateTimeLeft();
        _timer = Timer.periodic(
          const Duration(seconds: 1),
          (_) => _updateTimeLeft(),
        );
      }
    } catch (e) {
      debugPrint("Error loading data: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Listens for session updates, including emergency requests or session prompts.
  void _listenToSession() {
    _sessionSubscription = _firestore
        .collection('companion_sessions')
        .doc(widget.sessionId)
        .snapshots()
        .listen((snapshot) {
          if (snapshot.exists) {
            final data = snapshot.data()!;

            // Check if session ended
            if (data['status'] == 'ENDED') {
              if (mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text("Session ended")));
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
              return;
            }

            if (mounted) {
              setState(() {
                _sessionData = data;
                _lockedApps = List<String>.from(data['lockedApps'] ?? []);
                _selectedApps = List.from(_lockedApps);
              });
            }

            // Check for emergency requests
            if (data['emergencyRequested'] == true && mounted) {
              _showEmergencyRequestDialog(data);
            }

            // Check for early quiz request
            if (data['earlyQuizRequest'] == true &&
                data['earlyAttemptApproved'] != true &&
                mounted) {
              _showEarlyQuizRequestDialog(data);
            }
          }
        });
  }

  void _showEarlyQuizRequestDialog(Map<String, dynamic> sessionData) {
    showCustomDialog(
      context: context,
      barrierDismissible: false,
      title: "📖 Early Quiz Request",
      titleColor: Colors.blueAccent,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Student: ${sessionData['userName']} is requesting to take the quiz early.",
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 10),
          const Text(
            "If approved, they can attempt the quiz now to unlock their apps.",
            style: TextStyle(color: Colors.white70),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () async {
            Navigator.pop(context);
            await _firestore
                .collection('companion_sessions')
                .doc(widget.sessionId)
                .update({
                  'earlyQuizRequest': false,
                  'updatedAt': FieldValue.serverTimestamp(),
                });
          },
          child: const Text("Deny", style: TextStyle(color: Colors.white70)),
        ),
        ElevatedButton(
          onPressed: () async {
            Navigator.pop(context);
            await _firestore
                .collection('companion_sessions')
                .doc(widget.sessionId)
                .update({
                  'earlyAttemptApproved': true,
                  'updatedAt': FieldValue.serverTimestamp(),
                });
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Early attempt approved.")),
              );
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blueAccent,
            foregroundColor: Colors.white,
          ),
          child: const Text("Approve"),
        ),
      ],
    );
  }

  void _showEmergencyRequestDialog(Map<String, dynamic> sessionData) {
    final emergencyApp = sessionData['emergencyApp'] ?? '';
    final isGlobalExit = emergencyApp == 'ALL_APPS';
    final appName = isGlobalExit
        ? 'ALL APPS (Global Exit)'
        : _getAppName(emergencyApp);
    final reason = sessionData['emergencyReason'] ?? '';

    showCustomDialog(
      context: context,
      barrierDismissible: false,
      title: isGlobalExit
          ? "🚨 EMERGENCY EXIT REQUEST"
          : "🚨 Emergency Unlock Request",
      titleColor: Colors.redAccent,
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
            isGlobalExit
                ? "Requesting to END SESSION immediately."
                : "App: $appName",
            style: TextStyle(
              color: Colors.white,
              fontWeight: isGlobalExit ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          const SizedBox(height: 10),
          Text("Reason: $reason", style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[400] : Colors.grey.shade600)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => _respondToEmergency(false),
          child: const Text("Deny", style: TextStyle(color: Colors.white70)),
        ),
        ElevatedButton(
          onPressed: () => _respondToEmergency(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: isGlobalExit ? Colors.red : Colors.blueAccent,
            foregroundColor: Colors.white,
          ),
          child: Text(isGlobalExit ? "End Session" : "Allow"),
        ),
      ],
    );
  }

  Future<void> _respondToEmergency(bool allow) async {
    Navigator.pop(context);

    if (allow) {
      final app = _sessionData['emergencyApp'];
      if (app == 'ALL_APPS') {
        await _endSession(confirmed: true);
        return;
      }

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

  /// Unlocks a specific app manually during an active session (e.g. emergency).
  Future<void> _unlockSpecificApp(String packageName) async {
    await _firestore
        .collection('companion_sessions')
        .doc(widget.sessionId)
        .update({
          'manuallyUnlockedApps': FieldValue.arrayUnion([packageName]),
        });

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
        if (mounted) setState(() => _timeLeft = "Session ended");
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

  /// Applies the selected locks to the student's device.
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
            'duration':
                _sessionData['duration'] ?? 60, // Ensure duration is saved
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
        SnackBar(
          content: Text("${_selectedApps.length} apps locked for student"),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
        setState(() => _isLoading = false);
      }
    }
  }

  /// Ends the current active session and unlocks all apps.
  Future<void> _endSession({bool confirmed = false}) async {
    bool? confirm = confirmed;
    if (!confirmed) {
      confirm = await showCustomDialog<bool>(
        context: context,
        title: "End Session?",
        content: const Text("This will unlock all apps for the student"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text("Cancel", style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[400] : Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("End Session"),
          ),
        ],
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

      if (mounted) Navigator.pop(context);
    }
  }

  String _getAppName(String packageName) {
    if (_installedApps.isNotEmpty) {
      final match = _installedApps.where(
        (a) => a['packageName'] == packageName,
      );
      if (match.isNotEmpty) return match.first['appName'] ?? packageName;
    }

    const appNames = {
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.grey.shade400 : Colors.black54;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          "Control - $studentName",
          style: TextStyle(color: textColor),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
        actions: [
          if (isActive)
            IconButton(
              icon: const Icon(Icons.lock_open, color: Colors.red),
              onPressed: _endSession,
              tooltip: "End Session",
            ),
        ],
      ),
      body: Container(
        decoration: AppTheme.screenBackground(
          context,
          AppColors.roleGradients['companion']!,
        ),
        child: SafeArea(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.cyanAccent),
                )
              : Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withValues(alpha: 0.1),
                        border: Border(
                          bottom: BorderSide(
                            color: Colors.blueAccent.withValues(alpha: 0.3),
                          ),
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                studentName,
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Chip(
                                label: Text(
                                  isActive ? "ACTIVE" : "SETUP",
                                  style: const TextStyle(color: Colors.white),
                                ),
                                backgroundColor: isActive
                                    ? Colors.green
                                    : Colors.orange,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (isActive)
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
                                : "Select apps to lock and duration",
                            style: TextStyle(color: subTextColor),
                          ),
                          if (!isActive)
                            Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        "Requested Duration",
                                        style: TextStyle(
                                          color: textColor,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        "${_sessionData['duration'] ?? 60} mins",
                                        style: const TextStyle(
                                          color: Colors.blueAccent,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),

                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              childAspectRatio: 0.8,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                            ),
                        itemCount: _installedApps.length,
                        itemBuilder: (context, index) {
                          final app = _installedApps[index];
                          final pkg = app['packageName'];
                          final name = app['appName'];

                          final isSelected = _selectedApps.contains(pkg);
                          final isLocked = _lockedApps.contains(pkg);

                          return GestureDetector(
                            onTap: () => _toggleAppSelection(pkg),
                            child: Container(
                              decoration: BoxDecoration(
                                color: isLocked
                                    ? Colors.red.withValues(alpha: 0.2)
                                    : isSelected
                                    ? Colors.blueAccent.withValues(alpha: 0.2)
                                    : (isDark
                                          ? AppColors.cardOverlay
                                          : Colors.white70),
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
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      color: Colors.black.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                    child: AppIconWidget(
                                      packageName: app['packageName'],
                                      appName: app['appName'],
                                      iconBytes: app['decodedIcon'],
                                      size: 40,
                                    ),
                                  ),

                                  Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Text(
                                      name,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: isLocked
                                            ? Colors.redAccent
                                            : textColor,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),

                                  if (isLocked)
                                    const Icon(
                                      Icons.lock,
                                      color: Colors.red,
                                      size: 12,
                                    )
                                  else if (isSelected)
                                    const Icon(
                                      Icons.check_circle,
                                      color: Colors.blueAccent,
                                      size: 12,
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),

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
                                    label: const Text(
                                      'End Session & Unlock All',
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 15,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  "Student cannot unlock apps. You must end the session.",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: isDark ? Colors.grey[400] : Colors.grey.shade600,
                                    fontSize: 12,
                                  ),
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
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
