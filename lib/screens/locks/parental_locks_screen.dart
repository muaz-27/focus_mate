import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:focus_mate/core/schedule_service.dart';
import '../../core/widgets/app_icon_widget.dart';

/// Screen where students can view apps currently locked by their companion/parent
/// and submit unlock requests with a reason.
class ParentalLocksScreen extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String companionId;

  const ParentalLocksScreen({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.companionId,
  });

  @override
  State<ParentalLocksScreen> createState() => _ParentalLocksScreenState();
}

class _ParentalLocksScreenState extends State<ParentalLocksScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = true;
  List<Map<String, dynamic>> _lockedApps = [];
  List<AppSchedule> _schedules = [];
  List<String> _lockedPackageNames = [];
  Map<String, String> _iconMap = {};
  
  StreamSubscription? _scheduleSub;

  @override
  void initState() {
    super.initState();
    _loadLockedApps();
    
    _scheduleSub = ScheduleService().getSchedulesStream(widget.studentId).listen((schedules) {
      if (mounted) {
        setState(() {
          _schedules = schedules.where((s) => s.status == 'active').toList();
        });
      }
    });
  }

  @override
  void dispose() {
    _scheduleSub?.cancel();
    super.dispose();
  }

  Future<void> _loadLockedApps() async {
    try {
      // 1. Fetch current lock state from user doc
      final userDoc = await _firestore.collection('users').doc(widget.studentId).get();
      if (!userDoc.exists) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final data = userDoc.data()!;
      _lockedPackageNames = List<String>.from(data['lockedApps'] ?? []);

      if (_lockedPackageNames.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // 2. Fetch app metadata from shards
      final appsCollection = _firestore.collection('users').doc(widget.studentId).collection('data_v2');
      final shardsSnapshot = await appsCollection.get();
      List<Map<String, dynamic>> allApps = [];

      for (var doc in shardsSnapshot.docs) {
        if (doc.data().containsKey('installedApps')) {
          allApps.addAll(List<Map<String, dynamic>>.from(doc.data()['installedApps']));
        }
      }

      // 3. Fetch App Icons
      final iconCollection = _firestore.collection('users').doc(widget.studentId).collection('app_icons');
      final iconsSnapshot = await iconCollection.get();
      for (var doc in iconsSnapshot.docs) {
        if (doc.data().containsKey('icon')) {
          _iconMap[doc.id] = doc.data()['icon'];
        }
      }

      // 4. Filter to only locked apps and decode icons
      if (mounted) {
        setState(() {
          _lockedApps = allApps
              .where((app) => _lockedPackageNames.contains(app['packageName']))
              .map((app) {
                final newApp = Map<String, dynamic>.from(app);
                final pkg = newApp['packageName'];
                final iconBase64 = _iconMap[pkg] ?? newApp['iconBytes'];
                
                if (iconBase64 != null && iconBase64 is String) {
                  try {
                    newApp['decodedIcon'] = base64Decode(iconBase64);
                  } catch (_) {}
                }
                return newApp;
              }).toList();
              
          _lockedApps.sort((a, b) => 
            (a['appName'] as String).toLowerCase().compareTo((b['appName'] as String).toLowerCase())
          );
          
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading locked apps: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _requestUnlock(Map<String, dynamic> app) async {
    final reasonController = TextEditingController();
    
    await showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          title: Text("Request Unlock", style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Why do you need to unlock ${app['appName']}?",
                style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                decoration: InputDecoration(
                  hintText: "Enter your reason...",
                  hintStyle: TextStyle(color: isDark ? Colors.white30 : Colors.black26),
                  filled: true,
                  fillColor: isDark ? Colors.black26 : Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                final reason = reasonController.text.trim();
                if (reason.isEmpty) return;
                
                Navigator.pop(ctx);
                await _submitUnlockRequest(app, reason);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent),
              child: const Text("Submit", style: TextStyle(color: Colors.black)),
            ),
          ],
        );
      }
    );
  }

  Future<void> _submitUnlockRequest(Map<String, dynamic> app, String reason) async {
    try {
      await _firestore.collection('unlock_requests').add({
        'studentId': widget.studentId,
        'studentName': widget.studentName,
        'parentId': widget.companionId,
        'packageName': app['packageName'],
        'appName': app['appName'],
        'reason': reason,
        'status': 'pending',
        'requestedAt': FieldValue.serverTimestamp(),
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Unlock request sent successfully!"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to send request: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _requestScheduleUnlock(AppSchedule schedule) async {
    final reasonController = TextEditingController();
    
    await showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          title: Text("Request Unlock", style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Why do you need to unlock the schedule '${schedule.name}'?",
                style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                decoration: InputDecoration(
                  hintText: "Enter your reason...",
                  hintStyle: TextStyle(color: isDark ? Colors.white30 : Colors.black26),
                  filled: true,
                  fillColor: isDark ? Colors.black26 : Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                final reason = reasonController.text.trim();
                if (reason.isEmpty) return;
                
                Navigator.pop(ctx);
                await _submitScheduleUnlockRequest(schedule, reason);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
              child: const Text("Submit", style: TextStyle(color: Colors.black)),
            ),
          ],
        );
      }
    );
  }

  Future<void> _submitScheduleUnlockRequest(AppSchedule schedule, String reason) async {
    try {
      await _firestore.collection('unlock_requests').add({
        'studentId': widget.studentId,
        'studentName': widget.studentName,
        'parentId': widget.companionId,
        'packageName': 'schedule_${schedule.id}',
        'appName': 'Schedule: ${schedule.name}',
        'reason': reason,
        'status': 'pending',
        'requestedAt': FieldValue.serverTimestamp(),
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Unlock request sent successfully!"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to send request: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }



  Widget _buildAppTile(Map<String, dynamic> app, Color textColor, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: AppIconWidget(
          packageName: app['packageName'],
          appName: app['appName'],
          iconBytes: app['decodedIcon'],
          size: 50,
          fallbackFontSize: 24,
        ),
        title: Text(
          app['appName'] ?? 'Unknown App',
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          "Locked by Companion",
          style: TextStyle(color: isDark ? Colors.white54 : Colors.grey, fontSize: 12),
        ),
        trailing: ElevatedButton(
          onPressed: () => _requestUnlock(app),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.cyanAccent.withValues(alpha: 0.1),
            foregroundColor: Colors.cyanAccent,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text("Request"),
        ),
      ),
    );
  }

  Widget _buildScheduleTile(AppSchedule schedule, Color textColor, bool isDark) {
    String daysText = schedule.days.map((d) {
      switch (d) {
        case 1: return 'Mon';
        case 2: return 'Tue';
        case 3: return 'Wed';
        case 4: return 'Thu';
        case 5: return 'Fri';
        case 6: return 'Sat';
        case 7: return 'Sun';
        default: return '';
      }
    }).join(', ');
    
    final timeText = "${schedule.startTime.format(context)} - ${schedule.endTime.format(context)}";

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.amber.withValues(alpha: 0.05) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.amber.withValues(alpha: 0.2) : Colors.grey.shade200),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.schedule, color: Colors.amber, size: 28),
        ),
        title: Text(
          schedule.name,
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(daysText.isNotEmpty ? daysText : "No specific days", style: TextStyle(color: isDark ? Colors.white54 : Colors.grey, fontSize: 12)),
            const SizedBox(height: 4),
            Text(timeText, style: TextStyle(color: Colors.amber, fontSize: 13, fontWeight: FontWeight.bold)),
          ],
        ),
        isThreeLine: true,
        trailing: ElevatedButton(
          onPressed: () => _requestScheduleUnlock(schedule),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.amber.withValues(alpha: 0.1),
            foregroundColor: Colors.amber,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text("Request"),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text("Parental Locks", style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
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
          child: _isLoading 
            ? const Center(child: CircularProgressIndicator())
            : (_lockedApps.isEmpty && _schedules.isEmpty)
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_open, size: 64, color: isDark ? Colors.white24 : Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text("No parental locks applied at this time.", style: TextStyle(color: isDark ? Colors.white54 : Colors.grey)),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_lockedApps.isNotEmpty) ...[
                      Text("Instant Locks", style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 18)),
                      const SizedBox(height: 12),
                      ..._lockedApps.map((app) => _buildAppTile(app, textColor, isDark)),
                      const SizedBox(height: 16),
                    ],
                    if (_schedules.isNotEmpty) ...[
                      Text("Scheduled Locks", style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 18)),
                      const SizedBox(height: 12),
                      ..._schedules.map((schedule) => _buildScheduleTile(schedule, textColor, isDark)),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}