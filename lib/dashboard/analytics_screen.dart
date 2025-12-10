import 'dart:convert'; // For base64Decode
import 'dart:typed_data'; // For Uint8List

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

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
              appsUsed.sort(
                (a, b) =>
                    (b['usageMinutes'] ?? 0).compareTo(a['usageMinutes'] ?? 0),
              );
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
      final query = await statsRef
          .orderBy('lastUpdated', descending: true)
          .limit(7)
          .get();
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
    // 1. Theme Detection
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true, 
      backgroundColor: Colors.transparent, // Important for gradient
      appBar: AppBar(
        title: Text("${widget.userName}'s Insights"),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black87),
        titleTextStyle: TextStyle(
          color: isDark ? Colors.white : Colors.black87,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      body: Stack(
        children: [
          // 2. Gradient Background
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

          // 3. Content
          loading
            ? const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))
            : SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Summary Row
                      Row(
                        children: [
                          Expanded(
                            child: _buildInfoCard(
                              "Today",
                              formatTime(totalMinutes),
                              Icons.today,
                              Colors.blueAccent,
                              isDark,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildInfoCard(
                              "Weekly Avg",
                              formatTime(weeklyAverage),
                              Icons.calendar_view_week,
                              Colors.purpleAccent,
                              isDark,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Top Distraction Card
                      if (topApp != null)
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withOpacity(0.05) : Colors.white70,
                             borderRadius: BorderRadius.circular(24),
                             border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                             boxShadow: [
                               BoxShadow(
                                 color: Colors.redAccent.withOpacity(0.1),
                                 blurRadius: 20,
                                 offset: const Offset(0, 10),
                               )
                             ]
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.withOpacity(0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.warning_amber_rounded,
                                  color: Colors.redAccent,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      "Top Distraction",
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.1,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      topApp!['appName'],
                                      style: TextStyle(
                                        color: isDark ? Colors.white : Colors.black87,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
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
                                    style: const TextStyle(
                                      color: Colors.redAccent,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: _buildAppIcon(topApp!),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                      const SizedBox(height: 32),
                       Text(
                        "DETAILED BREAKDOWN",
                        style: TextStyle(
                          color: isDark ? Colors.cyanAccent : Colors.teal,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // App List
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: appsUsed.length,
                        itemBuilder: (context, index) {
                          final app = appsUsed[index];
                          final minutes = app['usageMinutes'] ?? 0;
                          final appName = app['appName'] ?? "Unknown";

                          double percent = totalMinutes > 0
                              ? (minutes / totalMinutes)
                              : 0.0;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                             decoration: BoxDecoration(
                              color: isDark ? Colors.white.withOpacity(0.05) : Colors.white70,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: _buildAppIcon(app),
                                ),
                                const SizedBox(width: 16),

                                // Name & Bar
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            appName,
                                            style: TextStyle(
                                              color: isDark ? Colors.white : Colors.black87,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                            ),
                                          ),
                                          Text(
                                            formatTime(minutes),
                                            style: TextStyle(
                                              color: isDark ? Colors.white60 : Colors.black54,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          value: percent,
                                          backgroundColor: isDark ? Colors.white10 : Colors.black12,
                                          color: index == 0
                                              ? Colors.redAccent
                                              : Colors.blueAccent,
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
              ),
        ],
      ),
    );
  }

  // 🔹 HELPER: BUILD ICON FROM BASE64
  Widget _buildAppIcon(Map<String, dynamic> app) {
    if (app['iconBytes'] != null && app['iconBytes'] is String) {
      try {
        Uint8List bytes = base64Decode(app['iconBytes']);
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.memory(
            bytes,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                _fallbackIcon(app['appName']),
          ),
        );
      } catch (e) {
        return _fallbackIcon(app['appName']);
      }
    }
    return _fallbackIcon(app['appName']);
  }

  Widget _fallbackIcon(String? appName) {
    String letter = (appName != null && appName.isNotEmpty)
        ? appName[0].toUpperCase()
        : "?";
    return Container(
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Text(
          letter,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard(
    String title,
    String value,
    IconData icon,
    Color color,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.white70,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
        boxShadow: [
           BoxShadow(
             color: Colors.black.withOpacity(isDark ? 0.2 : 0.05),
             blurRadius: 16,
             offset: const Offset(0, 8),
           )
        ]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 16),
          Text(title, style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

