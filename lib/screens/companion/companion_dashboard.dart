import 'dart:math';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:focus_mate/screens/companion/companion_control_page.dart';
import 'package:focus_mate/screens/schedule/schedule_approval_screen.dart';
import 'package:focus_mate/screens/companion/widgets/companion_header.dart';
import 'package:focus_mate/screens/companion/widgets/student_tile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:focus_mate/providers/user_provider.dart';
import 'package:focus_mate/theme/app_colors.dart';
import 'package:focus_mate/theme/app_theme.dart';
import 'package:focus_mate/core/notification_service.dart';
import 'package:focus_mate/core/theme_picker.dart';

/// Dashboard for companions (parents/partners) to manage linked students and sessions.
class CompanionDashboard extends ConsumerStatefulWidget {
  final Function onLogout;

  const CompanionDashboard({super.key, required this.onLogout});

  @override
  ConsumerState<CompanionDashboard> createState() => _CompanionDashboardState();
}

class _CompanionDashboardState extends ConsumerState<CompanionDashboard> {
  String get _userId => ref.read(currentUserIdProvider)!;
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

  bool _initialSessionLoaded = false;
  final Set<String> _initialUnlockLoaded = {};

  @override
  void initState() {
    super.initState();
    NotificationService().requestPermissions();
    _loadLinkCode();
    _listenForSessionRequests();
    _listenForActiveSessions();
    _listenForUserChanges();
    _loadExistingStudents(); // ← immediately start listeners for already-linked students
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

  /// Immediately starts real-time listeners for students that are already
  /// linked when the dashboard first opens. Without this, existing students
  /// only get listeners after _listenForUserChanges fires a change event.
  Future<void> _loadExistingStudents() async {
    try {
      final doc = await _firestore.collection('users').doc(_userId).get();
      if (!doc.exists || !mounted) return;
      final data = doc.data() as Map<String, dynamic>;
      final linkedSet = <String>{
        ...List<String>.from(data['linkedStudents'] ?? []),
        ...List<String>.from(data['linkedUsers'] ?? []),
      };
      for (var studentId in linkedSet) {
        if (!_studentScheduleSubscriptions.containsKey(studentId)) {
          _startStudentListeners(studentId);
        }
      }
    } catch (e) {
      debugPrint('Error loading existing students: $e');
    }
  }

  /// Unlinks a student from this companion.
  Future<void> _unlinkStudent(String studentId, String studentName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1E293B)
            : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Unlink $studentName?',
            style: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black87)),
        content: Text(
          'This will remove your connection with $studentName. They will need to re-link using your code.',
          style: TextStyle(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white70
                  : Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Unlink', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      final batch = _firestore.batch();

      // Remove student from companion's lists
      final companionRef = _firestore.collection('users').doc(_userId);
      batch.update(companionRef, {
        'linkedStudents': FieldValue.arrayRemove([studentId]),
        'linkedUsers': FieldValue.arrayRemove([studentId]),
      });

      // Remove companion from student's profile
      final studentRef = _firestore.collection('users').doc(studentId);
      batch.update(studentRef, {
        'linkedCompanion': FieldValue.delete(),
        'linkedParent': FieldValue.delete(),
      });

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$studentName has been unlinked.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _listenForUserChanges() {
    _userDocSubscription = _firestore
        .collection('users')
        .doc(_userId)
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
          final staleIds = _studentScheduleSubscriptions.keys
              .where((id) => !currentStudentIds.contains(id))
              .toList();
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

    // 2. Listen for Unlock Requests (top-level collection, unified with Parent flow)
    _studentUnlockSubscriptions[studentId] = _firestore
        .collection('unlock_requests')
        .where('parentId', isEqualTo: _userId)
        .where('studentId', isEqualTo: studentId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snapshot) async {
          if (!_initialUnlockLoaded.contains(studentId)) {
            _initialUnlockLoaded.add(studentId);
          } else {
            for (var change in snapshot.docChanges) {
              if (change.type == DocumentChangeType.added) {
                final studentName = change.doc.data()?['studentName'] ?? 'A student';
                NotificationService().showInstantNotification(
                  id: change.doc.id.hashCode,
                  title: 'New Unlock Request',
                  body: '$studentName has requested to unlock an app.',
                );
              }
            }
          }
          _updatePendingUnlockRequests(studentId, snapshot.docs);
        });
  }

  // Intermediate storage per student to simplify merging
  final Map<String, List<Map<String, dynamic>>> _perStudentPendingSchedules =
      {};
  final Map<String, List<Map<String, dynamic>>> _perStudentActiveSchedules = {};
  final Map<String, List<Map<String, dynamic>>> _perStudentUnlocks = {};

  Future<void> _updateSchedules(
    String studentId,
    List<QueryDocumentSnapshot> docs,
  ) async {
    if (!mounted) return;
    String userName = "Student";
    try {
      final userDoc = await _firestore.collection('users').doc(studentId).get();
      userName = userDoc.data()?['name'] ?? "Student";
    } catch (_) {}

    final allSchedules = docs.map((doc) {
      return <String, dynamic>{
        'id': doc.id,
        'userId': studentId,
        'userName': userName,
        ...(doc.data() as Map<String, dynamic>),
      };
    }).toList();

    if (!mounted) return;

    setState(() {
      _perStudentPendingSchedules[studentId] = allSchedules
          .where((s) => s['status'] == 'requested')
          .toList();
      _perStudentActiveSchedules[studentId] = allSchedules
          .where((s) => s['status'] == 'active')
          .toList();
      _pendingSchedules = _perStudentPendingSchedules.values
          .expand((x) => x)
          .toList();
      _activeSchedules = _perStudentActiveSchedules.values
          .expand((x) => x)
          .toList();
    });
  }

  Future<void> _updatePendingUnlockRequests(
    String studentId,
    List<QueryDocumentSnapshot> docs,
  ) async {
    if (!mounted) return;
    String userName = "Student";
    try {
      final userDoc = await _firestore.collection('users').doc(studentId).get();
      userName = userDoc.data()?['name'] ?? "Student";
    } catch (_) {}

    final requests = docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return {
        'id': doc.id,
        'userId': data['studentId'] ?? studentId,
        'userName': data['studentName'] ?? userName,
        ...data,
      };
    }).toList();

    setState(() {
      _perStudentUnlocks[studentId] = requests;
      _pendingUnlockRequests = _perStudentUnlocks.values
          .expand((x) => x)
          .toList();
    });
  }

  /// Listens for incoming session requests, deduplicating to show only the latest per user.
  void _listenForSessionRequests() {
    _firestore
        .collection('companion_sessions')
        .where('companionId', isEqualTo: _userId)
        .where('status', isEqualTo: 'REQUESTED')
        .snapshots()
        .listen(
          (snapshot) {
            if (mounted) {
              // Deduplicate requests: keep latest per user
              final Map<String, Map<String, dynamic>> latestRequests = {};

              for (final doc in snapshot.docs) {
                final data = doc.data();
                final userId = data['userId'];

                if (!latestRequests.containsKey(userId)) {
                  latestRequests[userId] = {'id': doc.id, ...data};
                } else {
                  // Keep the newer one if duplicate exists
                  final existing = latestRequests[userId]!;
                  final Timestamp? newTime = data['requestedAt'];
                  final Timestamp? oldTime = existing['requestedAt'];

                  if (newTime != null &&
                      (oldTime == null || newTime.compareTo(oldTime) > 0)) {
                    latestRequests[userId] = {'id': doc.id, ...data};
                  }
                }
              }

              if (!_initialSessionLoaded) {
                _initialSessionLoaded = true;
              } else {
                for (var change in snapshot.docChanges) {
                  if (change.type == DocumentChangeType.added) {
                    final studentName = change.doc.data()?['userName'] ?? 'A student';
                    NotificationService().showInstantNotification(
                      id: change.doc.id.hashCode,
                      title: 'New Study Session Request',
                      body: '$studentName has requested a new study session.',
                    );
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
          },
          onError: (e) {
            debugPrint("Error listening for requests: $e");
          },
        );
  }

  /// Listens for currently active sessions managed by this companion.
  void _listenForActiveSessions() {
    _firestore
        .collection('companion_sessions')
        .where('companionId', isEqualTo: _userId)
        .where('status', isEqualTo: 'ACTIVE')
        .snapshots()
        .listen((snapshot) {
          if (mounted) {
            setState(() {
              _activeSessions = snapshot.docs.map((doc) {
                final data = doc.data();
                return {'id': doc.id, ...data};
              }).toList();
            });
          }
        });
  }

  /// Loads the companion's unique link code from Firestore.
  Future<void> _loadLinkCode() async {
    final userState = ref.read(userProvider);
    final linkCodeFromProvider = userState.when(
      data: (u) => u?.toMap()['linkCode'],
      loading: () => null,
      error: (_, __) => null,
    );

    if (linkCodeFromProvider != null) {
      setState(() {
        linkCode = linkCodeFromProvider;
      });
      return;
    }

    final doc = await _firestore.collection('users').doc(_userId).get();
    setState(() {
      linkCode = doc.data()?['linkCode'];
    });
  }

  /// Generates a random 8-character alphanumeric code using a secure RNG.
  String _generateCode() {
    final rng = Random.secure();
    return List.generate(6, (index) => rng.nextInt(10).toString()).join();
  }

  /// Generates a new link code and updates it in Firestore with a 24-hour expiration.
  Future<void> _refreshCode() async {
    final code = _generateCode();
    await _firestore.collection('users').doc(_userId).update({
      'linkCode': code,
      'linkCodeExpiresAt': Timestamp.fromDate(
        DateTime.now().add(const Duration(hours: 24)),
      ),
    });
    setState(() {
      linkCode = code;
    });
  }

  /// Shows the settings bottom sheet with theme + logout options.
  void _showSettingsSheet(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1E1E2E) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final accentColor = isDark ? Colors.cyanAccent : Colors.blueAccent;

    showModalBottomSheet(
      context: context,
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Settings',
                style: TextStyle(
                  color: textColor,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: Icon(Icons.palette_outlined, color: accentColor),
                title: Text('Switch Theme', style: TextStyle(color: textColor)),
                subtitle: Text(
                  'Light · Dark · System',
                  style: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  showThemePicker(context, ref);
                },
              ),
              Divider(color: isDark ? Colors.white12 : Colors.black12, height: 1),
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: const Icon(Icons.logout, color: Colors.redAccent),
                title: Text('Log Out', style: TextStyle(color: textColor)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  widget.onLogout();
                },
              ),
            ],
          ),
        ),
      ),
    );
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
          "Companion Dashboard",
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.bold,
            fontSize: 22.sp,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () => _showSettingsSheet(context),
            icon: Icon(Icons.settings_outlined, color: textColor, size: 24.sp),
          ),
        ],
      ),
      body: Container(
        decoration: AppTheme.screenBackground(
          context,
          AppColors.roleGradients['companion']!,
        ),
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              // Link Code Section
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: CompanionHeader(
                    linkCode: linkCode,
                    onRefreshCode: _refreshCode,
                  ),
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
                      const Icon(
                        Icons.sync,
                        size: 16,
                        color: Colors.blueAccent,
                      ),
                    ],
                  ),
                ),
              ),

              // Connected Students List
              StreamBuilder<DocumentSnapshot>(
                stream: _firestore.collection('users').doc(_userId).snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SliverToBoxAdapter(
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  if (!snapshot.hasData || !snapshot.data!.exists) {
                    return const SliverToBoxAdapter(
                      child: Center(child: Text("No connection data found.")),
                    );
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
                            Icon(
                              Icons.child_care_rounded,
                              size: 64,
                              color: Colors.grey.withValues(alpha: 0.3),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              "No children linked yet.\nShare your code to get started!",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final studentId = linked[index];
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: StreamBuilder<DocumentSnapshot>(
                          stream: _firestore.collection('users').doc(studentId).snapshots(),
                          builder: (context, stuSnap) {
                            final studentName = stuSnap.hasData && stuSnap.data!.exists
                                ? ((stuSnap.data!.data() as Map<String, dynamic>)['name'] ?? 'Student')
                                : 'Student';
                            return StudentTile(
                                  studentId: studentId,
                                  isDark: isDark,
                                  companionId: _userId,
                                );
                          },
                        ),
                      );
                    }, childCount: linked.length),
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

  Widget _buildSessionRequestsSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
          "Session Requests",
          Icons.notifications_active,
          Colors.orange,
          isDark,
        ),
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
        _buildSectionTitle(
          "Active Sessions",
          Icons.play_circle_outline,
          Colors.green,
          isDark,
        ),
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
        _buildSectionTitle(
          "Active App Lock Schedules",
          Icons.lock,
          Colors.amber,
          isDark,
        ),
        const SizedBox(height: 12),
        ..._activeSchedules.map(
          (schedule) => _buildActiveScheduleCard(schedule),
        ),
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
        color: Colors.amber.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.amber.withValues(alpha: 0.1),
            child: Text(
              studentName[0].toUpperCase(),
              style: const TextStyle(color: Colors.amber),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "$studentName - ${schedule['name']}",
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  "${(schedule['lockedApps'] as List?)?.length ?? 0} apps locked",
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
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
      await _firestore
          .collection('users')
          .doc(studentId)
          .collection('schedules')
          .doc(scheduleId)
          .update({'status': 'inactive'});
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Schedule stopped")));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Widget _buildScheduleRequestsSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
          "Schedule Requests",
          Icons.schedule,
          Colors.amber,
          isDark,
        ),
        const SizedBox(height: 12),
        ..._pendingSchedules.map(
          (schedule) => _buildScheduleRequestCard(schedule),
        ),
      ],
    );
  }

  Widget _buildUnlockRequestsSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
          "App Unlock Requests",
          Icons.lock_open,
          Colors.purpleAccent,
          isDark,
        ),
        const SizedBox(height: 12),
        ..._pendingUnlockRequests.map((req) => _buildUnlockRequestCard(req)),
      ],
    );
  }

  Widget _buildSectionTitle(
    String title,
    IconData icon,
    Color color,
    bool isDark,
  ) {
    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
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
        color: Colors.orange.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.orange.withValues(alpha: 0.1),
            child: Text(
              studentName[0].toUpperCase(),
              style: const TextStyle(color: Colors.orange),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  studentName,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  session['studyGoal'] != null && session['studyGoal'].toString().trim().isNotEmpty
                      ? '${session['studyGoal']} (${session['duration'] ?? 60}m)'
                      : '${session['duration'] ?? 60}m App Lock request',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
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
        color: Colors.amber.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.amber.withValues(alpha: 0.1),
            child: Text(
              studentName[0].toUpperCase(),
              style: const TextStyle(color: Colors.amber),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  studentName,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'New Schedule: $scheduleName',
                  style: TextStyle(
                    color: Colors.amber,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
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
                    companionId: _userId,
                  ),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
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
        color: Colors.green.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.green.withValues(alpha: 0.1),
            child: Text(
              studentName[0].toUpperCase(),
              style: const TextStyle(color: Colors.green),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  studentName,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  'Session In-Progress',
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
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
          builder: (context) =>
              CompanionControlPage(sessionId: sessionId, companionId: _userId),
        ),
      );
    } else {
      await _firestore.collection('companion_sessions').doc(sessionId).update({
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

  Future<void> _approveUnlockRequest(Map<String, dynamic> req) async {
    final userId = req['userId'];
    final reqId = req['id'];
    final packageName = req['packageName'];

    // Update request status (top-level collection)
    await _firestore.collection('unlock_requests').doc(reqId).update({
      'status': 'approved',
    });

    if (packageName == 'all') {
      // Suspend all locks: Quick locks, active schedules, and companion sessions
      final batch = _firestore.batch();

      final userRef = _firestore.collection('users').doc(userId);
      batch.update(userRef, {'lockedApps': [], 'lockEndTime': null});

      final sessionsSnap = await _firestore
          .collection('companion_sessions')
          .where('userId', isEqualTo: userId)
          .where('status', isEqualTo: 'ACTIVE')
          .get();
      for (var doc in sessionsSnap.docs) {
        batch.update(doc.reference, {'status': 'ENDED'});
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("App unlocked successfully")),
      );
    }
  }

  Future<void> _denyUnlockRequest(Map<String, dynamic> req) async {
    final reqId = req['id'];
    await _firestore.collection('unlock_requests').doc(reqId).update({
      'status': 'denied',
    });
  }

  Widget _buildUnlockRequestCard(Map<String, dynamic> req) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final studentName = req['userName'] ?? 'Student';
    final appName = req['appName'] ?? 'Unknown App';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.purple.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.purple.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.purple.withValues(alpha: 0.1),
            child: Text(
              studentName[0].toUpperCase(),
              style: const TextStyle(color: Colors.purple),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  studentName,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Unlock: $appName',
                  style: const TextStyle(
                    color: Colors.purpleAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: const Text("Unlock"),
          ),
        ],
      ),
    );
  }
}
