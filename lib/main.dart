import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:focus_mate/core/dashboard_router.dart';
import 'firebase_options.dart';
import 'auth/auth_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const FocusMateApp());
}

class FocusMateApp extends StatefulWidget {
  const FocusMateApp({super.key});

  @override
  State<FocusMateApp> createState() => _FocusMateAppState();
}

class _FocusMateAppState extends State<FocusMateApp> {
  late Widget _currentScreen;
  Map<String, dynamic> _userData = {};
  UserRole? _userRole; // <-- now recognized

  // Dummy initial values for student dashboard
  int _studyTime = 0;
  int _dailyGoal = 120;
  bool _activeSession = false;
  bool _companionActive = false;
  bool _appsUnlocked = false;

  @override
  void initState() {
    super.initState();
    _currentScreen = AuthScreen(onAuthComplete: _handleAuthComplete);
  }

  // <-- Now the type UserRole is recognized
  void _handleAuthComplete(UserRole role, dynamic userData) {
    setState(() {
      _userRole = role;
      _userData = userData;
      _currentScreen = DashboardRouter(
        role: role,
        userData: userData,
        studyTime: _studyTime,
        dailyGoal: _dailyGoal,
        activeSession: _activeSession,
        companionActive: _companionActive,
        appsUnlocked: _appsUnlocked,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FocusMate',
      theme: ThemeData.dark(useMaterial3: true),
      home: _currentScreen,
    );
  }
}
