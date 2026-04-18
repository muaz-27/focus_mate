import 'package:flutter/material.dart';
import 'package:focus_mate/theme/app_colors.dart';

/// Defines the global dark theme configuration for the application.
ThemeData darkTheme = ThemeData(
  brightness: Brightness.dark,
  useMaterial3: true,
  scaffoldBackgroundColor: AppColors.background,
  colorScheme: ColorScheme.dark(
    primary: Colors.cyanAccent,
    secondary: Colors.blueAccent,
    surface: AppColors.cardOverlay,
    onSurface: Colors.white,
    error: Colors.redAccent,
  ),
  appBarTheme: AppBarTheme(
    backgroundColor: AppColors.cardOverlay,
    elevation: 0,
    iconTheme: const IconThemeData(color: Colors.white),
    titleTextStyle: const TextStyle(
      color: Colors.white,
      fontSize: 20,
      fontWeight: FontWeight.bold,
    ),
  ),
  cardTheme: CardThemeData(
    color: AppColors.cardOverlay,
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  ),
);