import 'package:flutter/material.dart';

extension ColorAlpha on Color {
  Color withAlphaDouble(double alpha) => withValues(alpha: alpha);
}

/// Centralized color definitions for the application.
class AppColors {
  /// Default dark background gradient (subtle linear).
  static const LinearGradient darkBackgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF151821), Color(0xFF0D0F16)],
  );

  /// Default light background gradient (subtle linear).
  static const LinearGradient lightBackgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF0F4F8), Color(0xFFE2E8F0)],
  );

  /// Semi-transparent overlay color for glassmorphism effects on cards.
  static Color cardOverlayDark = const Color(0xFF1E2230).withValues(alpha: 0.85);
  static Color cardOverlayLight = const Color(0xFFFFFFFF).withValues(alpha: 0.85);

  // --- White Variants ---
  static const Color white = Colors.white;
  static const Color white70 = Colors.white70;
  static const Color white54 = Colors.white54;
  static const Color white24 = Colors.white24;

  // --- Fallback Colors ---
  static const Color background = Color(0xFF0F172A);
  static Color cardOverlay = const Color(0xFF1E2230).withValues(alpha: 0.85);

  /// Gradient color combinations for different user roles (Subtle aesthetic shades).
  static const Map<String, List<Color>> roleGradients = {
    // Deep Cyan to Blue for Student/User
    'user': [Color(0xFF00E5FF), Color(0xFF007BFF)],
    // Vibrant Purple/Pink for Companion
    'companion': [Color(0xFFD500F9), Color(0xFF651FFF)],
    // Rich Red/Orange for Parent
    'parent': [Color(0xFFFF3D00), Color(0xFFD50000)],
  };

  /// Background colors for role selection cards (Dark mode).
  static const Map<String, List<Color>> roleBackgroundsDark = {
    'user': [Color(0xFF1E2D4A), Color(0xFF121B2E)],
    'companion': [Color(0xFF2A1F4A), Color(0xFF1A122E)],
    'parent': [Color(0xFF4A1F1F), Color(0xFF2E1212)],
  };

  /// Background colors for role selection cards (Light mode).
  static const Map<String, List<Color>> roleBackgroundsLight = {
    'user': [Color(0xFFE0F7FA), Color(0xFFB2EBF2)],
    'companion': [Color(0xFFF3E5F5), Color(0xFFE1BEE7)],
    'parent': [Color(0xFFFFEBEE), Color(0xFFFCE4EC)],
  };

  /// Background colors for role selection cards (Legacy fallback).
  static const Map<String, List<Color>> roleBackgrounds = {
    'user': [Color(0xFF1E2D4A), Color(0xFF121B2E)],
    'companion': [Color(0xFF2A1F4A), Color(0xFF1A122E)],
    'parent': [Color(0xFF4A1F1F), Color(0xFF2E1212)],
  };

  /// Default border color for cards.
  static const Color cardBorderDark = Colors.white12;
  static const Color cardBorderLight = Colors.black12;

  /// General accent color for buttons and interactive elements.
  static const Color buttonAccent = Color(0xFF5B8DEF); // Default to user bluish
}
