import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'app_lock_screen.dart';
import 'companion_request_page.dart';

class AppLockModeSelection extends StatefulWidget {
  final String userId;
  final String? companionId;
  final String? companionName;

  const AppLockModeSelection({
    super.key,
    required this.userId,
    this.companionId,
    this.companionName,
  });

  @override
  State<AppLockModeSelection> createState() => _AppLockModeSelectionState();
}

class _AppLockModeSelectionState extends State<AppLockModeSelection> {
  String? _selectedMode; // 'normal' or 'companion'
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  void _setMode(String mode) async {
    setState(() {
      _selectedMode = mode;
    });

    // Save mode to Firestore
    await _firestore.collection('users').doc(widget.userId).update({
      'appLockMode': mode,
    });

    // Navigate immediately after saving
    if (!mounted) return;
    if (mode == 'normal') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => AppLockScreen(userId: widget.userId),
        ),
      );
    } else if (mode == 'companion') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => CompanionRequestPage(
            userId: widget.userId,
            companionId: widget.companionId,
            companionName: widget.companionName,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2C), // Dark theme background
      appBar: AppBar(
        title: const Text("Select App Lock Mode"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "Choose how you want to manage your app locks",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 30),
            _buildModeCard(
              title: "Normal Mode",
              subtitle: "You manage locks manually",
              icon: Icons.person_outline,
              mode: 'normal',
              color: Colors.blueAccent,
            ),
            const SizedBox(height: 20),
            _buildModeCard(
              title: "Companion Mode",
              subtitle: "Locks selected by your companion",
              icon: Icons.people_outline,
              mode: 'companion',
              color: Colors.purpleAccent,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required String mode,
    required Color color,
  }) {
    final isSelected = _selectedMode == mode;
    return GestureDetector(
      onTap: () => _setMode(mode),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.2) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 30),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: color),
          ],
        ),
      ),
    );
  }
}
