import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:focus_mate/core/auth_service.dart';
import '../core/widgets/custom_button.dart';

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isEmailVerified = false;
  Timer? _timer;
  bool _isResending = false;
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    _isEmailVerified = _auth.currentUser?.emailVerified ?? false;

    if (!_isEmailVerified) {
      // Periodically check if the user has verified their email
      _timer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => _checkEmailVerified(),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _checkEmailVerified() async {
    final user = _auth.currentUser;
    if (user != null) {
      try {
        await user.reload(); // Refresh user data from Firebase
      } on FirebaseAuthException catch (e) {
        if (e.code == 'network-request-failed') {
          return; // Suppress offline connectivity spam in background loop
        }
        rethrow;
      }
      if (mounted) {
        setState(() {
          _isEmailVerified = _auth.currentUser?.emailVerified ?? false;
        });
      }

      if (_isEmailVerified) {
        _timer?.cancel();
        // Since Firebase stream in AuthGate listens to userChanges(),
        // it should automatically rebuild and push us to Dashboard
      }
    }
  }

  Future<void> _resendVerificationEmail() async {
    setState(() => _isResending = true);
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await user.sendEmailVerification();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Verification email resent. Check your inbox."),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isResending = false);
      }
    }
  }

  Future<void> _manualCheck() async {
    setState(() => _isChecking = true);
    await _checkEmailVerified();
    if (!_isEmailVerified && mounted) {
      setState(() => _isChecking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Email not verified yet. Please check your inbox."),
          backgroundColor: Colors.orangeAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = _auth.currentUser;

    return Scaffold(
      body: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [const Color(0xFF1A1F35), const Color(0xFF0B0E17)]
                : [const Color(0xFFF8FAFC), const Color(0xFFE2E8F0)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.mark_email_unread_outlined,
                    size: 100,
                    color: Colors.cyanAccent,
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    "Verify your email",
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "We've sent a verification email to:\n${user?.email ?? 'your email'}",
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white.withValues(alpha: 0.8),
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Please check your inbox and click the link to verify your account.",
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),
                  SizedBox(
                    width: double.infinity,
                    child: CustomButton(
                      text: "I've Verified (Refresh)",
                      onPressed: _isChecking ? null : _manualCheck,
                      isLoading: _isChecking,
                      color: Colors.cyanAccent,
                      textColor: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: Colors.cyanAccent),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _isResending ? null : _resendVerificationEmail,
                      child: _isResending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.cyanAccent,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              "Resend Email",
                              style: TextStyle(
                                color: Colors.cyanAccent,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  TextButton.icon(
                    onPressed: () => AuthService().signOut(),
                    icon: const Icon(Icons.arrow_back, color: Colors.white54),
                    label: const Text(
                      "Cancel",
                      style: TextStyle(color: Colors.white54, fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
