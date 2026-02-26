import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/auth_service.dart';
import 'analytics_screen.dart'; 
import './companion_control_page.dart';
import 'parent_child_control_page.dart';

/// Dashboard for parents to manage linked children and enforce restrictions.
class ParentDashboard extends StatefulWidget {
  final Map<String, dynamic> userData;
  final Function onLogout;

  const ParentDashboard({
    super.key,
    required this.userData,
    required this.onLogout,
  });

  @override
  State<ParentDashboard> createState() => _ParentDashboardState();
}

class _ParentDashboardState extends State<ParentDashboard> {
  String? linkCode;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _pendingSessions = [];
  List<Map<String, dynamic>> _activeSessions = [];
  List<Map<String, dynamic>> _unlockRequests = [];
  
  // Parent Theme Colors
  final List<Color> _gradientColors = [const Color(0xFF3D1E00), const Color(0xFF3A0505)]; // Dark Red/Brown
  final Color _primaryColor = Colors.orangeAccent;

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
        .where('parentId', isEqualTo: widget.userData['id'])
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
        .where('companionId', isEqualTo: widget.userData['id'])
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
        .where('companionId', isEqualTo: widget.userData['id'])
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
    if (widget.userData['linkCode'] != null) {
      setState(() => linkCode = widget.userData['linkCode']);
      return;
    }
    final doc = await _firestore.collection('users').doc(widget.userData['id']).get();
    setState(() => linkCode = doc.data()?['linkCode']);
  }

  String _generateCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(6, (index) => chars[Random().nextInt(chars.length)]).join();
  }

  Future<void> _refreshCode() async {
    final code = _generateCode();
    await _firestore.collection('users').doc(widget.userData['id']).update({'linkCode': code});
    setState(() => linkCode = code);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text("Parent Dashboard", style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
        actions: [
          IconButton(
            onPressed: () => AuthService().signOut(),
            icon: const Icon(Icons.logout, color: Colors.redAccent),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark 
              ? [const Color(0xFF1A1F35), const Color(0xFF0B0E17)] 
              : [const Color(0xFFF8FAFC), const Color(0xFFE2E8F0)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Link Code Card (Parent Themed)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFD946EF), Color(0xFFE11D48)], // Pink/Red gradient for Parents
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.redAccent.withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Parent Link Code",
                        style: TextStyle(color: Colors.white.withOpacity(0.9), fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            linkCode ?? "Generating...",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                            ),
                          ),
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.refresh, color: Colors.white),
                                onPressed: _refreshCode,
                              ),
                              if (linkCode != null)
                                IconButton(
                                  icon: const Icon(Icons.copy, color: Colors.white),
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: linkCode!));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text("Code copied!")),
                                    );
                                  },
                                ),
                            ],
                          ),
                        ],
                      ),
                      const Text(
                        "Enter this code on your child's device to link.",
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Requests & Sessions
                if (_pendingSessions.isNotEmpty) ...[
                  _buildSectionHeader("Requests", Icons.notifications_active, Colors.orange),
                  ..._pendingSessions.map((s) => _buildSessionRequestCard(s)),
                  const SizedBox(height: 24),
                ],

                if (_activeSessions.isNotEmpty) ...[
                   _buildSectionHeader("Active Sessions", Icons.timer, Colors.green),
                   ..._activeSessions.map((s) => _buildActiveSessionCard(s)),
                   const SizedBox(height: 24),
                ],

                if (_unlockRequests.isNotEmpty) ...[
                   _buildSectionHeader("App Unlock Requests", Icons.lock_open, Colors.blueAccent),
                   ..._unlockRequests.map((req) => _buildUnlockRequestCard(req)),
                   const SizedBox(height: 24),
                ],

                // Connected Children List
                _buildSectionHeader("Monitored Children", Icons.child_care, _primaryColor),
                Expanded(
                  child: StreamBuilder<DocumentSnapshot>(
                    stream: _firestore.collection('users').doc(widget.userData['id']).snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                      
                      final data = snapshot.data!.data() as Map<String, dynamic>;
                      // Merge both fields to handle potential mismatch from previous version
                      final linked = <String>{
                        ...List<String>.from(data['linkedUsers'] ?? []),
                        ...List<String>.from(data['linkedStudents'] ?? []),
                      }.toList();

                      if (linked.isEmpty) {
                        return Center(
                           child: Column(
                             mainAxisAlignment: MainAxisAlignment.center,
                             children: [
                               Icon(Icons.family_restroom, size: 48, color: Colors.grey[400]),
                               const SizedBox(height: 10),
                               Text("No children linked yet.", style: TextStyle(color: Colors.grey[600])),
                             ],
                           ),
                        );
                      }

                      return ListView.builder(
                        itemCount: linked.length,
                        itemBuilder: (context, index) {
                          final studentId = linked[index];
                          return FutureBuilder<DocumentSnapshot>(
                            future: _firestore.collection('users').doc(studentId).get(),
                            builder: (context, snap) {
                              if (!snap.hasData) return const SizedBox();
                              final student = snap.data!.data() as Map<String, dynamic>;
                              final studentName = student['name'] ?? "Unknown";

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.white.withOpacity(0.05) : Colors.white70,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                                ),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: _primaryColor.withOpacity(0.2),
                                    child: Text(studentName[0].toUpperCase(), style: TextStyle(color: _primaryColor)),
                                  ),
                                  title: Text(studentName, style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                                  subtitle: const Text("Monitor and control", style: TextStyle(fontSize: 12)),
                                  trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
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
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 8),
          Text(title, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildSessionRequestCard(Map<String, dynamic> session) {
    final textColor = Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87;
    return Card(
      color: Colors.orange.withOpacity(0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.orange.withOpacity(0.3))),
      child: ListTile(
        title: Text(session['userName'] ?? 'Child', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
        subtitle: Text("Requesting ${session['duration']} min session"),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: () => _respondToRequest(session['id'], false)),
            IconButton(icon: const Icon(Icons.check, color: Colors.green), onPressed: () => _respondToRequest(session['id'], true)),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveSessionCard(Map<String, dynamic> session) {
    final textColor = Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87;
    return Card(
      color: Colors.green.withOpacity(0.1),
       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.green.withOpacity(0.3))),
      child: ListTile(
        title: Text(session['userName'] ?? 'Child', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
        subtitle: const Text("Session Active"),
        trailing: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          child: const Text("Control"),
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
        ),
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
      await _firestore.collection('companion_sessions').doc(sessionId).update({'status': 'REJECTED'});
    }
  }

  Widget _buildUnlockRequestCard(Map<String, dynamic> req) {
    final textColor = Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87;
    return Card(
      color: Colors.blueAccent.withOpacity(0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.blueAccent.withOpacity(0.3))),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.lock_open, color: Colors.blueAccent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "${req['studentName']} requested to unlock ${req['appName']}",
                    style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              "\"${req['reason']}\"",
              style: TextStyle(color: Colors.grey.withOpacity(0.8), fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 12),
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
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
                  child: const Text("Approve"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleUnlockRequest(Map<String, dynamic> req, bool approve) async {
    try {
      // 1. Update request status
      await _firestore.collection('unlock_requests').doc(req['id']).update({
        'status': approve ? 'approved' : 'rejected',
        'respondedAt': FieldValue.serverTimestamp(),
      });

      if (approve) {
        // 2. Remove app from child's lockedApps array
        await _firestore.collection('users').doc(req['studentId']).update({
          'lockedApps': FieldValue.arrayRemove([req['packageName']]),
        });
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
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text("Failed to process request: $e"), backgroundColor: Colors.red)
        );
      }
    }
  }
}
