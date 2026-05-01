import 'package:flutter/material.dart';
import 'package:focus_mate/screens/quiz/quiz_history_screen.dart';

class QuizzesGrid extends StatelessWidget {
  final bool hasActiveSession;
  final bool isWaitingForCompanion;
  final bool canTakeQuiz;
  final bool loadingApps;
  final bool companionActive;
  final String userId;
  final Widget indicator;
  final VoidCallback onReadPdf;
  final VoidCallback onStartStudySession;
  final VoidCallback onOpenCurrentQuiz;

  const QuizzesGrid({
    super.key,
    required this.hasActiveSession,
    required this.isWaitingForCompanion,
    required this.canTakeQuiz,
    required this.loadingApps,
    required this.companionActive,
    required this.userId,
    required this.indicator,
    required this.onReadPdf,
    required this.onStartStudySession,
    required this.onOpenCurrentQuiz,
  });

  Widget _buildToolCard(String title, IconData icon, Color color, VoidCallback onTap, {bool isDisabled = false, required bool isDark}) {
    return InkWell(
      onTap: isDisabled ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: Opacity(
        opacity: isDisabled ? 0.5 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
                blurRadius: 8,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isDark ? 0.2 : 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Useful tools for studying
          Text("Tools", style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildToolCard(
                  "Read PDF",
                  Icons.picture_as_pdf,
                  Colors.redAccent,
                  onReadPdf,
                  isDisabled: false,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildToolCard(
                  "Start Session",
                  Icons.school,
                  Colors.amberAccent.shade700,
                  onStartStudySession,
                  isDisabled: hasActiveSession || isWaitingForCompanion || loadingApps,
                  isDark: isDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          indicator,
          const SizedBox(height: 16),
          Text("Quiz Management", style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildToolCard(
                  "Current Quiz",
                  Icons.play_circle_fill,
                  Colors.cyanAccent.shade700,
                  onOpenCurrentQuiz,
                  isDisabled: !canTakeQuiz || (!hasActiveSession && !isWaitingForCompanion),
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildToolCard(
                  "Quiz History",
                  Icons.history,
                  Colors.greenAccent.shade700,
                  () => Navigator.push(context, MaterialPageRoute(builder: (_) => QuizHistoryScreen(userId: userId))),
                  isDisabled: false,
                  isDark: isDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
