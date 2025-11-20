import 'package:flutter/material.dart';

extension ColorAlpha on Color {
  Color withAlphaDouble(double alpha) => withOpacity(alpha);
}

class AppColors {
  // Background
  static const Color background = Colors.black;

  // Card overlay (glass/frost effect)
  static Color cardOverlay = Colors.grey.shade900.withOpacity(0.8);

  // Whites
  static const Color white = Colors.white;
  static const Color white70 = Colors.white70;
  static const Color white54 = Colors.white54;
  static const Color white24 = Colors.white24;

  // Role gradients
  static const Map<String, List<Color>> roleGradients = {
    'user': [Colors.cyanAccent, Colors.blueAccent],
    'companion': [Colors.purpleAccent, Colors.pinkAccent],
    'parent': [Colors.orangeAccent, Colors.redAccent],
  };

  // Role card backgrounds
  static const Map<String, List<Color>> roleBackgrounds = {
    'user': [Color(0xFF082D30), Color(0xFF0A1F3A)],
    'companion': [Color(0xFF1A0A3A), Color(0xFF3A0A30)],
    'parent': [Color(0xFF3D1E00), Color(0xFF3A0505)],
  };

  // Card border
  static const Color cardBorder = Colors.white12;

  // General accent for buttons etc.
  static const Color buttonAccent = Colors.cyanAccent;
}
