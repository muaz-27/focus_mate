import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focus_mate/core/models/user_model.dart';
import 'package:focus_mate/providers/auth_provider.dart';
import 'package:focus_mate/providers/user_provider.dart';
import 'package:focus_mate/providers/companion_session_provider.dart';
import 'package:focus_mate/screens/companion/companion_dashboard.dart';
import 'package:focus_mate/screens/parent/parent_dashboard.dart';
import 'package:focus_mate/screens/student/student_dashboard.dart';
import 'package:focus_mate/screens/companion/companion_controlled_page.dart';

/// Routes the authenticated user to the correct dashboard based on their role.
///
/// Reads all state from Riverpod providers — no constructor parameters needed.
/// For student users, watches [activeCompanionSessionProvider] to auto-redirect
/// to [CompanionControlledPage] when a companion session is active.
class DashboardRouter extends ConsumerWidget {
  const DashboardRouter({super.key});

  void _handleLogout(BuildContext context, WidgetRef ref) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final userAsync = ref.read(userProvider);
    final user = userAsync.when(
      data: (u) => u,
      loading: () => null,
      error: (_, __) => null,
    );

    // Block logout for students with active locks or sessions
    if (user != null && user.role == UserRole.user) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.id)
            .get();

        if (doc.exists) {
          final data = doc.data()!;
          final lockedApps = List<String>.from(data['lockedApps'] ?? []);
          final lockEndTime = data['lockEndTime'] != null
              ? (data['lockEndTime'] as Timestamp).toDate()
              : null;

          // Check if apps are currently locked (and lock hasn't expired)
          final bool hasActiveLock = lockedApps.isNotEmpty &&
              (lockEndTime == null || DateTime.now().isBefore(lockEndTime));

          // Check for active companion sessions
          final sessionQuery = await FirebaseFirestore.instance
              .collection('companion_sessions')
              .where('userId', isEqualTo: user.id)
              .where('status', whereIn: ['REQUESTED', 'ACTIVE'])
              .limit(1)
              .get();
          final bool hasActiveSession = sessionQuery.docs.isNotEmpty;

          if (hasActiveLock || hasActiveSession) {
            if (context.mounted) {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: Row(
                    children: [
                      Icon(Icons.lock, color: Colors.redAccent, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        'Logout Blocked',
                        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                      ),
                    ],
                  ),
                  content: Text(
                    hasActiveSession
                        ? 'You cannot log out while a study session is active. Complete your quiz to unlock apps first.'
                        : 'You cannot log out while apps are locked. Complete your quiz to unlock apps first.',
                    style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
                  ),
                  actions: [
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark ? Colors.white24 : Colors.grey.shade200,
                        foregroundColor: isDark ? Colors.white : Colors.black87,
                      ),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            }
            return; // Block logout
          }
        }
      } catch (e) {
        debugPrint('FocusMate: Error checking lock state for logout: $e');
        // On error, fall through to allow logout
      }
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Confirm Logout', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
        content: Text('Are you sure you want to sign out?', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: isDark ? Colors.grey : Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Logout', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(authServiceProvider).signOut();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userProvider);

    return userAsync.when(
      loading: () => const Scaffold(
        backgroundColor: Color(0xFF121212),
        body: Center(child: CircularProgressIndicator(color: Colors.cyanAccent)),
      ),
      error: (_, __) => const Scaffold(
        body: Center(child: Text('Error loading user data', style: TextStyle(color: Colors.white))),
      ),
      data: (user) {
        if (user == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Student role — check for active companion session
        if (user.role == UserRole.user) {
          final sessionAsync = ref.watch(activeCompanionSessionProvider);

          return sessionAsync.when(
            loading: () => const Scaffold(
              backgroundColor: Color(0xFF121212),
              body: Center(child: CircularProgressIndicator(color: Colors.cyanAccent)),
            ),
            error: (_, __) => _buildStudentDashboard(context, ref, user),
            data: (session) {
              if (session != null) {
                return CompanionControlledPage(
                  sessionId: session['id'],
                  userId: user.id,
                );
              }
              return _buildStudentDashboard(context, ref, user);
            },
          );
        }

        // Non-student roles
        switch (user.role) {
          case UserRole.companion:
            return CompanionDashboard(
              onLogout: () => _handleLogout(context, ref),
            );
          case UserRole.parent:
            return ParentDashboard(
              onLogout: () => _handleLogout(context, ref),
            );
          default:
            return _buildStudentDashboard(context, ref, user);
        }
      },
    );
  }

  /// Builds the student dashboard with raw Firestore data.
  ///
  /// Uses a FutureBuilder to fetch the raw Firestore document which includes
  /// fields not in UserModel (lockedApps, lockEndTime, linkedCompanionRole, etc.)
  /// This ensures locks are enforced immediately on login.
  Widget _buildStudentDashboard(
    BuildContext context,
    WidgetRef ref,
    UserModel user,
  ) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(user.id).get(),
      builder: (context, snapshot) {
        // Build a base userData map from UserModel
        final Map<String, dynamic> userData = user.toMap();
        userData['id'] = user.id;

        // Overlay raw Firestore data to include lockedApps, lockEndTime, etc.
        if (snapshot.hasData && snapshot.data!.exists) {
          final rawData = snapshot.data!.data() as Map<String, dynamic>;
          // Merge critical fields that UserModel.toMap() doesn't include
          userData['lockedApps'] = rawData['lockedApps'];
          userData['lockEndTime'] = rawData['lockEndTime'];
          userData['linkedCompanionRole'] = rawData['linkedCompanionRole'];
          userData['companionName'] = rawData['companionName'];
          userData['snapshotRequest'] = rawData['snapshotRequest'];
          userData['linkCode'] = rawData['linkCode'];
        }

        return StudentDashboard(
          userData: userData,
          studyTime: user.studyTime,
          dailyGoal: user.dailyGoal,
          activeSession: false,
          companionActive: user.linkedCompanion != null,
          appsUnlocked: false,
          onLogout: () => _handleLogout(context, ref),
          onStartSession: (_) {},
        );
      },
    );
  }
}