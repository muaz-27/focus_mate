import 'dart:io';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:focus_mate/theme/app_colors.dart';
import 'package:focus_mate/core/gemini_service.dart';
import 'package:focus_mate/screens/quiz/quiz_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PdfViewerScreen extends StatefulWidget {
  final File pdfFile;

  const PdfViewerScreen({super.key, required this.pdfFile});

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  bool _isGenerating = false;

  Future<void> _generateQuiz() async {
    setState(() => _isGenerating = true);

    try {
      final pdfBytes = await widget.pdfFile.readAsBytes();
      final gemini = GeminiService();
      final questions = await gemini.generateQuizFromPdf(pdfBytes);

      if (!mounted) return;

      if (questions == null || questions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Could not generate quiz from this document."),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Save quiz to Firestore for history
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("You must be logged in to take a quiz."),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      final pdfName = widget.pdfFile.path.split('/').last.split('\\').last.replaceAll('.pdf', '');
      final docRef = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('saved_quizzes')
          .add({
        'title': pdfName,
        'sourceName': pdfName,
        'questions': questions,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'active',
        'lastScore': 0,
      });

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => QuizScreen(
            questions: questions,
            quizDocId: docRef.id,
            userId: userId,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error generating quiz: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

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
        widget.pdfFile,
        canShowScrollHead: false,
        canShowScrollStatus: true,
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: AppColors.cardOverlay,
          border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
        ),
        child: SafeArea(
          child: ElevatedButton(
            onPressed: _isGenerating ? null : _generateQuiz,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purpleAccent,
              disabledBackgroundColor: Colors.purpleAccent.withValues(alpha: 0.5),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isGenerating
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(
                        "Generating Quiz...",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  )
                : const Text(
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