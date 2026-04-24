import 'package:flutter/material.dart';
import 'package:focus_mate/theme/app_colors.dart';

/// Defines the global dark theme configuration for the application.
ThemeData darkTheme = ThemeData(
  brightness: Brightness.dark,
  useMaterial3: true,
  scaffoldBackgroundColor: Colors.transparent, // Transparent to allow gradient backgrounds
  colorScheme: ColorScheme.dark(
    primary: AppColors.buttonAccent,
    secondary: const Color(0xFF3B6BCA),
    surface: AppColors.cardOverlayDark,
    onSurface: Colors.white,
    error: const Color(0xFFE57373),
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
    color: AppColors.cardOverlayDark,
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  ),
);