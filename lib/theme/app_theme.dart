import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Helper class for reusable theme styles and decorations.
class AppTheme {
  /// Returns a standard input decoration with a hint and icon.
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

  /// Returns a BoxDecoration for cards with a soft gradient overlay and glass effect.
  static BoxDecoration cardContainer(List<Color> gradientColors) {
    return BoxDecoration(
      gradient: LinearGradient(
        colors: gradientColors.map((c) => c.withValues(alpha: 0.15)).toList(),
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(16),
      color: AppColors.cardOverlay,
      border: Border.all(color: AppColors.cardBorder),
    );
  }

  /// Standard style for header titles.
  static const TextStyle headerTitle = TextStyle(
    color: AppColors.white,
    fontSize: 22,
    fontWeight: FontWeight.bold,
  );

  /// Standard style for subtitles.
  static TextStyle subtitle = TextStyle(color: Colors.grey.shade300);

  /// Returns a ButtonStyle for primary buttons with a gradient background.
  /// Note: Takes the first color of the gradient as the background color.
  static ButtonStyle primaryButton(List<Color> gradient) {
    return ElevatedButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      backgroundColor: gradient[0],
      foregroundColor: AppColors.white,
    );
  }

  /// Returns a BoxDecoration for large buttons requiring a full gradient background.
  static BoxDecoration gradientButton(List<Color> gradient) {
    return BoxDecoration(
      gradient: LinearGradient(colors: gradient),
      borderRadius: BorderRadius.circular(14),
    );
  }
}
