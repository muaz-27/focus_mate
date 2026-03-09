import 'dart:math';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/auth_service.dart';
import '../theme/app_colors.dart';
import 'analytics_screen.dart'; 
import './companion_control_page.dart';
import 'schedule_approval_screen.dart';

/// Dashboard for companions (parents/partners) to manage linked students and sessions.
class CompanionDashboard extends StatefulWidget {
  final Map<String, dynamic> userData;
  final Function onLogout;

  const CompanionDashboard({
    super.key,
    required this.userData,
    required this.onLogout,
  });

  @override
  State<CompanionDashboard> createState() => _CompanionDashboardState();
}

class _CompanionDashboardState extends State<CompanionDashboard> {
  String? linkCode;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _pendingSessions = [];
  List<Map<String, dynamic>> _activeSessions = [];
  List<Map<String, dynamic>> _pendingSchedules = [];
  List<Map<String, dynamic>> _activeSchedules = [];
  List<Map<String, dynamic>> _pendingUnlockRequests = [];

  final Map<String, StreamSubscription> _studentScheduleSubscriptions = {};
  final Map<String, StreamSubscription> _studentUnlockSubscriptions = {};
  StreamSubscription? _userDocSubscription;

  @override
  void initState() {
    super.initState();
    _loadLinkCode();
    _listenForSessionRequests();
    _listenForActiveSessions();
    _listenForUserChanges();
  }

  @override
  void dispose() {
    for (var sub in _studentScheduleSubscriptions.values) {
      sub.cancel();
    }
    for (var sub in _studentUnlockSubscriptions.values) {
      sub.cancel();
    }
    _userDocSubscription?.cancel();
    super.dispose();
  }

  /// Listens to the companion's own document to manage student-specific listeners.
  void _listenForUserChanges() {
    _userDocSubscription = _firestore
        .collection('users')
        .doc(widget.userData['id'])
        .snapshots()
        .listen((doc) {
      if (!mounted || !doc.exists) return;
      final data = doc.data() as Map<String, dynamic>;
      
      final linkedSet = <String>{
        ...List<String>.from(data['linkedStudents'] ?? []),
        ...List<String>.from(data['linkedUsers'] ?? []),
      };
      
      final currentStudentIds = linkedSet.toList();
      
      // Remove stale listeners
      final staleIds = _studentScheduleSubscriptions.keys.where((id) => !currentStudentIds.contains(id)).toList();
      for (var id in staleIds) {
        _studentScheduleSubscriptions.remove(id)?.cancel();
        _studentUnlockSubscriptions.remove(id)?.cancel();
      }

      // Add new listeners
      for (var studentId in currentStudentIds) {
        if (!_studentScheduleSubscriptions.containsKey(studentId)) {
          _startStudentListeners(studentId);
        }
      }
    });
  }

