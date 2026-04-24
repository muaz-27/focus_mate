import 'package:flutter/material.dart';
import 'package:focus_mate/theme/app_colors.dart';
import 'package:focus_mate/theme/app_theme.dart';

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subTextColor = isDark ? Colors.white70 : Colors.grey.shade700;
    final dividerColor = isDark ? Colors.white24 : Colors.grey.shade300;
    final optionBg = isDark ? Colors.white10 : Colors.grey.shade100;
    final accentGreen = isDark ? Colors.greenAccent : Colors.green.shade700;

    if (questions.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: AppBar(title: Text("Quiz Review", style: TextStyle(color: textColor)), backgroundColor: Colors.transparent, elevation: 0, iconTheme: IconThemeData(color: textColor)),
        body: Container(
          decoration: AppTheme.screenBackground(context, AppColors.roleGradients['user']!),
          child: SafeArea(
            child: Center(child: Text("No questions found.", style: TextStyle(color: subTextColor))),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text("Quiz Review", style: TextStyle(color: textColor)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
      ),
      body: Container(
        decoration: AppTheme.screenBackground(context, AppColors.roleGradients['user']!),
        child: SafeArea(
          child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Score: $score / ${questions.length}", 
                    style: TextStyle(color: accentGreen, fontSize: 24, fontWeight: FontWeight.bold)
                  ),
                  const SizedBox(height: 8),
                  Text("Source: $sourceName", 
                    style: TextStyle(color: subTextColor, fontSize: 16)
                  ),
                  const SizedBox(height: 24),
                  Divider(color: dividerColor),
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
                        style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 16),
                      ...List.generate(options.length, (optIndex) {
                        final isCorrect = optIndex == correctIndex;
                        return Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: isCorrect ? Colors.green.withValues(alpha: 0.2) : optionBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isCorrect ? accentGreen : dividerColor,
                              width: isCorrect ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              if (isCorrect) 
                                Padding(
                                  padding: EdgeInsets.only(right: 12.0),
                                  child: Icon(Icons.check_circle, color: accentGreen, size: 20),
                                ),
                              Expanded(
                                child: Text(
                                  options[optIndex].toString(),
                                  style: TextStyle(
                                    color: isCorrect ? textColor : subTextColor,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 8),
                      Divider(color: isDark ? Colors.white10 : Colors.grey.shade200),
                    ],
                  ),
                );
              },
              childCount: questions.length,
            ),
          ),
        ],
        ),
      ),
      ),
    );
  }
}