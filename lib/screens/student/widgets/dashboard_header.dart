import 'package:flutter/material.dart';
import 'package:focus_mate/theme/app_theme.dart';

class DashboardHeader extends StatelessWidget {
  final Map<String, dynamic> userData;
  final Color titleColor;
  final Color subtitleColor;
  final VoidCallback onSettingsTap;

  const DashboardHeader({
    super.key,
    required this.userData,
    required this.titleColor,
    required this.subtitleColor,
    required this.onSettingsTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Welcome back,",
                style: TextStyle(color: subtitleColor, fontSize: 13, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              Text(
                userData['name'] ?? "Student",
                style: AppTheme.headerTitle.copyWith(
                  color: titleColor, 
                  fontSize: 28, 
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.5
                ),
              ),
            ],
          ),
          Container(
            decoration: BoxDecoration(
              color: titleColor.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: titleColor.withValues(alpha: 0.1)),
            ),
            child: IconButton(
              onPressed: onSettingsTap,
              icon: Icon(Icons.settings, color: titleColor),
            ),
          ),
        ],
      ),
    );
  }
}
