import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:focus_mate/theme/app_colors.dart';

/// Helper class for reusable theme styles and decorations.
class AppTheme {
  /// Returns a standard input decoration with a hint and icon.
  static InputDecoration inputDecoration(
    BuildContext context, {
    required String hint,
    required IconData icon,
    IconButton? suffix,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InputDecoration(
      prefixIcon: Icon(icon, color: isDark ? AppColors.white70 : Colors.black54),
      suffixIcon: suffix,
      hintText: hint,
      hintStyle: TextStyle(
        color: isDark ? AppColors.white54 : Colors.black45,
        fontSize: 14.sp,
      ),
      filled: true,
      fillColor: isDark ? AppColors.white24 : Colors.black12,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14.r),
        borderSide: BorderSide.none,
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
    );
  }

  /// Returns a BoxDecoration for cards with a soft gradient overlay and glass effect.
  static BoxDecoration cardContainer(BuildContext context, List<Color> gradientColors) {
    return BoxDecoration(
      gradient: LinearGradient(
        colors: gradientColors.map((c) => c.withValues(alpha: 0.15)).toList(),
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(16.r),
      color: Theme.of(context).colorScheme.surface,
      border: Border.all(
        color: Theme.of(context).brightness == Brightness.dark
            ? AppColors.cardBorderDark
            : AppColors.cardBorderLight,
      ),
    );
  }

  /// Standard style for header titles.
  static TextStyle headerTitle(BuildContext context) {
    return TextStyle(
      color: Theme.of(context).colorScheme.onSurface,
      fontSize: 22.sp,
      fontWeight: FontWeight.bold,
    );
  }

  /// Standard style for subtitles.
  static TextStyle subtitle(BuildContext context) {
    return TextStyle(
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
      fontSize: 14.sp,
    );
  }

  /// Returns a ButtonStyle for primary buttons with a gradient background.
  static ButtonStyle primaryButton(List<Color> gradient) {
    return ElevatedButton.styleFrom(
      padding: EdgeInsets.symmetric(vertical: 14.h, horizontal: 24.w),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.r)),
      backgroundColor: gradient[0],
      foregroundColor: AppColors.white, // Always white text on gradients for contrast
    );
  }

  /// Returns a BoxDecoration for large buttons requiring a full gradient background.
  static BoxDecoration gradientButton(List<Color> gradient) {
    return BoxDecoration(
      gradient: LinearGradient(colors: gradient),
      borderRadius: BorderRadius.circular(14.r),
    );
  }

  /// Returns a BoxDecoration for the main screen background gradient.
  static BoxDecoration screenBackground(BuildContext context, List<Color> gradient) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // The base solid color (80% of the screen)
    final baseColor = isDark ? const Color(0xFF0B0E17) : const Color(0xFFF8FAFC);
    
    // The top-left accent color blended softly (15-20% color)
    final accentColor = gradient[0];
    final topColor = Color.lerp(baseColor, accentColor, isDark ? 0.20 : 0.15) ?? baseColor;

    return BoxDecoration(
      gradient: LinearGradient(
        colors: [topColor, baseColor],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: const [0.0, 0.8],
      ),
    );
  }

  // ── Contrast-aware color helpers ──────────────────────────────────

  /// Primary text color – high contrast for body text.
  /// Dark: white  |  Light: near-black
  static Color textPrimary(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : const Color(0xFF1A1A2E);
  }

  /// Secondary text color – for subtitles and supporting info.
  /// Dark: white70  |  Light: dark grey
  static Color textSecondary(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.white70
        : const Color(0xFF4A4A5A);
  }

  /// Muted text color – for labels, hints, timestamps.
  /// Dark: white60  |  Light: medium grey
  static Color textMuted(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0x99FFFFFF) // white60
        : Colors.grey.shade600;
  }

  /// Disabled/placeholder text color.
  /// Dark: white38  |  Light: grey 500
  static Color textDisabled(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.white38
        : Colors.grey.shade500;
  }

  /// Icon color – matches secondary text for consistency.
  static Color iconColor(BuildContext context) {
    return textSecondary(context);
  }

  /// Subtle border / divider color.
  static Color borderColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.08);
  }

  /// Card surface color with slight transparency for glassmorphism.
  static Color cardSurface(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.white.withValues(alpha: 0.85);
  }
}