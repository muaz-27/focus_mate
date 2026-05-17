import 'package:flutter/material.dart';
import 'package:focus_mate/theme/app_colors.dart';

/// Defines the global light theme configuration for the application.
ThemeData lightTheme = ThemeData(
  brightness: Brightness.light,
  useMaterial3: true,
  // InkSparkle loads shaders/stretch_effect.frag, which is missing in some
  // Patrol/integration APK builds and crashes before tests can run.
  splashFactory: InkRipple.splashFactory,
  scaffoldBackgroundColor:
      Colors.transparent, // Transparent to allow gradient backgrounds
  colorScheme: ColorScheme.light(
    primary: AppColors.buttonAccent,
    secondary: const Color(0xFF3B6BCA),
    surface: AppColors.cardOverlayLight,
    onSurface: Colors.black87,
    error: const Color(0xFFD32F2F),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.white,
    elevation: 0,
    iconTheme: IconThemeData(color: Colors.black87),
    titleTextStyle: TextStyle(
      color: Colors.black87,
      fontSize: 20,
      fontWeight: FontWeight.bold,
    ),
  ),
  cardTheme: CardThemeData(
    color: Colors.white,
    elevation: 2,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  ),
);
