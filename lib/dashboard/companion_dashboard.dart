import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/auth_service.dart';
import 'analytics_screen.dart'; // Make sure this is imported!

class CompanionDashboard extends StatefulWidget {
  final Map<String, dynamic> userData;
  final Function onLogout;

  const CompanionDashboard({
    super.key,
    required this.userData,
    required this.onLogout,
  });

  @override
  State<CompanionDashboard> createState() => _CompanionDashboardState();
}

class _CompanionDashboardState extends State<CompanionDashboard> {
  String? linkCode;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _loadLinkCode();
  }

  Future<void> _loadLinkCode() async {
    // 1. Check if code already exists in passed data to avoid network call
    if (widget.userData['linkCode'] != null) {
      setState(() {
        linkCode = widget.userData['linkCode'];
      });
      return;
    }

    // 2. Fetch from DB if missing
    final doc = await _firestore
        .collection('users')
        .doc(widget.userData['id'])
        .get();
    setState(() {
      linkCode = doc.data()?['linkCode'];
    });
  }

  String _generateCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(
      6,
      (index) => chars[Random().nextInt(chars.length)],
    ).join();
  }

  Future<void> _refreshCode() async {
    final code = _generateCode();
    await _firestore.collection('users').doc(widget.userData['id']).update({
      'linkCode': code,
    });
    setState(() {
      linkCode = code;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212), // Dark background
      appBar: AppBar(
        title: const Text(
          "Companion Dashboard",
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: () => AuthService.signOut(context),
            icon: const Icon(Icons.logout, color: Colors.redAccent),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Link Code Card (Improved UI)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4F46E5), Color(0xFF3B82F6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Your Link Code",
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        linkCode ?? "Generating...",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.refresh,
                              color: Colors.white,
                            ),
                            onPressed: _refreshCode,
                          ),
                          if (linkCode != null)
                            IconButton(
                              icon: const Icon(Icons.copy, color: Colors.white),
                              onPressed: () {
                                Clipboard.setData(
                                  ClipboardData(text: linkCode!),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("Code copied!")),
                                );
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
                  const Text(
                    "Share this code with a student to connect.",
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            const Text(
              "Connected Students",
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            // 2. List of Students
            Expanded(
              child: StreamBuilder<DocumentSnapshot>(
                stream: _firestore
                    .collection('users')
                    .doc(widget.userData['id'])
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!snapshot.hasData || !snapshot.data!.exists) {
                    return const Center(child: Text("No data"));
                  }

                  final data = snapshot.data!.data() as Map<String, dynamic>;
                  final linked = List<String>.from(
                    data['linkedStudents'] ?? [],
                  );

                  if (linked.isEmpty) {
                    return Center(
                      child: Text(
                        "No students connected yet.",
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: linked.length,
                    itemBuilder: (context, index) {
                      final studentId = linked[index];

                      // Fetch Student Details
                      return FutureBuilder<DocumentSnapshot>(
                        future: _firestore
                            .collection('users')
                            .doc(studentId)
                            .get(),
                        builder: (context, snap) {
                          if (!snap.hasData) return const SizedBox();

                          final student =
                              snap.data!.data() as Map<String, dynamic>;
                          final studentName = student['name'] ?? "Unknown";

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.blueAccent.withOpacity(
                                  0.2,
                                ),
                                child: Text(
                                  studentName[0].toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.blueAccent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              title: Text(
                                studentName,
                                style: const TextStyle(color: Colors.white),
                              ),
                              subtitle: const Text(
                                "Tap to view usage",
                                style: TextStyle(color: Colors.grey),
                              ),
                              trailing: const Icon(
                                Icons.arrow_forward_ios,
                                size: 16,
                                color: Colors.white54,
                              ),

                              // 🚀 THIS IS THE MAGIC PART
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => AnalyticsScreen(
                                      userId: studentId, // Pass Student ID
                                      userName:
                                          studentName, // Pass Student Name
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
