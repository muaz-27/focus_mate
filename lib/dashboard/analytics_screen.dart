import 'dart:convert'; // For base64Decode
import 'dart:typed_data'; // For Uint8List

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
  int weeklyAverage = 0;
  Map<String, dynamic>? topApp;
  List<Map<String, dynamic>> appsUsed = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    final todayDocId = DateTime.now().toIso8601String().split('T')[0];
    final statsRef = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .collection('daily_stats');

    // 1. Listen to TODAY'S usage
    statsRef.doc(todayDocId).snapshots().listen((snapshot) {
      if (mounted) {
        if (snapshot.exists) {
          final data = snapshot.data()!;
          setState(() {
            totalMinutes = data['totalScreenTime'] ?? 0;
            appsUsed = List<Map<String, dynamic>>.from(data['apps'] ?? []);
            
            if (appsUsed.isNotEmpty) {
               appsUsed.sort((a, b) => (b['usageMinutes'] ?? 0).compareTo(a['usageMinutes'] ?? 0));
               topApp = appsUsed.first;
            } else {
              topApp = null;
            }
            loading = false;
          });
        } else {
          setState(() {
            totalMinutes = 0;
            appsUsed = [];
            topApp = null;
            loading = false;
          });
        }
      }
    });

    // 2. Fetch Weekly History
    _calculateWeeklyAvg(statsRef);
  }

  Future<void> _calculateWeeklyAvg(CollectionReference statsRef) async {
    try {
      final query = await statsRef.orderBy('lastUpdated', descending: true).limit(7).get();
      if (query.docs.isEmpty) return;
      int sum = 0;
      for (var doc in query.docs) {
        sum += (doc['totalScreenTime'] as int? ?? 0);
      }
      if (mounted) {
        setState(() {
          weeklyAverage = (sum / query.docs.length).round();
        });
      }
    } catch (e) {}
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
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: Text("${widget.userName}'s Insights"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Summary Row
                  Row(
                    children: [
                      Expanded(
                        child: _buildInfoCard("Today", formatTime(totalMinutes), Icons.today, Colors.blueAccent),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildInfoCard("Weekly Avg", formatTime(weeklyAverage), Icons.calendar_view_week, Colors.purpleAccent),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Top Distraction Card
                  if (topApp != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("Top Distraction", style: TextStyle(color: Colors.grey, fontSize: 12)),
                                Text(
                                  topApp!['appName'],
                                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                formatTime(topApp!['usageMinutes']),
                                style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              const SizedBox(height: 4),
                              // 🔹 TOP APP ICON
                              SizedBox(
                                width: 24, height: 24,
                                child: _buildAppIcon(topApp!),
                              )
                            ],
                          )
                        ],
                      ),
                    ),

                  const SizedBox(height: 24),
                  const Text("Detailed Breakdown", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),

                  // App List
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: appsUsed.length,
                    itemBuilder: (context, index) {
                      final app = appsUsed[index];
                      final minutes = app['usageMinutes'] ?? 0;
                      final appName = app['appName'] ?? "Unknown";

                      double percent = totalMinutes > 0 ? (minutes / totalMinutes) : 0.0;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            // 🔹 LIST ITEM ICON
                            SizedBox(
                              width: 40, height: 40,
                              child: _buildAppIcon(app),
                            ),
                            const SizedBox(width: 12),
                            
                            // Name & Bar
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(appName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                                      Text(formatTime(minutes), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: percent,
                                      backgroundColor: Colors.white10,
                                      color: index == 0 ? Colors.redAccent : Colors.blueAccent,
                                      minHeight: 6,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
    );
  }

  // 🔹 HELPER: BUILD ICON FROM BASE64
  Widget _buildAppIcon(Map<String, dynamic> app) {
    if (app['iconBytes'] != null && app['iconBytes'] is String) {
      try {
        Uint8List bytes = base64Decode(app['iconBytes']);
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            bytes,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => _fallbackIcon(app['appName']),
          ),
        );
      } catch (e) {
        return _fallbackIcon(app['appName']);
      }
    }
    return _fallbackIcon(app['appName']);
  }

  Widget _fallbackIcon(String? appName) {
    String letter = (appName != null && appName.isNotEmpty) ? appName[0].toUpperCase() : "?";
    return Container(
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          letter,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildInfoCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}