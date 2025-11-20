import 'package:flutter/material.dart';
import 'package:focus_mate/theme/app_colors.dart';

class DummyPage extends StatelessWidget {
  final String title;

  const DummyPage({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(title, style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
      ),
      body: Center(
        child: Text(
          "$title Page\n(Backend Coming Soon)",
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 20),
        ),
      ),
    );
  }
}
