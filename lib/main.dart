import 'package:flutter/material.dart';
import 'auth/auth_screen.dart';

// Dummy AppLockCenter Screen
class AppLockCenter extends StatelessWidget {
  final String userName;

  const AppLockCenter({super.key, required this.userName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('App Lock Center'),
        backgroundColor: Colors.grey[900],
      ),
      body: Center(
        child: Text(
          'Welcome, $userName!',
          style: const TextStyle(color: Colors.white, fontSize: 22),
        ),
      ),
    );
  }
}

void main() {
  runApp(const FocusMateApp());
}

class FocusMateApp extends StatefulWidget {
  const FocusMateApp({super.key});

  @override
  State<FocusMateApp> createState() => _FocusMateAppState();
}

class _FocusMateAppState extends State<FocusMateApp> {
  Widget _currentScreen = Container();

  @override
  void initState() {
    super.initState();
    _currentScreen = AuthScreen(onAuthComplete: _handleAuthComplete);
  }

  void _handleAuthComplete(UserRole role, dynamic userData) {
    // Navigate to AppLockCenter after login/signup
    setState(() {
      _currentScreen = AppLockCenter(userName: userData['name']);
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
