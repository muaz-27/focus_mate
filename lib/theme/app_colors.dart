import 'package:flutter/material.dart';

extension ColorAlpha on Color {
  Color withAlphaDouble(double alpha) => withValues(alpha: alpha);
}

/// Centralized color definitions for the application.
class AppColors {
  /// Default background color for dark mode.
  static const Color background = Colors.black;

  /// Semi-transparent overlay color for glassmorphism effects on cards.
  static Color cardOverlay = Colors.grey.shade900.withValues(alpha: 0.8);

  // --- White Variants ---
  static const Color white = Colors.white;
  static const Color white70 = Colors.white70;
  static const Color white54 = Colors.white54;
  static const Color white24 = Colors.white24;

  /// Gradient color combinations for different user roles.
  static const Map<String, List<Color>> roleGradients = {
    'user': [Colors.cyanAccent, Colors.blueAccent],
    'companion': [Colors.purpleAccent, Colors.pinkAccent],
    'parent': [Colors.orangeAccent, Colors.redAccent],
  };

  /// Background colors for role selection cards.
  static const Map<String, List<Color>> roleBackgrounds = {
    'user': [Color(0xFF082D30), Color(0xFF0A1F3A)],
    'companion': [Color(0xFF1A0A3A), Color(0xFF3A0A30)],
    'parent': [Color(0xFF3D1E00), Color(0xFF3A0505)],
  };

  /// Default border color for cards.
  static const Color cardBorder = Colors.white12;

  /// General accent color for buttons and interactive elements.
  static const Color buttonAccent = Colors.cyanAccent;
}
