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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Confirm Logout', style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure you want to sign out?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
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

        final userData = user.toMap();
        userData['id'] = user.id;

        // Student role — check for active companion session
        if (user.role == UserRole.user) {
          final sessionAsync = ref.watch(activeCompanionSessionProvider);

          return sessionAsync.when(
            loading: () => const Scaffold(
              backgroundColor: Color(0xFF121212),
              body: Center(child: CircularProgressIndicator(color: Colors.cyanAccent)),
            ),
            error: (_, __) => _buildStudentDashboard(context, ref, user, userData),
            data: (session) {
              if (session != null) {
                return CompanionControlledPage(
                  sessionId: session['id'],
                  userId: user.id,
                );
              }
              return _buildStudentDashboard(context, ref, user, userData);
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
            return _buildStudentDashboard(context, ref, user, userData);
        }
      },
    );
  }

  Widget _buildStudentDashboard(
    BuildContext context,
    WidgetRef ref,
    UserModel user,
    Map<String, dynamic> userData,
  ) {
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
  }
}