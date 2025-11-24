import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';


import 'firebase_options.dart';
import 'auth/auth_screen.dart';
import 'core/dashboard_router.dart'; // This contains UserRole enum

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
      home: const AuthGate(), 
    );
  }
}

// ---------------------------------------------------------------------------
// 🔹 AUTH GATE (Persistent Login)
// ---------------------------------------------------------------------------
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        
        // 1. Loading
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // 2. Not Logged In
        if (!snapshot.hasData) {
          return AuthScreen(onAuthComplete: (_, __) {});
        }

        // 3. Logged In -> Fetch Data
        User currentUser = snapshot.data!;

        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance.collection('users').doc(currentUser.uid).get(),
          builder: (context, userSnapshot) {
            
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
              FirebaseAuth.instance.signOut();
              return AuthScreen(onAuthComplete: (_,__) {});
            }

            // 4. Prepare Data
            Map<String, dynamic> userData = userSnapshot.data!.data() as Map<String, dynamic>;
            userData['id'] = currentUser.uid;

            // 🔹 FIX: Map the role string to your UserRole enum
            String roleStr = userData['role'] ?? 'user';
            
            // Logic: If it says 'companion', use companion. Otherwise, default to 'user' (Student)
            UserRole role = (roleStr == 'companion') ? UserRole.companion : UserRole.user;

            // 5. Open Dashboard
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