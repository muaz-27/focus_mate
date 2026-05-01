import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:focus_mate/theme/app_colors.dart';
import 'package:focus_mate/theme/app_theme.dart';
import 'package:focus_mate/core/widgets/custom_button.dart';

class QuizScreen extends StatefulWidget {
  final String userId;
  final String quizDocId; // Add document ID for updates
  final List<Map<String, dynamic>> questions;

  const QuizScreen({super.key, required this.userId, required this.quizDocId, required this.questions});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  static const platform = MethodChannel('com.example.focus_mate/blocker');
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  int _currentIndex = 0;
  int _score = 0;
  bool _quizFinished = false;
  int? _selectedOption;
  
  late List<Map<String, dynamic>> _activeQuestions;

  @override
  void initState() {
    super.initState();
    _initAndShuffleQuestions();
  }

  void _initAndShuffleQuestions() {
    _activeQuestions = widget.questions.map((q) {
      final originalOptions = List<String>.from(q['options']);
      final correctOptionText = originalOptions[q['correctIndex']];
      
      final shuffledOptions = List<String>.from(originalOptions)..shuffle();
      final newCorrectIndex = shuffledOptions.indexOf(correctOptionText);

      return {
        'question': q['question'],
        'options': shuffledOptions,
        'correctIndex': newCorrectIndex,
      };
    }).toList();
    _activeQuestions.shuffle();
  }

  void _nextQuestion() {
    if (_selectedOption == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select an option first!")),
      );
      return;
    }

    if (_selectedOption == _activeQuestions[_currentIndex]['correctIndex']) {
      _score++;
    }

