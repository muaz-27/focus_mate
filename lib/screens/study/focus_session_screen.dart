import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:focus_mate/theme/app_colors.dart';
import 'package:focus_mate/theme/app_theme.dart';
import 'package:focus_mate/core/widgets/custom_dialog.dart';

class FocusSessionScreen extends StatefulWidget {
  final String userId;
  final String mode; // "Focused" or "Pomodoro"
  final int durationMinutes;

  const FocusSessionScreen({
    super.key,
    required this.userId,
    required this.mode,
    required this.durationMinutes,
  });

  @override
  State<FocusSessionScreen> createState() => _FocusSessionScreenState();
}

class _FocusSessionScreenState extends State<FocusSessionScreen> {
  Timer? _timer;
  int _remainingSeconds = 0;
  int _totalSeconds = 0;
  bool _isPaused = false;

  @override
  void initState() {
    super.initState();
    _totalSeconds = widget.durationMinutes * 60;
    _remainingSeconds = _totalSeconds;
    _setSessionStatus(true); // Let the database know we started studying
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _setSessionStatus(false);
    super.dispose();
  }

  Future<void> _setSessionStatus(bool isActive) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .update({'activeSession': isActive});
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted && !_isPaused) {
        setState(() {
          if (_remainingSeconds > 0) {
            _remainingSeconds--;
          } else {
            _finishSession();
          }
        });
      }
    });
  }

  Future<void> _finishSession() async {
    _timer?.cancel();
    await _setSessionStatus(false); // Let the database know we stopped

    // Update Study Time
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .update({'studyTime': FieldValue.increment(widget.durationMinutes)});

    if (mounted) {
      Navigator.pop(context); // Go back to Dashboard
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Session Complete! +XP Gained")),
      );
    }
  }

  Future<void> _giveUp() async {
    bool? confirm = await showCustomDialog<bool>(
      context: context,
      title: "Give Up?",
      content: const Text("Your session won't be counted."),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text("Cancel"),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text("I Quit", style: TextStyle(color: Colors.red)),
        ),
      ],
    );

    if (confirm == true) {
      await _setSessionStatus(false);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Format Time: 05:30
    String timeText =
        "${(_remainingSeconds ~/ 60).toString().padLeft(2, '0')}:${(_remainingSeconds % 60).toString().padLeft(2, '0')}";

    double progress = 1.0 - (_remainingSeconds / _totalSeconds);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final mutedColor = isDark ? Colors.grey[400]! : Colors.grey.shade600;

    // We use this widget to stop the user from accidentally going back
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Container(
          height: double.infinity,
          width: double.infinity,
          decoration: AppTheme.screenBackground(
            context,
            AppColors.roleGradients['user']!,
          ),
          child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final circleSize = (constraints.maxWidth * 0.55).clamp(150.0, 250.0);
              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(height: 40),
                      Text(
                        "FOCUS MODE",
                        style: TextStyle(color: mutedColor, letterSpacing: 2),
                      ),
                      const SizedBox(height: 40),

                      Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: circleSize,
                            height: circleSize,
                            child: CircularProgressIndicator(
                              value: progress,
                              strokeWidth: circleSize * 0.06,
                              backgroundColor: isDark ? AppColors.cardOverlay : Colors.grey.shade200,
                              color: isDark ? Colors.blueAccent : Colors.blue.shade700,
                            ),
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              timeText,
                              style: TextStyle(
                                color: textColor,
                                fontSize: 60,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 60),

                      // Controls
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Pause/Resume
                          FloatingActionButton(
                            backgroundColor: isDark ? Colors.white : Colors.grey.shade800,
                            onPressed: () {
                              setState(() {
                                _isPaused = !_isPaused;
                              });
                            },
                            child: Icon(_isPaused ? Icons.play_arrow : Icons.pause, color: isDark ? Colors.black : Colors.white),
                          ),
                          const SizedBox(width: 24),
                          
                          // End Session
                          FloatingActionButton(
                            backgroundColor: Colors.redAccent,
                            onPressed: _giveUp,
                            child: const Icon(Icons.stop, color: Colors.white),
                          ),
                        ],
                      ),
                      SizedBox(height: 40),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        ),
      ),
    );
  }
}