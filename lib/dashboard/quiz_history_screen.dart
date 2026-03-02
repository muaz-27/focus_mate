import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_colors.dart';
import 'quiz_review_screen.dart';

class QuizHistoryScreen extends StatefulWidget {
  final String userId;

  const QuizHistoryScreen({super.key, required this.userId});

  @override
  State<QuizHistoryScreen> createState() => _QuizHistoryScreenState();
}

class _QuizHistoryScreenState extends State<QuizHistoryScreen> {
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Quiz History"),
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: StreamBuilder<QuerySnapshot>(
          stream: _firestore
              .collection('users')
              .doc(widget.userId)
              .collection('saved_quizzes')
              .where('status', isEqualTo: 'completed')
              .orderBy('timestamp', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
                // Sometime firestore requires an index for where + orderby.
                final errorString = snapshot.error.toString().toLowerCase();
                if (errorString.contains('failed-precondition') || errorString.contains('requires an index')) {
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
                return Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(color: Colors.white)));
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return Center(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.cardOverlay,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: const Text(
                    "No completed quizzes yet.",
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              );
            }

            return _buildList(snapshot.data!.docs);
          },
        ),
      ),
    );
  }

  Widget _buildList(List<QueryDocumentSnapshot> docs) {
     if (docs.isEmpty) {
         return Center(
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.cardOverlay,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: const Text(
                "No completed quizzes yet.",
                style: TextStyle(color: Colors.white54),
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
                      color: AppColors.cardOverlay,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: const BoxDecoration(
                            color: Colors.white10,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.history,
                              color: Colors.amberAccent, size: 28),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                sourceName,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Completed • Score: $score/$total",
                                style: TextStyle(
                                  color: Colors.amberAccent.withOpacity(0.7),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.white54),
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
