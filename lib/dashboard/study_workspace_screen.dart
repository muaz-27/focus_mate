import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class StudyWorkspaceScreen extends StatelessWidget {
  final String userId;

  const StudyWorkspaceScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Study Workspace"),
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: AppTheme.headerTitle,
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.blueAccent),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Useful tools for studying
            const Text("Tools", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildToolCard(
                    "PDF Reader",
                    Icons.picture_as_pdf,
                    Colors.redAccent,
                    () {},
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildToolCard(
                    "Generate Quiz",
                    Icons.quiz,
                    Colors.purpleAccent,
                    () {},
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Files you opened recently
            const Text("Recent Materials", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _buildMaterialItem("Math Notes - Chapter 1", "PDF • 2.3 MB", "2 mins ago"),
            _buildMaterialItem("History Essay Draft", "DOCX • 1.1 MB", "1 hour ago"),
            _buildMaterialItem("Physics Formula Sheet", "IMG • 500 KB", "Yesterday"),
            
            const SizedBox(height: 24),

            // Quizzes you have saved
            const Text("Saved Quizzes", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _buildQuizItem("Algebra Basics", "10 Questions • 80% Score"),
            _buildQuizItem("World War II", "20 Questions • Not started"),
          ],
        ),
      ),
    );
  }

  Widget _buildToolCard(String title, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.cardOverlay,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildMaterialItem(String title, String subtitle, String time) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.blueAccent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.description, color: Colors.blueAccent),
        ),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.grey)),
        trailing: Text(time, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        onTap: () {},
      ),
    );
  }

  Widget _buildQuizItem(String title, String subtitle) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.purpleAccent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.assignment, color: Colors.purpleAccent),
        ),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.grey)),
        trailing: const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16),
        onTap: () {},
      ),
    );
  }
}