    if (_currentIndex < _activeQuestions.length - 1) {
      setState(() {
        _currentIndex++;
        _selectedOption = null;
      });
    } else {
      _finishQuiz();
    }
  }

  Future<void> _finishQuiz() async {
    setState(() {
      _quizFinished = true;
    });

    final double percentage = (_score / _activeQuestions.length) * 100;
    
    // Unlock apps if >= 70%
    if (percentage >= 70.0) {
      bool unlockFailed = false;
      String errorMsg = "";

      try {
        await platform.invokeMethod('setBlockedApps', {'apps': []});
      } catch (e) {
        unlockFailed = true;
        errorMsg = e.toString();
      }

      try {
        await _firestore.collection('users').doc(widget.userId).update({
          'lockedApps': [],
          'lockEndTime': FieldValue.delete(),
        });
      } catch (e) {
        debugPrint("Error clearing lockedApps: $e");
      }

      try {
        final quizDocRef = _firestore
            .collection('users')
            .doc(widget.userId)
            .collection('saved_quizzes')
            .doc(widget.quizDocId);

        final quizDoc = await quizDocRef.get();
        final companionSessionId = quizDoc.data()?['companionSessionId'];

        // Update current quiz status to completed
        await quizDocRef.update({
          'status': 'completed',
          'lastScore': _score,
        });

        // **NEW**: Clean up ANY other active quizzes so they don't pop up next
        final otherActiveQ = await _firestore
            .collection('users')
            .doc(widget.userId)
            .collection('saved_quizzes')
            .where('status', isEqualTo: 'active')
            .get();
        if (otherActiveQ.docs.isNotEmpty) {
           final batch = _firestore.batch();
           for (var doc in otherActiveQ.docs) {
              if (doc.id != widget.quizDocId) {
                  batch.update(doc.reference, {'status': 'abandoned'});
              }
           }
           await batch.commit();
        }

        // If part of a companion session, end it
        if (companionSessionId != null) {
            await _firestore.collection('companion_sessions').doc(companionSessionId).update({
               'status': 'ENDED',
               'endedAt': FieldValue.serverTimestamp(),
               'updatedAt': FieldValue.serverTimestamp(),
               'quizPassed': true,
            });
        }

        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text(unlockFailed ? "Quiz Passed! (Unlock error: $errorMsg)" : "Apps Unlocked successfully! Great job!")),
           );
        }
      } catch (e) {
         if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text("Error saving quiz score: $e")),
           );
         }
      }
    } else {
      // Just update the latest score if failed
      try {
        await _firestore
            .collection('users')
            .doc(widget.userId)
            .collection('saved_quizzes')
            .doc(widget.quizDocId)
            .update({
          'lastScore': _score,
        });
      } catch (e) {
        debugPrint("F_MATE: Error updating lastScore: $e");
      }
    }
  }

  void _retryQuiz() {
    setState(() {
      _initAndShuffleQuestions();
      _currentIndex = 0;
      _score = 0;
      _quizFinished = false;
      _selectedOption = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white70 : Colors.black54;
    final cardBg = isDark ? Colors.white10 : Colors.white.withValues(alpha: 0.7);
    final cardBorder = isDark ? Colors.white24 : Colors.black12;
    final selectedBg = isDark 
        ? Colors.cyanAccent.withValues(alpha: 0.2) 
        : Colors.cyanAccent.withValues(alpha: 0.12);

    if (_activeQuestions.isEmpty) {
      return Scaffold(body: Center(child: Text("No questions generated!", style: TextStyle(color: textColor))));
    }

    if (_quizFinished) {
      final double percentage = (_score / _activeQuestions.length) * 100;
      final bool passed = percentage >= 70.0;
      
      return Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: Text("Quiz Results", style: AppTheme.headerTitle(context).copyWith(fontSize: 22.sp)), 
          backgroundColor: Colors.transparent,
          automaticallyImplyLeading: false,
        ),
        body: Container(
          decoration: AppTheme.screenBackground(context, AppColors.roleGradients['user']!),
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 24.w),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(passed ? Icons.check_circle : Icons.error, color: passed ? Colors.green : Colors.red, size: 80.sp),
                  SizedBox(height: 20.h),
                  Text(
                    "You scored $_score / ${_activeQuestions.length}",
                    style: TextStyle(color: textColor, fontSize: 32.sp, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 10.h),
                  Text(
                    "${percentage.toStringAsFixed(1)}%",
                    style: TextStyle(color: passed ? Colors.greenAccent.shade700 : Colors.redAccent, fontSize: 24.sp),
                  ),
                  SizedBox(height: 20.h),
                  Text(
                    passed ? "Congratulations! Your apps are now unlocked." : "You need 70% to unlock your apps. Keep studying!",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: subTextColor, fontSize: 16.sp),
                  ),
                  SizedBox(height: 40.h),
                  passed 
                    ? CustomButton(
                        onPressed: () => Navigator.pop(context),
                        text: "Return to Workspace",
                        color: Colors.cyanAccent,
                      )
                    : Column(
                        children: [
                          CustomButton(
                            onPressed: _retryQuiz,
                            text: "Retry Quiz",
                            color: Colors.orangeAccent,
                          ),
                          SizedBox(height: 12.h),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text("Return to Workspace (Apps stay locked)", style: TextStyle(color: subTextColor, fontSize: 14.sp)),
                          )
                        ],
                      )
                ],
              ),
            ),
          ),
        ),
      );
    }

    final currentQuestion = _activeQuestions[_currentIndex];
    final List<dynamic> options = currentQuestion['options'];

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          "Question ${_currentIndex + 1} of ${_activeQuestions.length}",
          style: AppTheme.headerTitle(context).copyWith(fontSize: 22.sp),
        ),
        backgroundColor: Colors.transparent,
        iconTheme: IconThemeData(color: textColor),
      ),
      body: Container(
        decoration: AppTheme.screenBackground(context, AppColors.roleGradients['user']!),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(24.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  currentQuestion['question'] ?? "Unknown question?",
                  style: TextStyle(color: textColor, fontSize: 22.sp, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 40.h),
                Expanded(
                  child: ListView(
                    children: List.generate(options.length, (index) {
                       final isSelected = _selectedOption == index;
                       return Padding(
                         padding: EdgeInsets.only(bottom: 16.h),
                         child: InkWell(
                           onTap: () => setState(() => _selectedOption = index),
                           borderRadius: BorderRadius.circular(16.r),
                           child: Container(
                             padding: EdgeInsets.all(20.w),
                             decoration: BoxDecoration(
                                color: isSelected ? selectedBg : cardBg,
                                border: Border.all(
                                  color: isSelected ? Colors.cyanAccent : cardBorder,
                                  width: isSelected ? 1.5.w : 1.w,
                                ),
                                borderRadius: BorderRadius.circular(16.r),
                             ),
                             child: Text(
                               options[index].toString(),
                               style: TextStyle(color: textColor, fontSize: 16.sp),
                             ),
                           ),
                         ),
                       );
                    }),
                  ),
                ),
                CustomButton(
                  onPressed: _nextQuestion,
                  text: _currentIndex == _activeQuestions.length - 1 ? "Finish Quiz" : "Next Question",
                  color: Colors.cyanAccent,
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
