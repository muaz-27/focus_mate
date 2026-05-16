import 'dart:convert';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:focus_mate/core/schedule_service.dart';
import 'package:focus_mate/theme/app_colors.dart';
import 'package:focus_mate/theme/app_theme.dart';
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
  
  // To keep track of installed apps metadata so we can filter locally on stream update
  List<Map<String, dynamic>> _allApps = [];
  
  // Track requests sent this session
  final Set<String> _pendingPackages = {};

  StreamSubscription? _scheduleSub;
  StreamSubscription<DocumentSnapshot>? _userDocSub;
  StreamSubscription<QuerySnapshot>? _unlockRequestsSub;

  @override
  void initState() {
    super.initState();
    _loadDataAndListen();
    
    _scheduleSub = ScheduleService().getSchedulesStream(widget.studentId).listen((schedules) {
      if (mounted) {
        setState(() {
          _schedules = schedules.where((s) => s.status == 'active').toList();
        });
        // Sync schedules to native when they change
        ScheduleService().syncSchedulesToNative(widget.studentId);
      }
    });

    _listenForUnlockRequests();
  }

  void _listenForUnlockRequests() {
    // Only listen for requests created recently to avoid old ones
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    
    _unlockRequestsSub = _firestore
        .collection('unlock_requests')
        .where('studentId', isEqualTo: widget.studentId)
        .where('parentId', isEqualTo: widget.companionId)
        // Note: avoiding requestedAt inequality filter here to prevent missing composite index errors.
        // We will filter by time in memory.
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      
      final Map<String, Map<String, dynamic>> latestRequests = {};
      
      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final ts = data['requestedAt'] as Timestamp?;
        final date = ts?.toDate() ?? DateTime.now(); // local cache writes have null server timestamps
        
        if (date.isBefore(cutoff)) continue;
        
        final pkg = data['packageName'] as String? ?? '';
        if (pkg.isEmpty) continue;
        
        if (!latestRequests.containsKey(pkg)) {
          latestRequests[pkg] = {'data': data, 'date': date};
        } else {
          final existingDate = latestRequests[pkg]!['date'] as DateTime;
          if (date.isAfter(existingDate)) {
            latestRequests[pkg] = {'data': data, 'date': date};
          }
        }
      }

      final Set<String> newPendingPkgs = {};

      for (final entry in latestRequests.entries) {
        final pkg = entry.key;
        final data = entry.value['data'] as Map<String, dynamic>;
        final status = data['status'] as String? ?? 'pending';

        if (status == 'pending') {
          newPendingPkgs.add(pkg);
        } else if (status == 'approved' || status == 'rejected') {
          if (_pendingPackages.contains(pkg)) {
            if (status == 'approved') {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _showStatusDialog(pkg, true);
              });
            } else {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _showStatusDialog(pkg, false);
              });
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _pendingPackages.clear();
          _pendingPackages.addAll(newPendingPkgs);
        });
      }
    });
  }

  @override
  void dispose() {
    _scheduleSub?.cancel();
    _userDocSub?.cancel();
    _unlockRequestsSub?.cancel();
    super.dispose();
  }

  Future<void> _loadDataAndListen() async {
    try {
      // 1. Fetch app metadata from shards (one time)
      final appsCollection = _firestore.collection('users').doc(widget.studentId).collection('data_v2');
      final shardsSnapshot = await appsCollection.get();
      
      for (var doc in shardsSnapshot.docs) {
        if (doc.data().containsKey('installedApps')) {
          _allApps.addAll(List<Map<String, dynamic>>.from(doc.data()['installedApps']));
        }
      }

      // 2. Fetch App Icons (one time)
      final iconCollection = _firestore.collection('users').doc(widget.studentId).collection('app_icons');
      final iconsSnapshot = await iconCollection.get();
      for (var doc in iconsSnapshot.docs) {
        if (doc.data().containsKey('icon')) {
          _iconMap[doc.id] = doc.data()['icon'];
        }
      }
    } catch (e) {
      debugPrint("Error loading metadata: $e");
    }

    // 3. Listen to user doc for lockedApps changes
    if (mounted) {
      _userDocSub = _firestore.collection('users').doc(widget.studentId).snapshots().listen((userDoc) {
        if (!mounted) return;
        if (!userDoc.exists) {
          setState(() => _isLoading = false);
          return;
        }

        final data = userDoc.data()!;
        _lockedPackageNames = List<String>.from(data['lockedApps'] ?? []);

        setState(() {
          _lockedApps = _allApps
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
      });
    }
  }

  void _showStatusDialog(String packageName, bool approved) {
    String appLabel = packageName;
    if (packageName.startsWith('schedule_')) {
      appLabel = 'Schedule';
    } else {
      final match = _lockedApps.firstWhere(
        (a) => a['packageName'] == packageName,
        orElse: () => {},
      );
      if (match.isNotEmpty) appLabel = match['appName'] as String? ?? packageName;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: (approved ? Colors.green : Colors.redAccent)
                    .withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                approved ? Icons.lock_open_rounded : Icons.lock_rounded,
                color: approved ? Colors.green : Colors.redAccent,
                size: 48,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              approved ? 'Request Approved!' : 'Request Denied',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              approved
                  ? 'Your unlock request for "$appLabel" has been approved.'
                  : 'Your unlock request for "$appLabel" was denied by your companion.',
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black54,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: approved ? Colors.green : Colors.redAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('OK'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _requestUnlock(Map<String, dynamic> app) async {
    final pkg = app['packageName'] as String;
    if (_pendingPackages.contains(pkg)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You already have a pending request for this app.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

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
              child: Text("Cancel", style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey.shade600)),
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
    final pkg = app['packageName'] as String;
    try {
      setState(() {
        _pendingPackages.add(pkg);
      });

      await _firestore.collection('unlock_requests').add({
        'studentId': widget.studentId,
        'studentName': widget.studentName,
        'parentId': widget.companionId,
        'packageName': pkg,
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
        setState(() {
          _pendingPackages.remove(pkg);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to send request: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _requestScheduleUnlock(AppSchedule schedule) async {
    final pkg = 'schedule_${schedule.id}';
    if (_pendingPackages.contains(pkg)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You already have a pending request for this schedule.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

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
              child: Text("Cancel", style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey.shade600)),
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
    final pkg = 'schedule_${schedule.id}';
    try {
      setState(() {
        _pendingPackages.add(pkg);
      });

      await _firestore.collection('unlock_requests').add({
        'studentId': widget.studentId,
        'studentName': widget.studentName,
        'parentId': widget.companionId,
        'packageName': pkg,
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
        setState(() {
          _pendingPackages.remove(pkg);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to send request: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildRequestButton({
    required String packageName,
    required VoidCallback onPressed,
    required Color color,
    required String label,
  }) {
    if (_pendingPackages.contains(packageName)) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.orange,
              ),
            ),
            SizedBox(width: 6),
            Text('Pending',
                style: TextStyle(
                    color: Colors.orange,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.1),
        foregroundColor: color,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(label),
    );
  }

  Widget _buildAppTile(Map<String, dynamic> app, Color textColor, bool isDark) {
    final pkg = app['packageName'] as String;
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
          packageName: pkg,
          appName: app['appName'],
          iconBytes: app['decodedIcon'],
          size: 50,
          fallbackFontSize: 24,
        ),
        title: Text(
          app['appName'] ?? 'Unknown App',
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          "Locked by Companion",
          style: TextStyle(color: isDark ? Colors.white54 : Colors.grey, fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: _buildRequestButton(
          packageName: pkg,
          color: Colors.cyanAccent,
          label: 'Request',
          onPressed: () => _requestUnlock(app),
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
    final pkg = 'schedule_${schedule.id}';

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
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              daysText.isNotEmpty ? daysText : "No specific days", 
              style: TextStyle(color: isDark ? Colors.white54 : Colors.grey, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              timeText, 
              style: TextStyle(color: Colors.amber, fontSize: 13, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        isThreeLine: true,
        trailing: _buildRequestButton(
          packageName: pkg,
          color: Colors.amber,
          label: 'Request',
          onPressed: () => _requestScheduleUnlock(schedule),
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
        decoration: AppTheme.screenBackground(
          context,
          AppColors.roleGradients['user']!,
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