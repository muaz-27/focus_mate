import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:focus_mate/theme/app_colors.dart';
import 'package:focus_mate/theme/app_theme.dart';

/// Shows a standardized custom dialog.
Future<T?> showCustomDialog<T>({
  required BuildContext context,
  required String title,
  required Widget content,
  List<Widget>? actions,
  bool barrierDismissible = true,
  Color? titleColor,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (context) => CustomDialog(
      title: title,
      content: content,
      actions: actions,
      titleColor: titleColor,
    ),
  );
}

class CustomDialog extends StatelessWidget {
  final String title;
  final Widget content;
  final List<Widget>? actions;
  final Color? titleColor;

  const CustomDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20.r),
        side: BorderSide(
          color: isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight,
        ),
      ),
      title: Text(
        title,
        style: AppTheme.headerTitle(context).copyWith(
          fontSize: 20.sp,
          color: titleColor ?? Theme.of(context).colorScheme.onSurface,
        ),
      ),
      content: DefaultTextStyle(
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
          fontSize: 16.sp,
        ),
        child: content,
      ),
      actions: actions,
      elevation: 10,
    );
  }
}