import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

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
    return AlertDialog(
      backgroundColor: AppColors.cardOverlay,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        title,
        style: AppTheme.headerTitle.copyWith(
          fontSize: 20,
          color: titleColor ?? AppColors.white,
        ),
      ),
      content: DefaultTextStyle(
        style: TextStyle(color: Colors.grey.shade300, fontSize: 16),
        child: content,
      ),
      actions: actions,
      elevation: 10,
    );
  }
}
