import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:focus_mate/theme/app_colors.dart';
import 'package:focus_mate/theme/app_theme.dart';

class WaitingForCompanionPage extends StatefulWidget {
  final String sessionId;
  final String userId;

  const WaitingForCompanionPage({
    super.key,
    required this.sessionId,
    required this.userId,
  });

  @override
  State<WaitingForCompanionPage> createState() =>
      _WaitingForCompanionPageState();
}

class _WaitingForCompanionPageState extends State<WaitingForCompanionPage> {
  late StreamSubscription _sessionSubscription;
  bool _isSelfCancelling = false;

  @override
  void initState() {
    super.initState();
    _listenForSessionUpdate();
  }

  @override
  void dispose() {
    _sessionSubscription.cancel();
    super.dispose();
  }

  void _listenForSessionUpdate() {
    _sessionSubscription = FirebaseFirestore.instance
        .collection('companion_sessions')
        .doc(widget.sessionId)
        .snapshots()
        .listen((snapshot) {
          if (!mounted) return;
          if (snapshot.exists) {
            final data = snapshot.data()!;
            final status = data['status'];

            if (status == 'ACTIVE') {
              // Declarative routing: pop to root, let DashboardRouter show CompanionControlledPage
              Navigator.popUntil(context, (route) => route.isFirst);
            } else if (status == 'REJECTED' || status == 'CANCELLED') {
              // If we initiated the cancel, don't pop again (manual pop handles it)
              if (_isSelfCancelling && status == 'CANCELLED') return;

              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("Session $status by companion")),
              );
            }
          }
        });
  }

  Future<void> _cancelRequest() async {
    setState(() => _isSelfCancelling = true);
    try {
      await FirebaseFirestore.instance
          .collection('companion_sessions')
          .doc(widget.sessionId)
          .update({
            'status': 'CANCELLED',
            'endedAt': FieldValue.serverTimestamp(),
          });
      // Navigation is handled by the listener, but we pop here for responsiveness
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _isSelfCancelling = false); // Reset if failed
      debugPrint("Error cancelling request: $e");
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to cancel request")),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1. Theme Detection
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      child: Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text(
          "Request Sent",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        centerTitle: true,
        elevation: 0,
        automaticallyImplyLeading: false, // Don't allow back without cancelling
      ),
      body: Container(
        // Gradient Background
        decoration: AppTheme.screenBackground(
          context,
          AppColors.roleGradients['user']!,
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Glass Card
                  Container(
                    padding: const EdgeInsets.all(40),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.white70,
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(
                        color: isDark ? Colors.white10 : Colors.black12,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const SizedBox(
                          width: 60,
                          height: 60,
                          child: CircularProgressIndicator(
                            color: Colors.cyanAccent,
                            strokeWidth: 4,
                          ),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          "Waiting for Response",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          "Your companion has been notified.\nSession will start once they accept.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 48),

                  // Cancel Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: TextButton(
                      onPressed: _cancelRequest,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: Colors.redAccent.withValues(alpha: 0.3),
                          ),
                        ),
                      ),
                      child: const Text(
                        "Cancel Request",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }
}
