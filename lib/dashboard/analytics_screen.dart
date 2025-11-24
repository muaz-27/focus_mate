import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AnalyticsScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const AnalyticsScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  int totalMinutes = 0;
  List<Map<String, dynamic>> appsUsed = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadUsage();
  }

  // Listen to Realtime Changes from Firebase
  void _loadUsage() {
    final todayDocId = DateTime.now().toIso8601String().split('T')[0];

    FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .collection('daily_stats')
        .doc(todayDocId)
        .snapshots()
        .listen((snapshot) {
          if (mounted) {
            if (snapshot.exists) {
              final data = snapshot.data()!;
              setState(() {
                totalMinutes = data['totalScreenTime'] ?? 0;
                appsUsed = List<Map<String, dynamic>>.from(data['apps'] ?? []);
                loading = false;
              });
            } else {
              setState(() {
                totalMinutes = 0;
                appsUsed = [];
                loading = false;
              });
            }
          }
        });
  }

  String formatTime(int mins) {
    if (mins < 60) return "${mins}m";
    int h = mins ~/ 60;
    int m = mins % 60;
    return "${h}h ${m}m";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212), // Dark Background
      appBar: AppBar(
        title: Text("${widget.userName}'s Usage"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.cyanAccent),
            )
          : Column(
              children: [
                // 1. Big Summary Card
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.blue.shade900, Colors.purple.shade900],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const Text(
                        "Total Screen Time",
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        formatTime(totalMinutes),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        DateTime.now().toString().split(' ')[0],
                        style: const TextStyle(
                          color: Colors.white30,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Most Used Apps",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                // 2. App List (Text Icons Only)
                Expanded(
                  child: appsUsed.isEmpty
                      ? const Center(
                          child: Text(
                            "No significant usage yet.",
                            style: TextStyle(color: Colors.white54),
                          ),
                        )
                      : ListView.builder(
                          itemCount: appsUsed.length,
                          padding: const EdgeInsets.only(bottom: 20),
                          itemBuilder: (context, index) {
                            final app = appsUsed[index];
                            final minutes = app['usageMinutes'] ?? 0;
                            final appName = app['appName'] ?? "Unknown";

                            // Get first letter for the icon
                            final firstLetter = appName.isNotEmpty
                                ? appName[0].toUpperCase()
                                : "?";

                            // Dynamic Color based on usage
                            Color usageColor = Colors.cyanAccent;
                            if (minutes > 60) usageColor = Colors.orangeAccent;
                            if (minutes > 120) usageColor = Colors.redAccent;

                            return Container(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                // 🔹 SIMPLE LETTER ICON (No External Packages)
                                leading: CircleAvatar(
                                  backgroundColor: Colors.white10,
                                  child: Text(
                                    firstLetter,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  appName,
                                  style: const TextStyle(color: Colors.white),
                                ),
                                trailing: Text(
                                  formatTime(minutes),
                                  style: TextStyle(
                                    color: usageColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
