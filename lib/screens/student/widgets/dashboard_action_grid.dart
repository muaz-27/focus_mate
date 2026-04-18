import 'package:flutter/material.dart';
import 'package:focus_mate/screens/study/study_workspace_screen.dart';
import 'package:focus_mate/screens/locks/parental_locks_screen.dart';
import 'package:focus_mate/screens/analytics/analytics_screen.dart';
import 'package:focus_mate/screens/schedule/schedule_list_screen.dart';
import 'package:focus_mate/screens/locks/unlock_request_screen.dart';
import 'package:focus_mate/core/permission_manager.dart';

class GlassTile extends StatelessWidget {
  final bool isDark;
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String? subtitle;

  const GlassTile({
    super.key,
    required this.isDark,
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 110), 
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark 
               ? [Colors.white.withValues(alpha: 0.07), Colors.white.withValues(alpha: 0.03)]
               : [Colors.white, Colors.grey.shade50],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.white, width: 1),
          boxShadow: [
             BoxShadow(
               color: isDark ? Colors.black.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.1), 
               blurRadius: 16, 
               offset: const Offset(0, 8)
             )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 16), 
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, 
                  style: TextStyle(
                    color: isDark ? Colors.white.withValues(alpha: 0.9) : Colors.black87, 
                    fontWeight: FontWeight.bold, 
                    fontSize: 16
                  )
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, 
                    style: TextStyle(
                      color: isDark ? Colors.white54 : Colors.black54, 
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    )
                  ),
                ]
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class DashboardActionGrid extends StatelessWidget {
  final bool isDark;
  final String studentId;
  final String studentName;
  final String? companionId;
  final String? companionRole;
  final String? companionName;
  final bool isSessionLocked;
  final bool appsUnlocked;
  final VoidCallback onAppLockTap;

  const DashboardActionGrid({
    super.key,
    required this.isDark,
    required this.studentId,
    required this.studentName,
    required this.companionId,
    required this.companionRole,
    required this.companionName,
    required this.isSessionLocked,
    required this.appsUnlocked,
    required this.onAppLockTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: GlassTile(
                isDark: isDark,
                title: "Study Workspace",
                icon: Icons.book,
                color: Colors.purpleAccent,
                onTap: () {
                   Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StudyWorkspaceScreen(userId: studentId),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildManagementGrid(context),
      ],
    );
  }

  Widget _buildManagementGrid(BuildContext context) {
    // Parental Locks Tile (only available to students with a parent companion)
    final Widget parentalLocksTile = (companionId != null && companionRole == 'parent') ? GlassTile(
      isDark: isDark,
      title: "Parental Locks",
      icon: Icons.admin_panel_settings,
      color: Colors.indigoAccent,
      subtitle: "View & Request",
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ParentalLocksScreen(
              studentId: studentId,
              studentName: studentName,
              companionId: companionId!,
            ),
          ),
        );
      },
    ) : const SizedBox.shrink();

    // If Parent Mode, hide "App Lock" (Only Analytics and Parental Locks)
    if (companionRole == 'parent') {
       return Column(
         children: [
           Row(
             children: [
               Expanded(
                 child: GlassTile(
                   isDark: isDark,
                   title: "Analytics",
                   icon: Icons.bar_chart,
                   color: Colors.green,
                   subtitle: "Stats",
                   onTap: () async {
                     if (await PermissionManager.checkUsageStats(context)) {
                       if (context.mounted) {
                         Navigator.push(
                           context, 
                           MaterialPageRoute(
                             builder: (_) => AnalyticsScreen(
                               userId: studentId,
                               userName: "My Stats",
                             ) 
                           )
                         );
                       }
                     }
                   },
                 ),
               ),
               if (companionId != null) ...[
                 const SizedBox(width: 16),
                 Expanded(child: parentalLocksTile),
               ] else ...[
                 const SizedBox(width: 16),
                 const Expanded(child: SizedBox.shrink()),
               ]
             ],
           ),
         ],
       );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: GlassTile(
                isDark: isDark,
                title: "App Lock",
                icon: isSessionLocked ? Icons.lock : Icons.phonelink_lock,
                color: isSessionLocked ? Colors.grey : Colors.orangeAccent,
                subtitle: isSessionLocked ? "Locked" : appsUnlocked ? "Unlocked" : "Active",
                onTap: () async {
                  if (isSessionLocked) {
                     ScaffoldMessenger.of(context).showSnackBar(
                       const SnackBar(content: Text("App Lock is managed by active session."))
                     );
                     return;
                  }
                  if (await PermissionManager.checkAccessibility(context)) {
                    if (context.mounted) {
                       onAppLockTap();
                    }
                  }
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: GlassTile(
                isDark: isDark,
                title: "Analytics",
                icon: Icons.bar_chart,
                color: Colors.green,
                subtitle: "Stats",
                onTap: () async {
                  if (await PermissionManager.checkUsageStats(context)) {
                    if (context.mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AnalyticsScreen(
                            userId: studentId,
                            userName: studentName,
                          ),
                        ),
                      );
                    }
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: GlassTile(
                isDark: isDark,
                title: "Schedules",
                icon: Icons.schedule,
                color: Colors.amberAccent,
                subtitle: "Automated Limits",
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ScheduleListScreen(
                        userId: studentId,
                        companionActive: companionId != null, // Changed from companionActive directly
                        companionId: companionId,
                        companionName: companionName,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 16),
            if (companionId != null)
              Expanded(
                child: GlassTile(
                  isDark: isDark,
                  title: "Unlock Request",
                  icon: Icons.lock_open,
                  color: Colors.purpleAccent,
                  subtitle: "Ask to unblock",
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => UnlockRequestScreen(
                          userId: studentId,
                          companionId: companionId!,
                        ),
                      ),
                    );
                  },
                ),
              )
            else
              const Expanded(child: SizedBox.shrink()),
          ],
        ),
      ],
    );
  }
}
