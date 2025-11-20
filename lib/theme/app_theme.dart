import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  // Input decoration for Option C theme
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
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    );
  }

  // Card container with soft gradient overlay
  static BoxDecoration cardContainer(List<Color> gradientColors) {
    return BoxDecoration(
      gradient: LinearGradient(
        colors: gradientColors.map((c) => c.withOpacity(0.15)).toList(),
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(16),
      color: AppColors.cardOverlay,
      border: Border.all(color: AppColors.cardBorder),
    );
  }

  // Header styles
  static const TextStyle headerTitle = TextStyle(
    color: AppColors.white,
    fontSize: 22,
    fontWeight: FontWeight.bold,
  );

  static TextStyle subtitle = TextStyle(color: Colors.grey.shade300);

  // Primary button style
  static ButtonStyle primaryButton(List<Color> gradient) {
    return ElevatedButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      backgroundColor: gradient[0],
      foregroundColor: AppColors.white,
    );
  }

  // Gradient container for large buttons
  static BoxDecoration gradientButton(List<Color> gradient) {
    return BoxDecoration(
      gradient: LinearGradient(colors: gradient),
      borderRadius: BorderRadius.circular(14),
    );
  }
}
