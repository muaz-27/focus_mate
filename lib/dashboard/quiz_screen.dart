import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_colors.dart';

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

  void _nextQuestion() {
    if (_selectedOption == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select an option first!")),
      );
      return;
    }

    if (_selectedOption == widget.questions[_currentIndex]['correctIndex']) {
      _score++;
    }

    if (_currentIndex < widget.questions.length - 1) {
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

    final double percentage = (_score / widget.questions.length) * 100;
    
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
      _currentIndex = 0;
      _score = 0;
      _quizFinished = false;
      _selectedOption = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.questions.isEmpty) {
      return const Scaffold(body: Center(child: Text("No questions generated!")));
    }

    if (_quizFinished) {
      final double percentage = (_score / widget.questions.length) * 100;
      final bool passed = percentage >= 70.0;
      
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text("Quiz Results"), 
          backgroundColor: Colors.transparent,
          automaticallyImplyLeading: false,
        ),
        body: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(passed ? Icons.check_circle : Icons.error, color: passed ? Colors.green : Colors.red, size: 80),
                const SizedBox(height: 20),
                Text(
                  "You scored $_score / ${widget.questions.length}",
                  style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Text(
                  "${percentage.toStringAsFixed(1)}%",
                  style: TextStyle(color: passed ? Colors.greenAccent : Colors.redAccent, fontSize: 24),
                ),
                const SizedBox(height: 20),
                Text(
                  passed ? "Congratulations! Your apps are now unlocked." : "You need 70% to unlock your apps. Keep studying!",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 40),
                passed 
                  ? ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent),
                      child: const Text("Return to Workspace", style: TextStyle(color: Colors.black)),
                    )
                  : Column(
                      children: [
                        ElevatedButton(
                          onPressed: _retryQuiz,
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent),
                          child: const Text("Retry Quiz", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text("Return to Workspace (Apps stay locked)", style: TextStyle(color: Colors.white70)),
                        )
                      ],
                    )
              ],
            ),
          ),
        ),
      );
    }

    final currentQuestion = widget.questions[_currentIndex];
    final List<dynamic> options = currentQuestion['options'];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text("Question ${_currentIndex + 1} of ${widget.questions.length}"),
        backgroundColor: Colors.transparent,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              currentQuestion['question'] ?? "Unknown question?",
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 40),
            Expanded(
              child: ListView(
                children: List.generate(options.length, (index) {
                   final isSelected = _selectedOption == index;
                   return Padding(
                     padding: const EdgeInsets.only(bottom: 16),
                     child: InkWell(
                       onTap: () => setState(() => _selectedOption = index),
                       child: Container(
                         padding: const EdgeInsets.all(20),
                         decoration: BoxDecoration(
                            color: isSelected ? Colors.cyanAccent.withOpacity(0.2) : Colors.white10,
                            border: Border.all(color: isSelected ? Colors.cyanAccent : Colors.white24),
                            borderRadius: BorderRadius.circular(16)
                         ),
                         child: Text(
                           options[index].toString(),
                           style: const TextStyle(color: Colors.white, fontSize: 16),
                         ),
                       ),
                     ),
                   );
                }),
              ),
            ),
            ElevatedButton(
              onPressed: _nextQuestion,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 20),
                backgroundColor: Colors.cyanAccent
              ),
              child: Text(
                _currentIndex == widget.questions.length - 1 ? "Finish Quiz" : "Next Question",
                style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            )
          ],
        ),
      ),
    );
  }
}
