import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../core/widgets/custom_dialog.dart';

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
  DateTime? _endTime;

  @override
  void initState() {
    super.initState();
    _totalSeconds = widget.durationMinutes * 60;
    _remainingSeconds = _totalSeconds;
    _endTime = DateTime.now().add(Duration(minutes: widget.durationMinutes));
    _setSessionStatus(true, _endTime); 
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _setSessionStatus(false, null);
    super.dispose();
  }

  Future<void> _setSessionStatus(bool isActive, DateTime? expectedEnd) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .update({
          'activeSession': isActive,
          if (isActive && expectedEnd != null) 'sessionEndTime': Timestamp.fromDate(expectedEnd),
        });
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted && !_isPaused && _endTime != null) {
        setState(() {
          final now = DateTime.now();
          if (now.isBefore(_endTime!)) {
            _remainingSeconds = _endTime!.difference(now).inSeconds;
          } else {
            _remainingSeconds = 0;
            _finishSession();
          }
        });
      }
    });
  }

  Future<void> _finishSession() async {
    _timer?.cancel();
    await _setSessionStatus(false, null);

    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .update({'studyTime': FieldValue.increment(widget.durationMinutes)});

    if (mounted) {
      Navigator.pop(context); 
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
      await _setSessionStatus(false, null);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Format Time: 05:30
    String timeText =
        "${(_remainingSeconds ~/ 60).toString().padLeft(2, '0')}:${(_remainingSeconds % 60).toString().padLeft(2, '0')}";

    double progress = 1.0 - (_remainingSeconds / _totalSeconds);

    // We use this widget to stop the user from accidentally going back
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                "FOCUS MODE",
                style: TextStyle(color: Colors.grey, letterSpacing: 2),
              ),
              const SizedBox(height: 40),

              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 250,
                    height: 250,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 15,
                      backgroundColor: AppColors.cardOverlay,
                      color: Colors.blueAccent,
                    ),
                  ),
                  Text(
                    timeText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 60,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 60),

              // Companion Toggle Indicator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.greenAccent.withOpacity(0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.link, color: Colors.greenAccent, size: 16),
                    SizedBox(width: 8),
                    Text("Companion Control Active", style: TextStyle(color: Colors.greenAccent, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 40),

              // Controls
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Pause/Resume
                  FloatingActionButton(
                    backgroundColor: Colors.white,
                    onPressed: () {
                      setState(() {
                        _isPaused = !_isPaused;
                        if (_isPaused) {
                          // Timer stopped by _startTimer check, just need to record state
                        } else {
                          // Resuming: recalculate _endTime based on current _remainingSeconds
                          _endTime = DateTime.now().add(Duration(seconds: _remainingSeconds));
                          _setSessionStatus(true, _endTime);
                        }
                      });
                    },
                    child: Icon(_isPaused ? Icons.play_arrow : Icons.pause, color: Colors.black),
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
            ],
          ),
        ),
      ),
    );
  }
}
