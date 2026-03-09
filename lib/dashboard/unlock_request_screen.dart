import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class UnlockRequestScreen extends StatefulWidget {
  final String userId;
  final String companionId;

  const UnlockRequestScreen({
    super.key,
    required this.userId,
    required this.companionId,
  });

  @override
  State<UnlockRequestScreen> createState() => _UnlockRequestScreenState();
}

class _UnlockRequestScreenState extends State<UnlockRequestScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = false;

  Future<void> _sendSuspendRequest() async {
    setState(() => _isLoading = true);
    try {
      await _firestore.collection('users').doc(widget.userId).collection('unlock_requests').add({
        'companionId': widget.companionId,
        'packageName': 'all',
        'appName': 'Suspend All Locks',
        'status': 'pending',
        'requestedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Request to suspend locks sent.")));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text("Suspend Locks", style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
      ),
      body: Container(
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
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.purpleAccent.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.lock_open_rounded, size: 80, color: Colors.purpleAccent),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    "Need a break from your app locks?",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Send a request to your companion to temporarily suspend all app locks.",
                    style: TextStyle(fontSize: 16, color: Colors.grey[500]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),
                  _isLoading
                      ? const CircularProgressIndicator(color: Colors.purpleAccent)
                      : SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton.icon(
                            onPressed: _sendSuspendRequest,
                            icon: const Icon(Icons.send),
                            label: const Text('Request Unlock', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.purpleAccent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
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
