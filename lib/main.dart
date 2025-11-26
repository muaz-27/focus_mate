import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// 🔹 IMPORTS
import 'firebase_options.dart';
import 'auth/auth_screen.dart';
import 'core/dashboard_router.dart';



Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const FocusMateApp());
}

class FocusMateApp extends StatelessWidget {
  const FocusMateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FocusMate',
      theme: ThemeData.dark(useMaterial3: true),
      home: const AuthGate(), // Persistent Login Logic
    );
  }
}

// ---------------------------------------------------------------------------
// 🔹 AUTH GATE (Checks Login Status & Routes to Dashboard)
// ---------------------------------------------------------------------------
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      // 1. Listen to Auth Changes
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        
        // Loading...
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        // Not Logged In -> Show Auth Screen
        if (!snapshot.hasData) {
          return AuthScreen(onAuthComplete: (_, __) {});
        }

        // Logged In -> Fetch User Data
        User currentUser = snapshot.data!;

        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance.collection('users').doc(currentUser.uid).get(),
          builder: (context, userSnapshot) {
            
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }

            // Safety Check: Auth exists but Data is missing
            if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
              FirebaseAuth.instance.signOut();
              return AuthScreen(onAuthComplete: (_,__) {});
            }

            // Get Data
            Map<String, dynamic> userData = userSnapshot.data!.data() as Map<String, dynamic>;
            userData['id'] = currentUser.uid;

            // Determine Role
            String roleStr = userData['role'] ?? 'user';
            UserRole role = (roleStr == 'companion') ? UserRole.companion : UserRole.user;

            // Route to Correct Dashboard
            return DashboardRouter(
              role: role,
              userData: userData,
              studyTime: userData['studyTime'] ?? 0,
              dailyGoal: userData['dailyGoal'] ?? 120,
              activeSession: false,
              companionActive: userData['linkedCompanion'] != null,
              appsUnlocked: false,
            );
          },
        );
      },
    );
  }
}