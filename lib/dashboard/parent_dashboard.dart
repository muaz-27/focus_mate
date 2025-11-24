import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../core/auth_service.dart';

class ParentDashboard extends StatelessWidget {
  final Map<String, dynamic> userData;
  final Function onLogout;

  const ParentDashboard({
    super.key,
    required this.userData,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.cardOverlay,
        title: Text("Parent Dashboard"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            onPressed: () {
              AuthService.signOut(context);
            }
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Monitored Students
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF3D1E00), Color(0xFF3A0505)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Monitored Students",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (userData['linkedUsers'] != null &&
                      (userData['linkedUsers'] as List).isNotEmpty)
                    ...List.generate(
                      userData['linkedUsers'].length,
                      (index) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          userData['linkedUsers'][index]['name'],
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    )
                  else
                    const Text(
                      "No students linked yet.",
                      style: TextStyle(color: Colors.grey),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
