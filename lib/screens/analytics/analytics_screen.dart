import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:focus_mate/screens/quiz/quiz_history_screen.dart';
import 'package:focus_mate/theme/app_colors.dart';
import 'package:focus_mate/theme/app_theme.dart';
import '../../core/widgets/app_icon_widget.dart';

class AnalyticsScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final Future<void> Function()? onUnlink;

  const AnalyticsScreen({
    super.key,
    required this.userId,
    required this.userName,
    this.onUnlink,
  });

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  int totalMinutes = 0;
  int weeklyAverage = 0;
  Map<String, String> _iconLookup = {};
  Map<String, dynamic>? topApp;
  List<Map<String, dynamic>> appsUsed = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  /// Fetches icons for the specific apps being displayed from the app_icons subcollection.
  Future<void> _fetchIconsForApps(List<Map<String, dynamic>> apps) async {
    if (apps.isEmpty) return;

    // Identify packages that need icons and aren't already in lookup
    final packagesNeeded = apps
        .map((a) => a['packageName'] as String)
        .where((pkg) => !_iconLookup.containsKey(pkg))
        .toSet()
        .toList();

    if (packagesNeeded.isEmpty) return;

    try {
      final iconCollection = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('app_icons');

      // Firestore 'whereIn' is limited to 10 or 30. safely 10.
      int batchSize = 10;
      for (var i = 0; i < packagesNeeded.length; i += batchSize) {
        final end = (i + batchSize < packagesNeeded.length)
            ? i + batchSize
            : packagesNeeded.length;
        final chunk = packagesNeeded.sublist(i, end);

        final snapshot = await iconCollection
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        if (mounted) {
          setState(() {
            for (var doc in snapshot.docs) {
              if (doc.data().containsKey('icon')) {
                _iconLookup[doc.id] = doc.data()['icon'];
              }
            }
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching icons: $e");
    }
  }

  /// Refreshes daily statistics and calculates weekly average.
  Future<void> _refreshData() async {
    final todayDocId = DateTime.now().toIso8601String().split('T')[0];
    final statsRef = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .collection('daily_stats');

    // Fetch Today's Stats
    try {
      final snapshot = await statsRef.doc(todayDocId).get();

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
              try {
                topApp = appsUsed.firstWhere(
                  (app) =>
                      app['packageName'] != 'com.example.focus_mate' &&
                      app['appName'] != 'FocusMate',
                );
              } catch (e) {
                topApp = null;
              }
            } else {
              topApp = null;
            }
          });

          // Fetch icons for these apps
          _fetchIconsForApps(appsUsed);
        } else {
          setState(() {
            totalMinutes = 0;
            appsUsed = [];
            topApp = null;
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching analytics: $e");
    }

    // Fetch Weekly History
    await _calculateWeeklyAvg(statsRef);

    if (mounted) {
      setState(() => loading = false);
    }
  }

  /// Calculates the average daily screen time over the last 7 days.
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
    } catch (e) {
      debugPrint("Error calculating weekly average: $e");
    }
  }

  String formatTime(int mins) {
    if (mins < 60) return "${mins}m";
    int h = mins ~/ 60;
    int m = mins % 60;
    return "${h}h ${m}m";
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
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
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: TextButton.icon(
              icon: const Icon(Icons.quiz_outlined, size: 20),
              label: const Text('Quizzes'),
              style: TextButton.styleFrom(
                foregroundColor: isDark ? Colors.white : Colors.black87,
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => QuizHistoryScreen(
                      userId: widget.userId,
                      isReadOnly: true,
                    ),
                  ),
                );
              },
            ),
          ),
          if (widget.onUnlink != null)
            IconButton(
              icon: const Icon(Icons.link_off, color: Colors.redAccent),
              tooltip: "Unlink Student",
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                    title: Text(
                      'Unlink Student?',
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                    ),
                    content: Text(
                      'This will remove your connection with ${widget.userName}. They will need to re-link using your code.',
                      style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                        child: const Text('Unlink', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                );

                if (confirm == true && mounted) {
                  await widget.onUnlink!();
                  if (mounted) Navigator.pop(context); // Go back after unlinking
                }
              },
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => loading = true);
              _refreshData();
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          Container(
            height: double.infinity,
            width: double.infinity,
            decoration: AppTheme.screenBackground(
              context,
              AppColors.roleGradients['user']!,
            ),
          ),

          loading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.cyanAccent),
                )
              : SafeArea(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      await _refreshData();
                    },
                    color: Colors.cyanAccent,
                    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
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

                          if (topApp != null)
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.05)
                                    : Colors.white70,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: Colors.redAccent.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.redAccent.withValues(
                                      alpha: 0.1,
                                    ),
                                    blurRadius: 20,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.redAccent.withValues(
                                        alpha: 0.2,
                                      ),
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                           Text(
                                          "Top Distraction",
                                           style: TextStyle(
                                            color: isDark ? Colors.grey[400] : Colors.grey.shade600,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 1.1,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          topApp!['appName'],
                                          style: TextStyle(
                                            color: isDark
                                                ? Colors.white
                                                : Colors.black87,
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
                                        child: AppIconWidget(
                                          packageName: topApp!['packageName'],
                                          appName: topApp!['appName'],
                                          iconBytes:
                                              topApp!['iconBytes'] is Uint8List
                                              ? topApp!['iconBytes']
                                              : null,
                                          iconBase64:
                                              (topApp!['iconBytes'] is String)
                                              ? topApp!['iconBytes']
                                              : _iconLookup[topApp!['packageName']],
                                          size: 28,
                                        ),
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
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.05)
                                      : Colors.white70,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isDark
                                        ? Colors.white10
                                        : Colors.black12,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 40,
                                      height: 40,
                                      child: AppIconWidget(
                                        packageName: app['packageName'],
                                        appName: appName,
                                        iconBytes: app['iconBytes'] is Uint8List
                                            ? app['iconBytes']
                                            : null,
                                        iconBase64: (app['iconBytes'] is String)
                                            ? app['iconBytes']
                                            : _iconLookup[app['packageName']],
                                        size: 40,
                                      ),
                                    ),
                                    const SizedBox(width: 16),

                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  appName,
                                                  overflow: TextOverflow.ellipsis,
                                                  maxLines: 1,
                                                  style: TextStyle(
                                                    color: isDark
                                                        ? Colors.white
                                                        : Colors.black87,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 15,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                formatTime(minutes),
                                                style: TextStyle(
                                                  color: isDark
                                                      ? Colors.white60
                                                      : Colors.black54,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            child: LinearProgressIndicator(
                                              value: percent,
                                              backgroundColor: isDark
                                                  ? Colors.white10
                                                  : Colors.black12,
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
                ),
        ],
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
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white70,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              color: isDark ? Colors.white54 : Colors.black54,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
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
