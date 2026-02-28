import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:focus_mate/core/auth_service.dart';
import 'package:focus_mate/core/models/user_model.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// 🔹 IMPORTS
import 'firebase_options.dart';
import 'auth/auth_screen.dart';
import 'core/dashboard_router.dart';
import 'theme/light_theme.dart';
import 'theme/dark_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: ".env");
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    }
  } catch (e, stacktrace) {
    debugPrint("Initialization failed: $e\n$stacktrace");
  }
  runApp(const FocusMateApp());
}

class FocusMateApp extends StatelessWidget {
  const FocusMateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FocusMate',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.system,
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

        return FutureBuilder<UserModel?>(
          future: AuthService().getUserData(currentUser.uid),
          builder: (context, userSnapshot) {
            
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }

            // Safety Check: Auth exists but Data is missing
            if (!userSnapshot.hasData || userSnapshot.data == null) {
              AuthService().signOut();
              return AuthScreen(onAuthComplete: (_,__) {});
            }

            // Get Data
            final user = userSnapshot.data!;

            // Route to Correct Dashboard
            return DashboardRouter(
              user: user,
              activeSession: false,
              companionActive: user.linkedUsers?.isNotEmpty ?? false,
              appsUnlocked: false,
            );
          },
        );
      },
    );
  }
}