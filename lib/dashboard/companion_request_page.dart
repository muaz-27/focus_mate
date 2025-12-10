import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'waiting_for_companion_page.dart';
import '../theme/app_colors.dart';
import '../core/widgets/custom_dialog.dart';

class CompanionRequestPage extends StatefulWidget {
  final String userId;
  final String? companionId;
  final String? companionName;

  const CompanionRequestPage({
    super.key,
    required this.userId,
    this.companionId,
    this.companionName,
  });

  @override
  State<CompanionRequestPage> createState() => _CompanionRequestPageState();
}

class _CompanionRequestPageState extends State<CompanionRequestPage> {
  final List<int> _durationOptions = [15, 30, 45, 60, 90, 120];
  int _selectedDuration = 60;
  final TextEditingController _goalController = TextEditingController();
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Request Companion Session"),
        backgroundColor: AppColors.cardOverlay,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            TextField(
              controller: _goalController,
              decoration: InputDecoration(
                hintText: "Study goal (optional)",
                hintStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: Colors.white12,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              children: _durationOptions.map((minutes) {
                final isSelected = _selectedDuration == minutes;
                return ChoiceChip(
                  label: Text("$minutes min"),
                  selected: isSelected,
                  selectedColor: Colors.blueAccent,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey,
                  ),
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _selectedDuration = minutes);
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _requestCompanionSession,
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("Request Session"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _requestCompanionSession() async {
    if (widget.companionId == null) return;

    setState(() => _isLoading = true);
    try {
      // 1. Check for existing pending or active sessions
      // 1. Check for existing pending or active sessions
      final existingParams = await FirebaseFirestore.instance
          .collection('companion_sessions')
          .where('userId', isEqualTo: widget.userId)
          .where('status', whereIn: ['REQUESTED', 'ACTIVE'])
          .get();

      // Filter out stale requests (older than 30 mins)
      DocumentSnapshot? blockingDoc;
      final now = DateTime.now();

      for (var doc in existingParams.docs) {
        final data = doc.data();
        if (data['status'] == 'ACTIVE') {
          blockingDoc = doc;
          break;
        } else if (data['status'] == 'REQUESTED') {
          final requestedAt = (data['requestedAt'] as Timestamp?)?.toDate();
          if (requestedAt != null && now.difference(requestedAt).inMinutes < 30) {
            blockingDoc = doc;
            break;
          }
        }
      }

      if (blockingDoc != null) {
        if (!mounted) return;
        
        // Show dialog with option to kill the zombie session
        final shouldEnd = await showCustomDialog<bool>(
          context: context,
          title: "Session Already Active",
          content: Text(
              "You have a session currently ${(blockingDoc.data() as Map<String, dynamic>)['status']}. Do you want to end it and start a new one?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text("End & Continue", style: TextStyle(color: Colors.white)),
            ),
          ],
        );

        if (shouldEnd == true) {
           await blockingDoc.reference.update({
             'status': 'ENDED',
             'endedAt': FieldValue.serverTimestamp(),
             'endedBy': 'override_new_request'
           });
           // Proceed to create new session below...
        } else {
           return; // User cancelled
        }
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();
      final userData = userDoc.data()!;

      final sessionRef =
          FirebaseFirestore.instance.collection('companion_sessions').doc();

      await sessionRef.set({
        'id': sessionRef.id,
        'userId': widget.userId,
        'userName': userData['name'],
        'companionId': widget.companionId,
        'companionName': widget.companionName,
        'status': 'REQUESTED',
        'requestedAt': FieldValue.serverTimestamp(),
        'duration': _selectedDuration,
        'studyGoal': _goalController.text.isNotEmpty
            ? _goalController.text
            : null,
        'lockedApps': [],
        'manuallyUnlockedApps': [],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => WaitingForCompanionPage(
            sessionId: sessionRef.id,
            userId: widget.userId,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}