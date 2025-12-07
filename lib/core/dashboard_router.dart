import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // ADD THIS IMPORT
import 'package:focus_mate/core/models/user_model.dart';
import 'package:focus_mate/dashboard/companion_dashboard.dart';
import 'package:focus_mate/dashboard/parent_dashboard.dart';
import 'package:focus_mate/dashboard/student_dashboard.dart';
import 'package:focus_mate/dashboard/companion_controlled_page.dart'; // ADD THIS IMPORT

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
    final userData = user.toMap();
    // Add ID explicitly as it might not be in toMap depending on implementation
    userData['id'] = user.id; 

    // Check for active companion session FIRST (only for students)
    if (user.role == UserRole.user) {
      return FutureBuilder<QuerySnapshot>(
        future: FirebaseFirestore.instance
            .collection('companion_sessions')
            .where('userId', isEqualTo: user.id)
            .where('status', isEqualTo: 'ACTIVE')
            .limit(1)
            .get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              backgroundColor: Color(0xFF121212),
              body: Center(child: CircularProgressIndicator(color: Colors.cyanAccent)),
            );
          }
          
          if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
            // User has active companion session
            final sessionId = snapshot.data!.docs.first.id;
            return CompanionControlledPage(
              sessionId: sessionId,
              userId: user.id,
            );
          }
          
          // No active companion session, proceed to normal student dashboard
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
        },
      );
    }

    // For non-student roles (companion/parent), use normal routing
    switch (user.role) {
      case UserRole.user:
        // This case is already handled above, but keeping for completeness
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