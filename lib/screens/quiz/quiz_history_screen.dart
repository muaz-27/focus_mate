import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focus_mate/theme/app_colors.dart';
import 'package:focus_mate/theme/app_theme.dart';
import 'package:focus_mate/screens/quiz/quiz_review_screen.dart';
import 'package:focus_mate/providers/quiz_provider.dart';

class QuizHistoryScreen extends ConsumerStatefulWidget {
  final String userId;
  final bool isReadOnly;

  const QuizHistoryScreen({super.key, required this.userId, this.isReadOnly = false});

  @override
  ConsumerState<QuizHistoryScreen> createState() => _QuizHistoryScreenState();
}

class _QuizHistoryScreenState extends ConsumerState<QuizHistoryScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> _deleteQuiz(String docId) async {
    try {
      await _firestore
          .collection('users')
          .doc(widget.userId)
          .collection('saved_quizzes')
          .doc(docId)
          .delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Quiz deleted from history.")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Error deleting quiz: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final quizzesAsync = ref.watch(quizzesProvider(widget.userId));

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final cardBg = isDark ? AppColors.cardOverlay : Colors.white.withValues(alpha: 0.85);
    final borderColor = isDark ? Colors.white10 : Colors.grey.shade200;
    final iconBg = isDark ? Colors.white10 : Colors.amber.withValues(alpha: 0.1);
    final accentAmber = isDark ? Colors.amberAccent : Colors.amber.shade700;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text("Quiz History", style: TextStyle(color: textColor)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
      ),
      body: Container(
        decoration: AppTheme.screenBackground(context, AppColors.roleGradients['user']!),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: quizzesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) {
                final errorString = error.toString().toLowerCase();
                if (errorString.contains('failed-precondition') || errorString.contains('requires an index')) {
                  return _buildFallbackStream();
                }
                return Center(child: Text("Error: $error", style: TextStyle(color: textColor)));
              },
              data: (docs) {
                final completedDocs = docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return data['status'] == 'completed';
                }).toList();
                return _buildList(completedDocs);
              },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Fallback when compound index is not yet created
  Widget _buildFallbackStream() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('users')
          .doc(widget.userId)
          .collection('saved_quizzes')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, fallbackSnapshot) {
        if (!fallbackSnapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = fallbackSnapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return data['status'] == 'completed';
        }).toList();
        return _buildList(docs);
      },
    );
  }

  Widget _buildList(List<QueryDocumentSnapshot> docs) {
     final isDark = Theme.of(context).brightness == Brightness.dark;
     final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
     final cardBg = isDark ? AppColors.cardOverlay : Colors.white.withValues(alpha: 0.85);
     final borderColor = isDark ? Colors.white10 : Colors.grey.shade200;
     final iconBg = isDark ? Colors.white10 : Colors.amber.withValues(alpha: 0.1);
     final accentAmber = isDark ? Colors.amberAccent : Colors.amber.shade700;

     if (docs.isEmpty) {
         return Center(
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor),
              ),
              child: Text(
                "No completed quizzes yet.",
                style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.grey.shade700),
              ),
            ),
          );
     }
     
     return ListView.separated(
              itemCount: docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final doc = docs[index];
                final data = doc.data() as Map<String, dynamic>;
                final questionsList = data['questions'] as List<dynamic>? ?? [];

                final String sourceName = data['sourceName'] ?? 'Unknown Source';
                final int score = data['lastScore'] ?? 0;
                final int total = questionsList.length;

                return GestureDetector(
                  onTap: () {
                    final mappedQuestions = questionsList
                        .map((e) => Map<String, dynamic>.from(e as Map))
                        .toList();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => QuizReviewScreen(
                          questions: mappedQuestions,
                          sourceName: sourceName,
                          score: score,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderColor),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: iconBg,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.history,
                              color: accentAmber, size: 28),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                sourceName,
                                style: TextStyle(
                                    color: textColor,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Completed • Score: $score/$total",
                                style: TextStyle(
                                  color: accentAmber.withValues(alpha: 0.7),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!widget.isReadOnly)
                          IconButton(
                            icon: Icon(Icons.delete_outline,
                                color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.grey.shade700),
                            onPressed: () => _deleteQuiz(doc.id),
                          ),
                      ],
                    ),
                  ),
                );
              },
            );
  }
}