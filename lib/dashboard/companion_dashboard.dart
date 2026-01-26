import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/auth_service.dart';
import 'analytics_screen.dart'; 
import './companion_control_page.dart';

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

  @override
  void initState() {
    super.initState();
    _loadLinkCode();
    _listenForSessionRequests();
    _listenForActiveSessions();
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
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
        ),
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
            stops: const [0.0, 1.0],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4F46E5), Color(0xFF3B82F6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Your Link Code",
                    style: TextStyle(color: isDark ? Colors.white70 : Colors.white.withOpacity(0.9)),
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
                            icon: const Icon(
                              Icons.refresh,
                              color: Colors.white,
                            ),
                            onPressed: _refreshCode,
                          ),
                          if (linkCode != null)
                            IconButton(
                              icon: const Icon(Icons.copy, color: Colors.white),
                              onPressed: () {
                                Clipboard.setData(
                                  ClipboardData(text: linkCode!),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("Code copied!")),
                                );
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
                  Text(
                    "Share this code with a student to connect.",
                    style: TextStyle(color: isDark ? Colors.white38 : Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            if (_pendingSessions.isNotEmpty) ...[
              _buildSessionRequestsSection(),
              const SizedBox(height: 24),
            ],

            if (_activeSessions.isNotEmpty) ...[
              _buildActiveSessionsSection(),
              const SizedBox(height: 24),
            ],

            Text(
              "Connected Students",
              style: TextStyle(
                color: textColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            Expanded(
              child: StreamBuilder<DocumentSnapshot>(
                stream: _firestore
                    .collection('users')
                    .doc(widget.userData['id'])
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!snapshot.hasData || !snapshot.data!.exists) {
                    return const Center(child: Text("No data"));
                  }

                  final data = snapshot.data!.data() as Map<String, dynamic>;
                  final linked = List<String>.from(
                    data['linkedStudents'] ?? [],
                  );

                  if (linked.isEmpty) {
                    return Center(
                      child: Text(
                        "No students connected yet.",
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: linked.length,
                    itemBuilder: (context, index) {
                      final studentId = linked[index];

                      return FutureBuilder<DocumentSnapshot>(
                        future: _firestore
                            .collection('users')
                            .doc(studentId)
                            .get(),
                        builder: (context, snap) {
                          if (!snap.hasData) return const SizedBox();

                          final student =
                              snap.data!.data() as Map<String, dynamic>;
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
                                backgroundColor: Colors.blueAccent.withOpacity(0.2),
                                child: Text(
                                  studentName[0].toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.blueAccent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              title: Text(
                                studentName,
                                style: TextStyle(color: textColor),
                              ),
                              subtitle: const Text(
                                "Tap to view usage",
                                style: TextStyle(color: Colors.grey),
                              ),
                              trailing: const Icon(
                                Icons.arrow_forward_ios,
                                size: 16,
                                color: Colors.white54,
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
                    },
                  );
                },
              ),
            ),
            ],
          ),
        ),
      ),
    ));
  }

  /// Builds the section displaying pending session requests.
  Widget _buildSessionRequestsSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.notifications_active, color: Colors.orange, size: 24),
            const SizedBox(width: 8),
            Text(
              "Session Requests",
              style: TextStyle(
                color: textColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _pendingSessions.length.toString(),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ..._pendingSessions.map((session) => _buildSessionRequestCard(session)),
      ],
    );
  }

  /// Builds the section displaying currently active sessions.
  Widget _buildActiveSessionsSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.timer, color: Colors.green, size: 24),
            const SizedBox(width: 8),
            Text(
              "Active Sessions",
              style: TextStyle(
                color: textColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _activeSessions.length.toString(),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ..._activeSessions.map((session) => _buildActiveSessionCard(session)),
      ],
    );
  }

  Widget _buildSessionRequestCard(Map<String, dynamic> session) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.grey : Colors.black54;

    final studentName = session['userName'] ?? 'Student';
    final duration = session['duration'] ?? 60;
    final studyGoal = session['studyGoal'];
    final requestedAt = session['requestedAt']?.toDate();
    
    String timeAgo = 'Recently';
    if (requestedAt != null) {
      final diff = DateTime.now().difference(requestedAt);
      if (diff.inMinutes < 1) {
        timeAgo = 'Just now';
      } else if (diff.inMinutes < 60) {
        timeAgo = '${diff.inMinutes} min ago';
      } else {
        timeAgo = '${diff.inHours} hours ago';
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.orange.withOpacity(0.2),
          child: Text(
            studentName[0].toUpperCase(),
            style: const TextStyle(color: Colors.orange),
          ),
        ),
        title: Text(
          studentName,
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$duration min session • $timeAgo',
              style: TextStyle(color: subTextColor, fontSize: 12),
            ),
            if (studyGoal != null && studyGoal.isNotEmpty)
              Text(
                'Goal: $studyGoal',
                style: const TextStyle(color: Colors.orange, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.close, color: Colors.red, size: 20),
              onPressed: () => _respondToRequest(session['id'], false),
              tooltip: 'Reject',
            ),
            const SizedBox(width: 4),
            ElevatedButton(
              onPressed: () => _respondToRequest(session['id'], true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              child: const Text('Accept'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveSessionCard(Map<String, dynamic> session) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.grey : Colors.black54;

    final studentName = session['userName'] ?? 'Student';
    final startedAt = session['startedAt']?.toDate();
    final duration = session['duration'] ?? 60;
    
    String timeLeft = '';
    if (startedAt != null) {
      final endTime = startedAt.add(Duration(minutes: duration));
      final now = DateTime.now();
      if (now.isAfter(endTime)) {
        timeLeft = 'Session ended';
      } else {
        final diff = endTime.difference(now);
        final hours = diff.inHours;
        final minutes = diff.inMinutes.remainder(60);
        timeLeft = '${hours}h ${minutes}m left';
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.green.withOpacity(0.2),
          child: Text(
            studentName[0].toUpperCase(),
            style: const TextStyle(color: Colors.green),
          ),
        ),
        title: Text(
          studentName,
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '$timeLeft • ${session['lockedApps']?.length ?? 0} apps locked',
          style: TextStyle(color: subTextColor, fontSize: 12),
        ),
        trailing: ElevatedButton(
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          child: const Text('Manage'),
        ),
      ),
    );
  }

  /// Handles accepting or rejecting a session request.
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
      await _firestore
          .collection('companion_sessions')
          .doc(sessionId)
          .update({
            'status': 'REJECTED',
            'updatedAt': FieldValue.serverTimestamp(),
          });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session request rejected')),
        );
      }
    }
  }
}