import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AnalyticsScreen extends StatelessWidget {
  final String userId;
  final String userName;

  const AnalyticsScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  String formatTime(int mins) {
    if (mins < 60) return "${mins}m";
    int h = mins ~/ 60;
    int m = mins % 60;
    return "${h}h ${m}m";
  }

  @override
  Widget build(BuildContext context) {
    final todayDocId = DateTime.now().toIso8601String().split('T')[0];

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: Text("${userName}'s Usage"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),

      // 🔥 LIVE DATA DIRECTLY
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('daily_stats')
            .doc(todayDocId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.cyanAccent),
            );
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(
              child: Text(
                "No usage data for today yet.",
                style: TextStyle(color: Colors.white54, fontSize: 16),
              ),
            );
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final totalMinutes = data['totalScreenTime'] ?? 0;
          final appsUsed = List<Map<String, dynamic>>.from(data['apps'] ?? []);

          return Column(
            children: [
              // SUMMARY CARD
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
                      todayDocId,
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

              // 🔥 APP LIST WITH LOGOS
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
                              leading: CircleAvatar(
                                backgroundColor: Colors.white10,
                                child:
                                    // 🔥🔥 LOGO / ICON FETCHING ADDED HERE 🔥🔥
                                    (app['iconBytes'] != null &&
                                            app['iconBytes'] is String)
                                        ? ClipOval(
                                            child: Image.memory(
                                              base64Decode(app['iconBytes']),
                                              fit: BoxFit.cover,
                                              width: 40,
                                              height: 40,
                                            ),
                                          )
                                        : Text(
                                            appName.isNotEmpty
                                                ? appName[0].toUpperCase()
                                                : "?",
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
          );
        },
      ),
    );
  }
}
