import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  // Input Decoration
  static InputDecoration inputDecoration({
    required String hint,
    required IconData icon,
    IconButton? suffix,
  }) {
    return InputDecoration(
      prefixIcon: Icon(icon, color: AppColors.white70),
      suffixIcon: suffix,
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.white54),
      filled: true,
      fillColor: AppColors.white24,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }

  // Card container decoration
  static BoxDecoration cardContainer(List<Color> gradientColors) {
    return BoxDecoration(
      gradient: LinearGradient(
        colors: gradientColors.map((c) => c.withValues(alpha: 0.15)).toList(),
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(16),
      color: AppColors.cardOverlay,
    );
  }

  // Signup/Login header title
  static const TextStyle headerTitle = TextStyle(
    color: AppColors.white,
    fontSize: 22,
    fontWeight: FontWeight.bold,
  );

  static TextStyle subtitle = TextStyle(color: Colors.grey.shade300);

  // Full width primary button
  static ButtonStyle primaryButton(List<Color> gradient) {
    return ElevatedButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: gradient[0],
    );
  }
}
