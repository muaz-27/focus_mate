import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

  @override
  void initState() {
    super.initState();
    _totalSeconds = widget.durationMinutes * 60;
    _remainingSeconds = _totalSeconds;
    _setSessionStatus(true); // 🟢 Tell Companion we started
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
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
      if (mounted) {
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
    await _setSessionStatus(false); // 🔴 Tell Companion we finished

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
    bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Give Up?"),
        content: const Text("Your session won't be counted."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("I Quit", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
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

    // 🔒 PopScope prevents using the Android Back Button
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
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
                      backgroundColor: Colors.grey[900],
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

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.redAccent),
                    foregroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(
                      vertical: 15,
                      horizontal: 30,
                    ),
                  ),
                  onPressed: _giveUp,
                  child: const Text("GIVE UP"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
