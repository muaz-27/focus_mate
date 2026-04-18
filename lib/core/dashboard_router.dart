import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:focus_mate/core/models/user_model.dart';
import 'package:focus_mate/core/auth_service.dart';
import 'package:focus_mate/dashboard/companion_dashboard.dart';
import 'package:focus_mate/dashboard/parent_dashboard.dart';
import 'package:focus_mate/dashboard/student_dashboard.dart';
import 'package:focus_mate/dashboard/companion_controlled_page.dart';

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

  void handleLogout(BuildContext context) async {
    await AuthService().signOut();
    // AuthGate will automatically handle the navigation
  }

  void handleStartSession(String mode) {
    // implement session start logic if needed locally
    debugPrint("Starting session in $mode mode");
  }

  @override
  Widget build(BuildContext context) {
    final userData = user.toMap();
    userData['id'] = user.id; 

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
            final sessionId = snapshot.data!.docs.first.id;
            return CompanionControlledPage(
              sessionId: sessionId,
              userId: user.id,
            );
          }
          
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

    switch (user.role) {
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
    }
  }
}