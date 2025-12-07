import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'companion_controlled_page.dart';
import '../theme/app_colors.dart';

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
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => CompanionControlledPage(
                sessionId: widget.sessionId,
                userId: widget.userId,
              ),
            ),
          );
        } else if (status == 'REJECTED' || status == 'CANCELLED') {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Session $status by companion")),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Waiting for Companion"),
        backgroundColor: AppColors.cardOverlay,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            const Text(
              "Waiting for companion to accept...",
              style: TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 10),
            Text(
              "Session ID: ${widget.sessionId.substring(0, 8)}...",
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}