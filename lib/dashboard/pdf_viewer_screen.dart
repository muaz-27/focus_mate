import 'dart:io';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class PdfViewerScreen extends StatelessWidget {
  final File pdfFile;

  const PdfViewerScreen({super.key, required this.pdfFile});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Study Material", style: TextStyle(color: Colors.white)),
        backgroundColor: AppColors.background,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: SfPdfViewer.file(
        pdfFile,
        canShowScrollHead: false,
        canShowScrollStatus: true,
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: AppColors.cardOverlay,
          border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
        ),
        child: SafeArea(
          child: ElevatedButton(
            onPressed: () {
              // TODO: Start Quiz Mode
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Quiz mode coming soon!")),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purpleAccent,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              "I'm Ready to Take the Quiz",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
