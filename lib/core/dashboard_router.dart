import 'package:flutter/material.dart';
import 'package:focus_mate/core/models/user_model.dart';
import 'package:focus_mate/dashboard/companion_dashboard.dart';
import 'package:focus_mate/dashboard/parent_dashboard.dart';
import 'package:focus_mate/dashboard/student_dashboard.dart';

class DashboardRouter extends StatelessWidget {
  final UserModel user;
  final bool activeSession;
  final bool companionActive;
  final bool appsUnlocked;

  const DashboardRouter({
    super.key,
    required this.user,
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
    // Convert UserModel to Map for legacy dashboards
    // TODO: Refactor dashboards to use UserModel directly
    final userData = user.toMap();
    // Add ID explicitly as it might not be in toMap depending on implementation
    userData['id'] = user.id; 

    switch (user.role) {
      case UserRole.user:
        return StudentDashboard(
          userData: userData,
          studyTime: user.studyTime,
          dailyGoal: user.dailyGoal,
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
    }
  }
}
