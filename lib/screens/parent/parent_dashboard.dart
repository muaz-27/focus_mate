import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:focus_mate/screens/analytics/analytics_screen.dart';
import 'package:focus_mate/screens/analytics/snapshots_screen.dart';
import 'package:focus_mate/screens/companion/companion_control_page.dart';
import 'package:focus_mate/screens/locks/remote_app_lock_screen.dart';
import 'package:focus_mate/screens/parent/parent_child_control_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:focus_mate/providers/user_provider.dart';
import 'package:focus_mate/theme/app_colors.dart';
import 'package:focus_mate/theme/app_theme.dart';

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

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          "Parent Dashboard",
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 22.sp),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: () => widget.onLogout(),
            icon: Icon(Icons.logout, color: Colors.redAccent, size: 24.sp),
          ),
        ],
      ),
      body: Container(
        decoration: AppTheme.screenBackground(context, AppColors.roleGradients['parent']!),
        child: SafeArea(
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
                
                SliverToBoxAdapter(child: SizedBox(height: 40.h)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard(bool isDark) {
    final cardTextColor = isDark ? Colors.white : Colors.black87;
    final cardSubTextColor = isDark ? Colors.white70 : Colors.black54;
    final iconBtnBg = isDark ? Colors.white.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.08);
    final iconBtnColor = isDark ? Colors.white : Colors.black87;

    return Container(
      padding: EdgeInsets.all(24.w),
      decoration: AppTheme.cardContainer(context, AppColors.roleGradients['parent']!),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Parent Link Code",
            style: TextStyle(color: cardSubTextColor, fontSize: 14.sp, fontWeight: FontWeight.w500),
          ),
          SizedBox(height: 12.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                linkCode ?? "...",
                style: TextStyle(
                  color: cardTextColor,
                  fontSize: 36.sp,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                ),
              ),
              Row(
                children: [
                  _glassIconButton(Icons.refresh, _refreshCode, iconBtnBg, iconBtnColor),
                  SizedBox(width: 8.w),
                  _glassIconButton(Icons.copy, () {
                    if (linkCode != null) {
                      Clipboard.setData(ClipboardData(text: linkCode!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Code copied!")),
                      );
                    }
                  }, iconBtnBg, iconBtnColor),
                ],
              ),
            ],
          ),
          SizedBox(height: 12.h),
          Text(
            "Link your child's device by entering this code in their Focus Mate app.",
            style: TextStyle(color: cardSubTextColor, fontSize: 13.sp),
          ),
        ],
      ),
    );
  }

  Widget _glassIconButton(IconData icon, VoidCallback onPressed, Color bgColor, Color iconColor) {
    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: IconButton(
        icon: Icon(icon, color: iconColor, size: 20),
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
    // Use StreamBuilder so isOnline updates live without manual refresh.
    return StreamBuilder<DocumentSnapshot>(
      stream: _firestore.collection('users').doc(studentId).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return Container(
            height: 120.h,
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white70,
              borderRadius: BorderRadius.circular(20.r),
            ),
            child: const Center(
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          );
        }

        final student = snap.data!.data() as Map<String, dynamic>? ?? {};
        final studentName = (student['name'] as String?) ?? "Unknown";
        // deviceOnline is set by the child's heartbeat. Also validate lastSeen
        // freshness (< 3 min) so the badge goes Offline after the device goes dark.
        final bool rawOnline = (student['deviceOnline'] as bool?) ?? false;
        final Timestamp? lastSeenTs = student['lastSeen'] as Timestamp?;
        final bool recentHeartbeat = lastSeenTs != null &&
            DateTime.now().difference(lastSeenTs.toDate()).inMinutes < 3;
        final isOnline = rawOnline && recentHeartbeat;
        final studyTime = student['studyTime'] ?? 0;
        final level = student['level'] ?? 1;
        final lockedApps = List<String>.from(student['lockedApps'] ?? []);

        return Container(
          padding: EdgeInsets.all(16.w),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
            borderRadius: BorderRadius.circular(20.r),
            border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05)),
            boxShadow: [
              if (!isDark)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: Column(
            children: [
              // Top row: Avatar + Name + Status badge
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // --- Avatar with online dot ---
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 24.r,
                        backgroundColor: Colors.pinkAccent.withValues(alpha: 0.1),
                        child: Text(
                          studentName[0].toUpperCase(),
                          style: TextStyle(color: Colors.pinkAccent, fontWeight: FontWeight.bold, fontSize: 20.sp),
                        ),
                      ),
                      Positioned(
                        right: 0, bottom: 0,
                        child: Container(
                          width: 13.w, height: 13.h,
                          decoration: BoxDecoration(
                            color: isOnline ? Colors.green : Colors.grey,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDark ? const Color(0xFF1E293B) : Colors.white,
                              width: 2.w,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(width: 12.w),
                  // --- Name + stats (takes remaining space) ---
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          studentName,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 15.sp,
                          ),
                        ),
                        SizedBox(height: 3.h),
                        // Stats row — clipped so it never overflows
                        Row(
                          children: [
                            Icon(Icons.star_rounded, size: 13.sp, color: Colors.amber.shade600),
                            SizedBox(width: 3.w),
                            Text(
                              "Lv $level",
                              style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 11.sp),
                            ),
                            SizedBox(width: 8.w),
                            Icon(Icons.timer_outlined, size: 12.sp, color: Colors.blueAccent.withValues(alpha: 0.7)),
                            SizedBox(width: 3.w),
                            Flexible(
                              child: Text(
                                "${studyTime}m today",
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 11.sp),
                              ),
                            ),
                            if (lockedApps.isNotEmpty) ...[
                              SizedBox(width: 6.w),
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 5.w, vertical: 2.h),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(5.r),
                                ),
                                child: Text(
                                  "${lockedApps.length}🔒",
                                  style: TextStyle(color: Colors.redAccent.shade100, fontSize: 10.sp, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 8.w),
                  // --- ONLINE / OFFLINE badge (fixed width to prevent push) ---
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 4.h),
                    decoration: BoxDecoration(
                      color: isOnline
                          ? Colors.green.withValues(alpha: 0.12)
                          : Colors.grey.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Text(
                      isOnline ? "ONLINE" : "OFFLINE",
                      style: TextStyle(
                        color: isOnline ? Colors.green : Colors.grey,
                        fontSize: 9.sp,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 14.h),
              Container(height: 1, color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade200),
              SizedBox(height: 12.h),
              // Bottom row: Quick action buttons
              Row(
                children: [
                  _buildStudentAction(
                    icon: Icons.dashboard_outlined,
                    label: "Control",
                    color: Colors.pinkAccent,
                    isDark: isDark,
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => ParentChildControlPage(studentId: studentId, studentName: studentName),
                      ));
                    },
                  ),
                  SizedBox(width: 8.w),
                  _buildStudentAction(
                    icon: Icons.analytics_outlined,
                    label: "Analytics",
                    color: Colors.blueAccent,
                    isDark: isDark,
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => AnalyticsScreen(userId: studentId, userName: studentName),
                      ));
                    },
                  ),
                  SizedBox(width: 8.w),
                  _buildStudentAction(
                    icon: Icons.lock_outline,
                    label: "Locks",
                    color: Colors.orangeAccent,
                    isDark: isDark,
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => RemoteAppLockScreen(studentId: studentId, studentName: studentName),
                      ));
                    },
                  ),
                  SizedBox(width: 8.w),
                  _buildStudentAction(
                    icon: Icons.camera_alt_outlined,
                    label: "Snaps",
                    color: Colors.indigoAccent,
                    isDark: isDark,
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => SnapshotsScreen(studentId: studentId, studentName: studentName),
                      ));
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStudentAction({
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12.r),
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 10.h),
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.1 : 0.08),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: color.withValues(alpha: isDark ? 0.15 : 0.12)),
            ),
            child: Column(
              children: [
                Icon(icon, color: color, size: 20.sp),
                SizedBox(height: 4.h),
                Text(label, style: TextStyle(color: isDark ? Colors.grey[300] : Colors.grey[700], fontSize: 11.sp, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
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
