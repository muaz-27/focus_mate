import 'package:flutter/material.dart';
import 'package:focus_mate/dashboard/companion_dashboard.dart';
import 'package:focus_mate/dashboard/parent_dashboard.dart';
import 'package:focus_mate/dashboard/student_dashboard.dart';

enum UserRole { user, companion, parent }

class DashboardRouter extends StatelessWidget {
  final UserRole role;
  final Map<String, dynamic> userData;
  final int studyTime;
  final int dailyGoal;
  final bool activeSession;
  final bool companionActive;
  final bool appsUnlocked;

  const DashboardRouter({
    super.key,
    required this.role,
    required this.userData,
    required this.studyTime,
    required this.dailyGoal,
    required this.activeSession,
    required this.companionActive,
    required this.appsUnlocked,
  });

  void handleLogout(BuildContext context) {
    // implement logout
  }

  void handleStartSession(String mode) {
    // implement session start
  }

  @override
  Widget build(BuildContext context) {
    switch (role) {
      case UserRole.user:
        return StudentDashboard(
          userData: userData,
          studyTime: studyTime,
          dailyGoal: dailyGoal,
          activeSession: activeSession,
          companionActive: companionActive,
          appsUnlocked: appsUnlocked,
          onLogout: () => handleLogout(context),
          onStartSession: handleStartSession,
        );
      case UserRole.companion:
        return CompanionDashboard(
          userData: userData,
          onLogout: () => handleLogout(context),
        );
      case UserRole.parent:
        return ParentDashboard(
          userData: userData,
          onLogout: () => handleLogout(context),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