  void _startStudentListeners(String studentId) {
    // 1. Listen for ALL Schedules
    _studentScheduleSubscriptions[studentId] = _firestore
        .collection('users')
        .doc(studentId)
        .collection('schedules')
        .snapshots()
        .listen((snapshot) async {
       _updateSchedules(studentId, snapshot.docs);
    });

    // 2. Listen for Unlock Requests
    _studentUnlockSubscriptions[studentId] = _firestore
        .collection('users')
        .doc(studentId)
        .collection('unlock_requests')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snapshot) async {
       _updatePendingUnlockRequests(studentId, snapshot.docs);
    });
  }

  // Intermediate storage per student to simplify merging
  final Map<String, List<Map<String, dynamic>>> _perStudentPendingSchedules = {};
  final Map<String, List<Map<String, dynamic>>> _perStudentActiveSchedules = {};
  final Map<String, List<Map<String, dynamic>>> _perStudentUnlocks = {};

  Future<void> _updateSchedules(String studentId, List<QueryDocumentSnapshot> docs) async {
    if (!mounted) return;
    String userName = "Student";
    try {
      final userDoc = await _firestore.collection('users').doc(studentId).get();
      userName = userDoc.data()?['name'] ?? "Student";
    } catch (_) {}

    final allSchedules = docs.map((doc) => {
      'id': doc.id,
      'userId': studentId,
      'userName': userName,
      ...doc.data() as Map<String, dynamic>
    }).toList();

    setState(() {
      _perStudentPendingSchedules[studentId] = allSchedules.where((s) => s['status'] == 'requested').toList();
      _perStudentActiveSchedules[studentId] = allSchedules.where((s) => s['status'] == 'active').toList();
      _pendingSchedules = _perStudentPendingSchedules.values.expand((x) => x).toList();
      _activeSchedules = _perStudentActiveSchedules.values.expand((x) => x).toList();
    });
  }

  Future<void> _updatePendingUnlockRequests(String studentId, List<QueryDocumentSnapshot> docs) async {
    if (!mounted) return;
    String userName = "Student";
    try {
      final userDoc = await _firestore.collection('users').doc(studentId).get();
      userName = userDoc.data()?['name'] ?? "Student";
    } catch (_) {}

    final requests = docs.map((doc) => {
      'id': doc.id,
      'userId': studentId,
      'userName': userName,
      ...doc.data() as Map<String, dynamic>
    }).toList();

    setState(() {
      _perStudentUnlocks[studentId] = requests;
      _pendingUnlockRequests = _perStudentUnlocks.values.expand((x) => x).toList();
    });
  }

  /// Listens for incoming session requests, deduplicating to show only the latest per user.
  void _listenForSessionRequests() {
    _firestore
        .collection('companion_sessions')
        .where('companionId', isEqualTo: widget.userData['id'])
        .where('status', isEqualTo: 'REQUESTED')
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        // Deduplicate requests: keep latest per user
        final Map<String, Map<String, dynamic>> latestRequests = {};
        
        for (final doc in snapshot.docs) {
          final data = doc.data();
          final userId = data['userId'];
          
          if (!latestRequests.containsKey(userId)) {
             latestRequests[userId] = {
              'id': doc.id,
              ...data,
            };
          } else {
             // Keep the newer one if duplicate exists
             final existing = latestRequests[userId]!;
             final Timestamp? newTime = data['requestedAt'];
             final Timestamp? oldTime = existing['requestedAt'];
             
             if (newTime != null && (oldTime == null || newTime.compareTo(oldTime) > 0)) {
                latestRequests[userId] = {
                  'id': doc.id,
                  ...data,
                };
             }
          }
        }
        
        final requests = latestRequests.values.toList();
        
        // Sort by time descending
        requests.sort((a, b) {
           Timestamp? tA = a['requestedAt'];
           Timestamp? tB = b['requestedAt'];
           if (tA == null) return 1;
           if (tB == null) return -1;
           return tB.compareTo(tA);
        });
        
        setState(() {
          _pendingSessions = requests;
        });
      }
    }, onError: (e) {
      debugPrint("Error listening for requests: $e");
    });
  }

  /// Listens for currently active sessions managed by this companion.
  void _listenForActiveSessions() {
    _firestore
        .collection('companion_sessions')
        .where('companionId', isEqualTo: widget.userData['id'])
        .where('status', isEqualTo: 'ACTIVE')
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _activeSessions = snapshot.docs.map((doc) {
            final data = doc.data();
            return {
              'id': doc.id,
              ...data,
            };
          }).toList();
        });
      }
    });
  }



  /// Loads the companion's unique link code from Firestore.
  Future<void> _loadLinkCode() async {
    if (widget.userData['linkCode'] != null) {
      setState(() {
        linkCode = widget.userData['linkCode'];
      });
      return;
    }

    final doc = await _firestore
        .collection('users')
        .doc(widget.userData['id'])
        .get();
    setState(() {
      linkCode = doc.data()?['linkCode'];
    });
  }

  /// Generates a random 6-character alphanumeric code.
  String _generateCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(
      6,
      (index) => chars[Random().nextInt(chars.length)],
    ).join();
  }

  /// Generates a new link code and updates it in Firestore.
  Future<void> _refreshCode() async {
    final code = _generateCode();
    await _firestore.collection('users').doc(widget.userData['id']).update({
      'linkCode': code,
    });
    setState(() {
      linkCode = code;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          "Companion Dashboard",
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 22),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: () => AuthService().signOut(),
            icon: const Icon(Icons.logout, color: Colors.redAccent),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Background Gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark 
                  ? [const Color(0xFF0F172A), const Color(0xFF1E293B)] 
                  : [const Color(0xFFF1F5F9), const Color(0xFFE2E8F0)],
              ),
            ),
          ),
          
          SafeArea(
            child: CustomScrollView(
              slivers: [
                // Link Code Section
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: _buildHeaderCard(isDark),
                  ),
                ),

                // Session Requests
                if (_pendingSessions.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: _buildSessionRequestsSection(),
                    ),
                  ),

                // Schedule Requests
                if (_pendingSchedules.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: _buildScheduleRequestsSection(),
                    ),
                  ),

                // Active Sessions (Manual)
                if (_activeSessions.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: _buildActiveSessionsSection(),
                    ),
                  ),

                // Active App Lock Schedules
                if (_activeSchedules.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: _buildActiveSchedulesSection(),
                    ),
                  ),

                // Unlock Requests
                if (_pendingUnlockRequests.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: _buildUnlockRequestsSection(),
                    ),
                  ),

                // Connected Students Header
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                    child: Row(
                      children: [
                        Text(
                          "Monitored Children",
                          style: TextStyle(
                            color: textColor,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        const Icon(Icons.sync, size: 16, color: Colors.blueAccent),
                      ],
                    ),
                  ),
                ),

                // Connected Students List
                StreamBuilder<DocumentSnapshot>(
                  stream: _firestore
                      .collection('users')
                      .doc(widget.userData['id'])
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));
                    }

                    if (!snapshot.hasData || !snapshot.data!.exists) {
                      return const SliverToBoxAdapter(child: Center(child: Text("No connection data found.")));
                    }

                    final data = snapshot.data!.data() as Map<String, dynamic>;
                    
                    // FIX: Standardize syncing by merging linkedUsers and linkedStudents
                    final linkedSet = <String>{
                      ...List<String>.from(data['linkedStudents'] ?? []),
                      ...List<String>.from(data['linkedUsers'] ?? []),
                    };
                    final linked = linkedSet.toList();

                    if (linked.isEmpty) {
                      return SliverToBoxAdapter(
                        child: Container(
                          padding: const EdgeInsets.all(40),
                          child: Column(
                            children: [
                              Icon(Icons.child_care_rounded, size: 64, color: Colors.grey.withOpacity(0.3)),
                              const SizedBox(height: 16),
                              Text(
                                "No children linked yet.\nShare your code to get started!",
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey[500], fontSize: 16),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final studentId = linked[index];
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: _buildStudentTile(studentId, isDark),
                          );
                        },
                        childCount: linked.length,
                      ),
                    );
                  },
                ),
                
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6366F1), Color(0xFF3B82F6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Share Link Code",
            style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                linkCode ?? "...",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                ),
              ),
              Row(
                children: [
                  _glassIconButton(Icons.refresh, _refreshCode),
                  const SizedBox(width: 8),
                  _glassIconButton(Icons.copy, () {
                    if (linkCode != null) {
                      Clipboard.setData(ClipboardData(text: linkCode!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Code copied!")),
                      );
                    }
                  }),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            "Connect children by letting them enter this code in their Focus Mate dashboard.",
            style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _glassIconButton(IconData icon, VoidCallback onPressed) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: 20),
        onPressed: onPressed,
      ),
    );
  }


  Widget _buildStudentTile(String studentId, bool isDark) {
    return FutureBuilder<DocumentSnapshot>(
      future: _firestore.collection('users').doc(studentId).get(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return Container(height: 80, decoration: BoxDecoration(color: isDark ? Colors.white.withOpacity(0.05) : Colors.white70, borderRadius: BorderRadius.circular(16)));
        }

        final student = snap.data!.data() as Map<String, dynamic>;
        final studentName = student['name'] ?? "Unknown";
        final isOnline = student['isOnline'] ?? false; // Assuming we have this field or similar

        return Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Stack(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.blueAccent.withOpacity(0.1),
                  child: Text(studentName[0].toUpperCase(), style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 20)),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: isOnline ? Colors.green : Colors.grey,
                      shape: BoxShape.circle,
                      border: Border.all(color: isDark ? const Color(0xFF1E293B) : Colors.white, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            title: Text(studentName, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 16)),
            subtitle: Text("Level ${student['level'] ?? 1} • Focus Scholar", style: TextStyle(color: Colors.grey[500], fontSize: 12)),
            trailing: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.analytics_outlined, color: Colors.blueAccent, size: 20),
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AnalyticsScreen(
                    userId: studentId,
                    userName: studentName,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildSessionRequestsSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle("Session Requests", Icons.notifications_active, Colors.orange, isDark),
        const SizedBox(height: 12),
        ..._pendingSessions.map((session) => _buildSessionRequestCard(session)),
      ],
    );
  }

  Widget _buildActiveSessionsSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle("Active Sessions", Icons.play_circle_outline, Colors.green, isDark),
        const SizedBox(height: 12),
        ..._activeSessions.map((session) => _buildActiveSessionCard(session)),
      ],
    );
  }

  Widget _buildActiveSchedulesSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle("Active App Lock Schedules", Icons.lock, Colors.amber, isDark),
        const SizedBox(height: 12),
        ..._activeSchedules.map((schedule) => _buildActiveScheduleCard(schedule)),
      ],
    );
  }

  Widget _buildActiveScheduleCard(Map<String, dynamic> schedule) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final studentName = schedule['userName'] ?? 'Student';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.amber.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.amber.withOpacity(0.1),
            child: Text(studentName[0].toUpperCase(), style: const TextStyle(color: Colors.amber)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("$studentName - ${schedule['name']}", style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
                Text("${(schedule['lockedApps'] as List?)?.length ?? 0} apps locked", style: TextStyle(color: Colors.grey[500], fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.stop_circle_outlined, color: Colors.amber),
            tooltip: "Stop Schedule",
            onPressed: () => _stopSchedule(schedule['userId'], schedule['id']),
          ),
        ],
      ),
    );
  }

  Future<void> _stopSchedule(String studentId, String scheduleId) async {
    try {
      await _firestore.collection('users').doc(studentId).collection('schedules').doc(scheduleId).update({
        'status': 'inactive',
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Schedule stopped")));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Widget _buildScheduleRequestsSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle("Schedule Requests", Icons.schedule, Colors.amber, isDark),
        const SizedBox(height: 12),
        ..._pendingSchedules.map((schedule) => _buildScheduleRequestCard(schedule)),
      ],
    );
  }

  Widget _buildUnlockRequestsSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle("App Unlock Requests", Icons.lock_open, Colors.purpleAccent, isDark),
        const SizedBox(height: 12),
        ..._pendingUnlockRequests.map((req) => _buildUnlockRequestCard(req)),
      ],
    );
  }

  Widget _buildSectionTitle(String title, IconData icon, Color color, bool isDark) {
    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 8),
        Text(title, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildSessionRequestCard(Map<String, dynamic> session) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final studentName = session['userName'] ?? 'Student';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.orange.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.orange.withOpacity(0.1),
            child: Text(studentName[0].toUpperCase(), style: const TextStyle(color: Colors.orange)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(studentName, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
                Text('${session['duration'] ?? 60}m study request', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.grey),
            onPressed: () => _respondToRequest(session['id'], false),
          ),
          ElevatedButton(
            onPressed: () => _respondToRequest(session['id'], true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: const Text("Approve"),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleRequestCard(Map<String, dynamic> schedule) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final studentName = schedule['userName'] ?? 'Student';
    final scheduleName = schedule['name'] ?? 'Schedule';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.amber.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.amber.withOpacity(0.1),
            child: Text(studentName[0].toUpperCase(), style: const TextStyle(color: Colors.amber)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(studentName, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
                Text('New Schedule: $scheduleName', style: TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          // Reject button
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.grey),
            onPressed: () async {
              await _firestore
                 .collection('users')
                 .doc(schedule['userId'])
                 .collection('schedules')
                 .doc(schedule['id'])
                 .delete();
            },
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ScheduleApprovalScreen(
                    schedule: schedule,
                    companionId: widget.userData['id'],
                  ),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: const Text("Review"),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveSessionCard(Map<String, dynamic> session) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final studentName = session['userName'] ?? 'Student';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.green.withOpacity(0.1),
            child: Text(studentName[0].toUpperCase(), style: const TextStyle(color: Colors.green)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(studentName, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
                const Text('Session In-Progress', style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CompanionControlPage(
                    sessionId: session['id'],
                    companionId: widget.userData['id'],
                  ),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("Manage"),
          ),
        ],
      ),
    );
  }

  Future<void> _respondToRequest(String sessionId, bool accept) async {
    if (accept) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CompanionControlPage(
            sessionId: sessionId,
            companionId: widget.userData['id'],
          ),
        ),
      );
    } else {
      await _firestore.collection('companion_sessions').doc(sessionId).update({
        'status': 'REJECTED',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session request rejected')));
      }
    }
  }

  Future<void> _approveUnlockRequest(Map<String, dynamic> req) async {
    final userId = req['userId'];
    final reqId = req['id'];
    final packageName = req['packageName'];

    // Update request status
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('unlock_requests')
        .doc(reqId)
        .update({'status': 'approved'});

    if (packageName == 'all') {
      // Suspend all locks: Quick locks, active schedules, and companion sessions
      final batch = _firestore.batch();
      
      final userRef = _firestore.collection('users').doc(userId);
      batch.update(userRef, {
        'lockedApps': [],
        'lockEndTime': null,
      });

      final sessionsSnap = await _firestore
          .collection('companion_sessions')
          .where('userId', isEqualTo: userId)
          .where('status', isEqualTo: 'ACTIVE')
          .get();
      for (var doc in sessionsSnap.docs) {
         batch.update(doc.reference, {'status': 'COMPLETED'});
      }

      final schedulesSnap = await _firestore
          .collection('users')
          .doc(userId)
          .collection('schedules')
          .where('status', isEqualTo: 'active')
          .get();
      for (var doc in schedulesSnap.docs) {
        batch.update(doc.reference, {'status': 'inactive'});
      }
      
      await batch.commit();
    } else if (packageName.toString().startsWith('schedule_')) {
      final scheduleId = packageName.toString().substring('schedule_'.length);
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('schedules')
          .doc(scheduleId)
          .update({'status': 'inactive'});
    } else {
      // Legacy or specific app unlock
      final sessionsSnap = await _firestore
          .collection('companion_sessions')
          .where('userId', isEqualTo: userId)
          .where('status', isEqualTo: 'ACTIVE')
          .get();
          
      for (var doc in sessionsSnap.docs) {
         await doc.reference.update({
           'lockedApps': FieldValue.arrayRemove([packageName]),
           'manuallyUnlockedApps': FieldValue.arrayUnion([packageName]),
         });
      }

      await _firestore.collection('users').doc(userId).update({
        'lockedApps': FieldValue.arrayRemove([packageName]),
      });

      final schedulesSnap = await _firestore
          .collection('users')
          .doc(userId)
          .collection('schedules')
          .get();

      for (var doc in schedulesSnap.docs) {
        await doc.reference.update({
          'exemptions': FieldValue.arrayUnion([packageName]),
        });
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("App unlocked successfully")));
    }
  }

  Future<void> _denyUnlockRequest(Map<String, dynamic> req) async {
    final userId = req['userId'];
    final reqId = req['id'];
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('unlock_requests')
        .doc(reqId)
        .update({'status': 'denied'});
  }

  Widget _buildUnlockRequestCard(Map<String, dynamic> req) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final studentName = req['userName'] ?? 'Student';
    final appName = req['appName'] ?? 'Unknown App';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.purple.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.purple.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.purple.withOpacity(0.1),
            child: Text(studentName[0].toUpperCase(), style: const TextStyle(color: Colors.purple)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(studentName, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
                Text('Unlock: $appName', style: const TextStyle(color: Colors.purpleAccent, fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.grey),
            onPressed: () => _denyUnlockRequest(req),
          ),
          ElevatedButton(
            onPressed: () => _approveUnlockRequest(req),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purpleAccent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: const Text("Unlock"),
          ),
        ],
      ),
    );
  }
}