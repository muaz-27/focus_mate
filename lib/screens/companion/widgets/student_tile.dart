import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:focus_mate/screens/analytics/analytics_screen.dart';

class StudentTile extends StatelessWidget {
  final String studentId;
  final bool isDark;

  const StudentTile({
    super.key,
    required this.studentId,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(studentId).get(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return Container(height: 80, decoration: BoxDecoration(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white70, borderRadius: BorderRadius.circular(16)));
        }

        final student = snap.data!.data() as Map<String, dynamic>;
        final studentName = student['name'] ?? "Unknown";
        final isOnline = student['isOnline'] ?? false; // Assuming we have this field or similar

        return Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Stack(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.blueAccent.withValues(alpha: 0.1),
                  child: Text(studentName[0].toUpperCase(), style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 20)),
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
                      border: Border.all(color: isDark ? const Color(0xFF1E293B) : Colors.white, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            title: Text(studentName, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 16)),
            subtitle: Text("Level ${student['level'] ?? 1} • Focus Scholar", style: TextStyle(color: Colors.grey[500], fontSize: 12)),
            trailing: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.blueAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.analytics_outlined, color: Colors.blueAccent, size: 20),
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AnalyticsScreen(
                    userId: studentId,
                    userName: studentName,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
