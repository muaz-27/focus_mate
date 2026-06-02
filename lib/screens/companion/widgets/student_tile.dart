import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:focus_mate/screens/analytics/analytics_screen.dart';

class StudentTile extends StatelessWidget {
  final String studentId;
  final bool isDark;
  final String? companionId;

  const StudentTile({
    super.key,
    required this.studentId,
    required this.isDark,
    this.companionId,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(studentId).get(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return Container(
            height: 120,
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white70,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Center(
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          );
        }

        final student = snap.data!.data() as Map<String, dynamic>;
        final studentName = student['name'] ?? "Unknown";
        
        final bool rawOnline = (student['deviceOnline'] as bool?) ?? false;
        final Timestamp? lastSeenSnap = student['lastSeen'] as Timestamp?;
        final bool recentHeartbeat = lastSeenSnap != null &&
            DateTime.now().difference(lastSeenSnap.toDate()).inMinutes < 3;
        final isOnline = rawOnline && recentHeartbeat;

        final studyTime = student['studyTime'] ?? 0;
        final level = student['level'] ?? 1;
        final lockedApps = List<String>.from(student['lockedApps'] ?? []);

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
            ),
            boxShadow: [
              if (!isDark)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: Column(
            children: [
              // Top row: Avatar + Name + Status
              Row(
                children: [
                  // Avatar with online indicator
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: Colors.blueAccent.withValues(alpha: 0.1),
                        child: Text(
                          studentName[0].toUpperCase(),
                          style: const TextStyle(
                            color: Colors.blueAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: isOnline ? Colors.green : Colors.grey,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDark ? const Color(0xFF1E293B) : Colors.white,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  // Name + info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          studentName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(Icons.star_rounded, size: 14, color: Colors.amber.shade600),
                            const SizedBox(width: 3),
                            Text(
                              "Lvl $level",
                              style: TextStyle(
                                color: isDark ? Colors.grey[400] : Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(Icons.timer_outlined, size: 13, color: Colors.blueAccent.withValues(alpha: 0.7)),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                "${studyTime}m today",
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            if (lockedApps.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  "${lockedApps.length}🔒",
                                  style: TextStyle(
                                    color: Colors.redAccent.shade100,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Online/Offline chip
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isOnline
                          ? Colors.green.withValues(alpha: 0.1)
                          : Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isOnline ? "ONLINE" : "OFFLINE",
                      style: TextStyle(
                        color: isOnline ? Colors.green : Colors.grey,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Divider
              Container(
                height: 1,
                color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade200,
              ),
              const SizedBox(height: 12),
              // Bottom row: Quick action buttons
              Row(
                children: [
                  _buildActionButton(
                    context,
                    icon: Icons.analytics_outlined,
                    label: "Analytics",
                    color: Colors.blueAccent,
                    isDark: isDark,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AnalyticsScreen(
                            userId: studentId,
                            userName: studentName,
                            onUnlink: companionId != null ? () async {
                              final batch = FirebaseFirestore.instance.batch();
                              
                              // Remove student from companion's lists
                              final companionRef = FirebaseFirestore.instance.collection('users').doc(companionId);
                              batch.update(companionRef, {
                                'linkedStudents': FieldValue.arrayRemove([studentId]),
                                'linkedUsers': FieldValue.arrayRemove([studentId]),
                              });

                              // Remove companion from student's profile
                              final studentRef = FirebaseFirestore.instance.collection('users').doc(studentId);
                              batch.update(studentRef, {
                                'linkedCompanion': FieldValue.delete(),
                                'linkedParent': FieldValue.delete(),
                              });

                              await batch.commit();
                              
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('$studentName has been unlinked.')),
                                );
                              }
                            } : null,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildActionButton(
                    context,
                    icon: Icons.lock_outline,
                    label: "Locks",
                    color: Colors.grey, // Disabled look
                    isDark: isDark,
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("App Locks are restricted to Parent accounts.")),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildActionButton(
                    context,
                    icon: Icons.camera_alt_outlined,
                    label: "Snapshots",
                    color: Colors.grey, // Disabled look
                    isDark: isDark,
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Snapshots are restricted to Parent accounts.")),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.1 : 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: color.withValues(alpha: isDark ? 0.15 : 0.12),
              ),
            ),
            child: Column(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: isDark ? Colors.grey[300] : Colors.grey[700],
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
