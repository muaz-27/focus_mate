import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:focus_mate/firebase_options.dart';
import 'package:focus_mate/theme/light_theme.dart';
import 'package:focus_mate/theme/dark_theme.dart';
import 'package:focus_mate/core/auth_gate.dart';
import 'package:focus_mate/core/notification_service.dart';

Future<void> main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("Failed to load .env file: $e");
  }

  try {
    // Initialize Firebase
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (e, stacktrace) {
    debugPrint("Initialization failed: $e\n$stacktrace");
  }

  try {
    await NotificationService().initialize();
  } catch (e) {
    debugPrint("Notification initialization failed: $e");
  }

  // Run app with Riverpod ProviderScope
  runApp(const ProviderScope(child: FocusMateApp()));
}

class FocusMateApp extends StatelessWidget {
  const FocusMateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(360, 690),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'FocusMate',
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: ThemeMode.system,
          home: const AuthGate(),
        );
      },
    );
  }
}
