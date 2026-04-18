import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:focus_mate/screens/companion/companion_control_page.dart';
import 'package:focus_mate/screens/parent/parent_child_control_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focus_mate/providers/user_provider.dart';

/// Dashboard for parents to manage linked children and enforce restrictions.
class ParentDashboard extends ConsumerStatefulWidget {
  final Function onLogout;

  const ParentDashboard({
    super.key,
    required this.onLogout,
  });

  @override
  ConsumerState<ParentDashboard> createState() => _ParentDashboardState();
}

class _ParentDashboardState extends ConsumerState<ParentDashboard> {
  String get _userId => ref.read(currentUserIdProvider)!;
  String? linkCode;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _pendingSessions = [];
  List<Map<String, dynamic>> _activeSessions = [];
  List<Map<String, dynamic>> _unlockRequests = [];
  
  @override
  void initState() {
    super.initState();
    _loadLinkCode();
    _listenForSessionRequests();
    _listenForActiveSessions();
    _listenForUnlockRequests();
  }

  /// Listens for incoming app unlock requests from children.
  void _listenForUnlockRequests() {
    _firestore
        .collection('unlock_requests')
        .where('parentId', isEqualTo: _userId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        final reqs = snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
        reqs.sort((a, b) {
           Timestamp? tA = a['requestedAt'];
           Timestamp? tB = b['requestedAt'];
           if (tA == null) return 1;
           if (tB == null) return -1;
           return tB.compareTo(tA);
        });
        setState(() => _unlockRequests = reqs);
      }
    });
  }

  /// Listens for incoming session requests.
  void _listenForSessionRequests() {
    _firestore
        .collection('companion_sessions')
        .where('companionId', isEqualTo: _userId)
        .where('status', isEqualTo: 'REQUESTED')
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        // Deduplicate requests logic similar to CompanionDashboard
        final Map<String, Map<String, dynamic>> latestRequests = {};
        for (final doc in snapshot.docs) {
          final data = doc.data();
          final userId = data['userId'];
          if (!latestRequests.containsKey(userId)) {
             latestRequests[userId] = {'id': doc.id, ...data};
          } else {
             // Keep newer
             final existing = latestRequests[userId]!;
             final Timestamp? newTime = data['requestedAt'];
             final Timestamp? oldTime = existing['requestedAt'];
             if (newTime != null && (oldTime == null || newTime.compareTo(oldTime) > 0)) {
                latestRequests[userId] = {'id': doc.id, ...data};
             }
          }
        }
        final requests = latestRequests.values.toList();
        requests.sort((a, b) {
           Timestamp? tA = a['requestedAt'];
           Timestamp? tB = b['requestedAt'];
           if (tA == null) return 1;
           if (tB == null) return -1;
           return tB.compareTo(tA);
        });
        setState(() => _pendingSessions = requests);
      }
    });
  }

  /// Listens for currently active sessions.
  void _listenForActiveSessions() {
    _firestore
        .collection('companion_sessions')
        .where('companionId', isEqualTo: _userId)
        .where('status', isEqualTo: 'ACTIVE')
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _activeSessions = snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
        });
      }
    });
  }

  /// Loads the parent's unique link code.
  Future<void> _loadLinkCode() async {
    final userState = ref.read(userProvider);
    final linkCodeFromProvider = userState.when(
      data: (u) => u?.toMap()['linkCode'],
      loading: () => null,
      error: (_, __) => null,
    );

    if (linkCodeFromProvider != null) {
      setState(() => linkCode = linkCodeFromProvider);
      return;
    }
    final doc = await _firestore.collection('users').doc(_userId).get();
    setState(() => linkCode = doc.data()?['linkCode']);
  }

  String _generateCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rng = Random.secure();
    return List.generate(8, (index) => chars[rng.nextInt(chars.length)]).join();
  }

  Future<void> _refreshCode() async {
    final code = _generateCode();
    await _firestore.collection('users').doc(_userId).update({
      'linkCode': code,
      'linkCodeExpiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(hours: 24))),
    });
    setState(() => linkCode = code);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          "Parent Dashboard",
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 22),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: () => widget.onLogout(),
            icon: const Icon(Icons.logout, color: Colors.redAccent),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Background Gradient (Parent Theme: Deep Pinks/Reds)
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark 
                  ? [const Color(0xFF1A1F35), const Color(0xFF0B0E17)] 
                  : [const Color(0xFFF8FAFC), const Color(0xFFE2E8F0)],
              ),
            ),
          ),
          
          SafeArea(
            child: CustomScrollView(
              slivers: [
                // Link Code Section
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                    child: _buildHeaderCard(isDark),
                  ),
                ),

                // Session Requests
                if (_pendingSessions.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionTitle("Session Requests", Icons.notifications_active, Colors.orange, isDark),
                          const SizedBox(height: 12),
                          ..._pendingSessions.map((s) => _buildSessionRequestCard(s)),
                        ],
                      ),
                    ),
                  ),

                // Active Sessions
                if (_activeSessions.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionTitle("Active Sessions", Icons.play_circle_fill, Colors.green, isDark),
                          const SizedBox(height: 12),
                          ..._activeSessions.map((s) => _buildActiveSessionCard(s)),
                        ],
                      ),
                    ),
                  ),

                // App Unlock Requests
                if (_unlockRequests.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionTitle("App Unlock Requests", Icons.lock_open, Colors.blueAccent, isDark),
                          const SizedBox(height: 12),
                          ..._unlockRequests.map((req) => _buildUnlockRequestCard(req)),
                        ],
                      ),
                    ),
                  ),

                // Connected Children Header
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
                        Icon(Icons.family_restroom, size: 18, color: Colors.pinkAccent.withValues(alpha: 0.5)),
                      ],
                    ),
                  ),
                ),

                // Connected Children List
                StreamBuilder<DocumentSnapshot>(
                  stream: _firestore
                      .collection('users')
                      .doc(_userId)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));
                    }

                    if (!snapshot.hasData || !snapshot.data!.exists) {
                      return const SliverToBoxAdapter(child: Center(child: Text("No connection data found.")));
                    }

                    final data = snapshot.data!.data() as Map<String, dynamic>;
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
                              Icon(Icons.child_care_rounded, size: 64, color: Colors.grey.withValues(alpha: 0.3)),
                              const SizedBox(height: 16),
                              Text(
                                "No children linked yet.\nUse your parent code to connect!",
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
            color: const Color(0xFF6366F1).withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Parent Link Code",
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
            "Link your child's device by entering this code in their Focus Mate app.",
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _glassIconButton(IconData icon, VoidCallback onPressed) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: 20),
        onPressed: onPressed,
      ),
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

  Widget _buildStudentTile(String studentId, bool isDark) {
    return FutureBuilder<DocumentSnapshot>(
      future: _firestore.collection('users').doc(studentId).get(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return Container(height: 80, decoration: BoxDecoration(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white70, borderRadius: BorderRadius.circular(16)));
        }

        final student = snap.data!.data() as Map<String, dynamic>;
        final studentName = student['name'] ?? "Unknown";

        return Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Stack(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.blueAccent.withValues(alpha: 0.1),
                  child: Text(studentName[0].toUpperCase(), style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 20)),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.green, // Placeholder for online status
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
              decoration: BoxDecoration(color: Colors.blueAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.analytics_outlined, color: Colors.blueAccent, size: 20),
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ParentChildControlPage(
                    studentId: studentId,
                    studentName: studentName,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildSessionRequestCard(Map<String, dynamic> session) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final studentName = session['userName'] ?? 'Child';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.orange.withValues(alpha: 0.1),
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
            ),
            child: const Text("Approve"),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveSessionCard(Map<String, dynamic> session) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final studentName = session['userName'] ?? 'Child';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.green.withValues(alpha: 0.1),
            child: Text(studentName[0].toUpperCase(), style: const TextStyle(color: Colors.green)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(studentName, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
                const Text('Session Active', style: TextStyle(color: Colors.green, fontSize: 12)),
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
                    companionId: _userId,
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
            child: const Text("Control"),
          ),
        ],
      ),
    );
  }

  Widget _buildUnlockRequestCard(Map<String, dynamic> req) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blueAccent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_open, color: Colors.blueAccent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "${req['studentName']} requested to unlock ${req['appName']}",
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "\"${req['reason']}\"",
            style: TextStyle(color: Colors.grey.withValues(alpha: 0.8), fontStyle: FontStyle.italic, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => _handleUnlockRequest(req, false),
                child: const Text("Refuse", style: TextStyle(color: Colors.redAccent)),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => _handleUnlockRequest(req, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text("Approve"),
              ),
            ],
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
            companionId: _userId,
          ),
        ),
      );
    } else {
      await _firestore.collection('companion_sessions').doc(sessionId).update({'status': 'REJECTED'});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Request rejected"), backgroundColor: Colors.orange),
        );
      }
    }
  }

  Future<void> _handleUnlockRequest(Map<String, dynamic> req, bool approve) async {
    try {
      await _firestore.collection('unlock_requests').doc(req['id']).update({
        'status': approve ? 'approved' : 'rejected',
        'respondedAt': FieldValue.serverTimestamp(),
      });
      if (approve) {
        if (req['packageName'] == 'all') {
             // Suspend ALL locks
             final batch = _firestore.batch();
             
             // 1. Clear instant locks and timer
             final userRef = _firestore.collection('users').doc(req['studentId']);
             batch.update(userRef, {
               'lockedApps': [],
               'lockEndTime': null,
             });
             
             // 2. Clear schedules mapping to this user
             final schedulesSnapshot = await _firestore
                 .collection('users')
                 .doc(req['studentId'])
                 .collection('schedules')
                 .where('status', isEqualTo: 'active')
                 .get();
                 
             for (var doc in schedulesSnapshot.docs) {
                 batch.update(doc.reference, {'status': 'inactive'});
             }
             
             await batch.commit();
        } else if (req['packageName'].toString().startsWith('schedule_')) {
            // Unlock specific schedule
            final scheduleId = req['packageName'].toString().substring('schedule_'.length);
            await _firestore
                .collection('users')
                .doc(req['studentId'])
                .collection('schedules')
                .doc(scheduleId)
                .update({'status': 'inactive'});
        } else {
            // Normal single app unlock
            await _firestore.collection('users').doc(req['studentId']).update({
              'lockedApps': FieldValue.arrayRemove([req['packageName']]),
            });
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(approve ? "Unlock request approved." : "Unlock request refused."),
            backgroundColor: approve ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed: $e"), backgroundColor: Colors.red));
      }
    }
  }
}
