import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class QuizReviewScreen extends StatelessWidget {
  final List<Map<String, dynamic>> questions;
  final String sourceName;
  final int score;

  const QuizReviewScreen({
    super.key,
    required this.questions,
    required this.sourceName,
    required this.score,
  });

  @override
  Widget build(BuildContext context) {
    if (questions.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text("Quiz Review"), backgroundColor: Colors.transparent),
        body: const Center(child: Text("No questions found.", style: TextStyle(color: Colors.white))),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Quiz Review"),
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Score: $score / ${questions.length}", 
                    style: const TextStyle(color: Colors.greenAccent, fontSize: 24, fontWeight: FontWeight.bold)
                  ),
                  const SizedBox(height: 8),
                  Text("Source: $sourceName", 
                    style: const TextStyle(color: Colors.white70, fontSize: 16)
                  ),
                  const SizedBox(height: 24),
                  const Divider(color: Colors.white24),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final questionData = questions[index];
                final questionText = questionData['question'] ?? "Unknown?";
                final options = questionData['options'] as List<dynamic>? ?? [];
                final correctIndex = questionData['correctIndex'] as int? ?? 0;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "${index + 1}. $questionText",
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 16),
                      ...List.generate(options.length, (optIndex) {
                        final isCorrect = optIndex == correctIndex;
                        return Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: isCorrect ? Colors.green.withOpacity(0.2) : Colors.white10,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isCorrect ? Colors.greenAccent : Colors.white24,
                              width: isCorrect ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              if (isCorrect) 
                                const Padding(
                                  padding: EdgeInsets.only(right: 12.0),
                                  child: Icon(Icons.check_circle, color: Colors.greenAccent, size: 20),
                                ),
                              Expanded(
                                child: Text(
                                  options[optIndex].toString(),
                                  style: TextStyle(
                                    color: isCorrect ? Colors.white : Colors.white70,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 8),
                      const Divider(color: Colors.white10),
                    ],
                  ),
                );
              },
              childCount: questions.length,
            ),
          ),
        ],
      ),
    );
  }
}
