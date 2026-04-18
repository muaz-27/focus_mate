import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:focus_mate/screens/companion/waiting_for_companion_page.dart';
import 'package:focus_mate/core/widgets/custom_dialog.dart';
import 'package:flutter/cupertino.dart';

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
  int _selectedDuration = 60;
  final TextEditingController _goalController = TextEditingController();
  bool _isLoading = false;

  String _formatDuration(int minutes) {
    if (minutes < 60) return "${minutes}m";
    final int hours = minutes ~/ 60;
    final int mins = minutes % 60;
    if (mins == 0) return "${hours}h";
    return "${hours}h ${mins}m";
  }

  void _showDurationPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B), // Match dark theme
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          height: 300,
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // Handle bar
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 20),
              const Text("Select Duration", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              Expanded(
                child: CupertinoTheme(
                  data: const CupertinoThemeData(
                    brightness: Brightness.dark,
                    textTheme: CupertinoTextThemeData(
                      pickerTextStyle: TextStyle(color: Colors.white, fontSize: 24),
                    ),
                  ),
                  child: CupertinoTimerPicker(
                    mode: CupertinoTimerPickerMode.hm,
                    initialTimerDuration: Duration(minutes: _selectedDuration),
                    onTimerDurationChanged: (Duration newDuration) {
                        if (newDuration.inMinutes >= 15) {
                          setState(() => _selectedDuration = newDuration.inMinutes);
                        }
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 1. Theme Detection
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true, 
      backgroundColor: Colors.transparent, // Important for gradient to show
      appBar: AppBar(
        title: const Text("Request Session", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          // 2. Gradient Background (Matches Dashboard) - Full Screen
          Container(
            height: double.infinity,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark 
                  ? [const Color(0xFF1A1F35), const Color(0xFF0B0E17)] 
                  : [const Color(0xFFF8FAFC), const Color(0xFFE2E8F0)],
              ),
            ),
          ),
          
          // 3. Scrollable Content
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  
                  // 4. Session Name Input (Glassmorphism)
                  Text(
                    "SESSION DETAILS", 
                    style: TextStyle(
                      color: isDark ? Colors.cyanAccent : Colors.teal, 
                      fontSize: 12, 
                      fontWeight: FontWeight.bold, 
                      letterSpacing: 1.2
                    )
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white70,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                    ),
                    child: TextField(
                      controller: _goalController,
                      decoration: InputDecoration(
                        hintText: "Name your session (e.g., Math Study)",
                        hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        prefixIcon: Icon(Icons.edit, color: isDark ? Colors.white54 : Colors.black54, size: 20),
                      ),
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // 5. Duration Selector (Glassmorphism)
                  Text(
                    "DURATION", 
                    style: TextStyle(
                      color: isDark ? Colors.cyanAccent : Colors.teal, 
                      fontSize: 12, 
                      fontWeight: FontWeight.bold, 
                      letterSpacing: 1.2
                    )
                  ),
                  const SizedBox(height: 16),
                  
                  // Tappable Duration Card
                  InkWell(
                    onTap: _showDurationPicker,
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white70,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                      boxShadow: [
                         BoxShadow(
                           color: Colors.black.withValues(alpha: 0.1),
                           blurRadius: 20,
                           offset: const Offset(0, 10),
                         )
                      ]
                    ),
                    child: Column(
                      children: [
                        Text(
                          _formatDuration(_selectedDuration),
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontSize: 48, 
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.touch_app, size: 14, color: isDark ? Colors.cyanAccent : Colors.teal),
                            const SizedBox(width: 6),
                            Text(
                              "Tap to change duration",
                              style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 13),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 48),

                // 5. Action Button (Gradient)
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _requestCompanionSession,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent, // Use Container gradient
                      padding: EdgeInsets.zero,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Colors.cyanAccent, Colors.blueAccent]),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(color: Colors.cyanAccent.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))
                        ],
                      ),
                      child: Container(
                        alignment: Alignment.center,
                        child: _isLoading
                            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Text("Start Request", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ),
                  ),
                ),
                ],
              ),
            ),
          ),
        ],
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

      // Re-check for active sessions right before creating to minimize race window
      final lastCheck = await FirebaseFirestore.instance
          .collection('companion_sessions')
          .where('userId', isEqualTo: widget.userId)
          .where('status', whereIn: ['ACTIVE', 'REQUESTED'])
          .limit(1)
          .get();

      final now2 = DateTime.now();
      final hasBlocking = lastCheck.docs.any((doc) {
        final data = doc.data();
        if (data['status'] == 'ACTIVE') return true;
        final requestedAt = (data['requestedAt'] as Timestamp?)?.toDate();
        return requestedAt != null && now2.difference(requestedAt).inMinutes < 30;
      });

      if (hasBlocking) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("A session was just created. Please wait.")),
          );
        }
        return;
      }

      // Create the new session document atomically
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
    } catch (e) {
      if (e.toString().contains('DUPLICATE_SESSION')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("A session was just created. Please wait.")),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
