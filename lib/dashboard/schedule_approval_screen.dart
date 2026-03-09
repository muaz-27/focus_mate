import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'dart:typed_data';
import '../core/schedule_service.dart';
import '../theme/app_colors.dart';

class ScheduleApprovalScreen extends StatefulWidget {
  final Map<String, dynamic> schedule;
  final String companionId;

  const ScheduleApprovalScreen({
    super.key,
    required this.schedule,
    required this.companionId,
  });

  @override
  State<ScheduleApprovalScreen> createState() => _ScheduleApprovalScreenState();
}

class _ScheduleApprovalScreenState extends State<ScheduleApprovalScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  List<Map<String, dynamic>> _installedApps = [];
  List<String> _selectedApps = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStudentApps();
  }

  Future<void> _loadStudentApps() async {
    try {
      final studentId = widget.schedule['userId'];
      if (studentId == null || studentId.isEmpty) return;

      final appsCollection = _firestore.collection('users').doc(studentId).collection('data_v2');
      final shardsSnapshot = await appsCollection.get();
      List<Map<String, dynamic>> apps = [];

      if (shardsSnapshot.docs.isNotEmpty) {
        for (var doc in shardsSnapshot.docs) {
          if (doc.data().containsKey('installedApps')) {
            final shardApps = List<Map<String, dynamic>>.from(doc.data()['installedApps']);
            apps.addAll(shardApps);
          }
        }
      }

      final iconCollection = _firestore.collection('users').doc(studentId).collection('app_icons');
      final iconsSnapshot = await iconCollection.get();
      Map<String, String> iconMap = {};
      for (var doc in iconsSnapshot.docs) {
         if (doc.data().containsKey('icon')) {
             iconMap[doc.id] = doc.data()['icon'];
         }
      }

      if (mounted) {
        setState(() {
          const ignoredPackages = [
            'android', 'com.android.settings', 'com.android.systemui', 'com.android.vending',
            'com.google.android.gms', 'com.google.android.googlequicksearchbox',
            'com.google.android.inputmethod.latin', 'com.google.android.packageinstaller',
            'com.android.permissioncontroller', 'com.android.shell', 
            'com.android.providers.calendar', 'com.android.providers.contacts',
          ];

          _installedApps = apps.where((app) {
            final pkg = app['packageName'] as String;
            if (pkg == 'com.example.focus_mate') return false;
            if (ignoredPackages.contains(pkg)) return false;
            if (pkg.startsWith('com.android.providers')) return false;
            if (pkg.contains('overlay') || pkg.contains('service')) return false;
            return true;
          }).map((app) {
            final newApp = Map<String, dynamic>.from(app);
            final pkg = newApp['packageName'];
            final iconBase64 = iconMap[pkg] ?? newApp['iconBytes'];
            if (iconBase64 != null && iconBase64 is String) {
              try {
                newApp['decodedIcon'] = base64Decode(iconBase64);
              } catch (_) {}
            }
            return newApp;
          }).toList();
          
          _installedApps.sort((a, b) => (a['appName'] as String).toLowerCase().compareTo((b['appName'] as String).toLowerCase()));
          _selectedApps = List<String>.from(widget.schedule['lockedApps'] ?? []);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _toggleAppSelection(String packageName) {
    setState(() {
      if (_selectedApps.contains(packageName)) {
        _selectedApps.remove(packageName);
      } else {
        _selectedApps.add(packageName);
      }
    });
  }

  Future<void> _approveSchedule() async {
    if (_selectedApps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Select apps to lock first.")));
      return;
    }

    setState(() => _isLoading = true);
    try {
      final studentId = widget.schedule['userId'];
      final scheduleId = widget.schedule['id'];

      await _firestore.collection('users').doc(studentId).collection('schedules').doc(scheduleId).update({
        'lockedApps': _selectedApps,
        'status': 'active',
      });
      
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Widget _fallbackIcon(String appName) {
    String letter = (appName.isNotEmpty) ? appName[0].toUpperCase() : "?";
    return Container(
      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
      child: Center(child: Text(letter, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
    );
  }

  Widget _buildAppIcon(Map<String, dynamic> app) {
    if (app['decodedIcon'] != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          app['decodedIcon'] as Uint8List,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallbackIcon(app['appName'] ?? '?'),
          gaplessPlayback: true, 
        ),
      );
    }
    return _fallbackIcon(app['appName'] ?? '?');
  }

  @override
  Widget build(BuildContext context) {
    final studentName = widget.schedule['userName'] ?? 'Student';
    final scheduleName = widget.schedule['name'] ?? 'Schedule';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text("Approve '$scheduleName'", style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
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
              ? const Center(child: CircularProgressIndicator(color: Colors.amberAccent))
              : Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.amberAccent.withOpacity(0.1),
                        border: Border(bottom: BorderSide(color: Colors.amberAccent.withOpacity(0.3))),
                      ),
                      child: Column(
                        children: [
                          Text("Select apps to lock on $studentName's device during this schedule.",
                             textAlign: TextAlign.center, style: TextStyle(color: textColor)),
                          const SizedBox(height: 8),
                          Text("${_selectedApps.length} apps selected", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          childAspectRatio: 0.8,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemCount: _installedApps.length,
                        itemBuilder: (context, index) {
                          final app = _installedApps[index];
                          final pkg = app['packageName'];
                          final name = app['appName'];
                          final isSelected = _selectedApps.contains(pkg);
                                                
                          return GestureDetector(
                            onTap: () => _toggleAppSelection(pkg),
                            child: Container(
                              decoration: BoxDecoration(
                                color: isSelected ? Colors.amberAccent.withOpacity(0.2) : (isDark ? AppColors.cardOverlay : Colors.white70),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected ? Colors.amberAccent : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      color: Colors.black.withOpacity(0.3),
                                    ),
                                    child: _buildAppIcon(app),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Text(
                                      name,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: textColor, fontSize: 10, fontWeight: FontWeight.w500),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isSelected)
                                    const Icon(Icons.check_circle, color: Colors.amberAccent, size: 12),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: _approveSchedule,
                          icon: const Icon(Icons.check),
                          label: const Text('Approve & Lock Sequence', style: TextStyle(fontSize: 16)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amberAccent,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
