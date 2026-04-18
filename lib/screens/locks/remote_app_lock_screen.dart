import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:convert';
import 'dart:typed_data';
import '../../core/widgets/app_icon_widget.dart';

class RemoteAppLockScreen extends StatefulWidget {
  final String studentId;
  final String studentName;

  const RemoteAppLockScreen({
    super.key,
    required this.studentId,
    required this.studentName,
  });

  @override
  State<RemoteAppLockScreen> createState() => _RemoteAppLockScreenState();
}

class _RemoteAppLockScreenState extends State<RemoteAppLockScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  List<Map<String, dynamic>> installedApps = [];
  List<String> lockedPackages = [];
  DateTime? lockEndTime;
  bool loading = true;
  int _selectedDuration = 60; // Default 1 hour

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  /// Fetches installed apps from shards and current lock state
  Future<void> _loadData() async {
    try {
      // 1. Fetch Apps from Shards
      final appsCollection = _firestore.collection('users').doc(widget.studentId).collection('data_v2');
      final shardsSnapshot = await appsCollection.get();
      List<Map<String, dynamic>> allApps = [];

      if (shardsSnapshot.docs.isNotEmpty) {
        for (var doc in shardsSnapshot.docs) {
          if (doc.data().containsKey('installedApps')) {
            final shardApps = List<Map<String, dynamic>>.from(doc.data()['installedApps']);
            allApps.addAll(shardApps);
          }
        }
      } else {
        // Fallback or empty
        debugPrint("No sharded app data found for student.");
      }
      
      // Sort alphabetic
      allApps.sort((a, b) => (a['appName'] as String).toLowerCase().compareTo((b['appName'] as String).toLowerCase()));

      // 2. Fetch App Icons
      final iconCollection = _firestore.collection('users').doc(widget.studentId).collection('app_icons');
      final iconsSnapshot = await iconCollection.get();
      Map<String, String> iconMap = {};
      for (var doc in iconsSnapshot.docs) {
         if (doc.data().containsKey('icon')) {
             iconMap[doc.id] = doc.data()['icon'];
         }
      }

      // 3. Fetch Lock State
      final doc = await _firestore.collection('users').doc(widget.studentId).get();
      
      if (mounted) {
        setState(() {
          installedApps = allApps
              .where((app) => app['packageName'] != 'com.example.focus_mate')
              .map((app) {
                final newApp = Map<String, dynamic>.from(app);
                final pkg = newApp['packageName'];
                final iconBase64 = iconMap[pkg] ?? newApp['iconBytes'];
                
                if (iconBase64 != null && iconBase64 is String) {
                  try {
                    newApp['decodedIcon'] = base64Decode(iconBase64);
                  } catch (e) {
                    debugPrint("Error decoding icon for $pkg");
                  }
                }
                return newApp;
              }).toList();
              
          if (doc.exists) {
             final data = doc.data()!;
             lockedPackages = List<String>.from(data['lockedApps'] ?? []);
             if (data['lockEndTime'] != null) {
               lockEndTime = (data['lockEndTime'] as Timestamp).toDate();
             }
          }
          loading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading remote data: $e");
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _toggleLock(String packageName, bool isLocked) async {
    setState(() {
      isLocked ? lockedPackages.add(packageName) : lockedPackages.remove(packageName);
    });

    // Update Firestore
    await _firestore
        .collection('users')
        .doc(widget.studentId)
        .update({'lockedApps': lockedPackages});
  }

  Future<void> _activateLock(int minutes) async {
    final targetTime = DateTime.now().add(Duration(minutes: minutes));
    setState(() => lockEndTime = targetTime);

    await _firestore
        .collection('users')
        .doc(widget.studentId)
        .update({'lockEndTime': Timestamp.fromDate(targetTime)});
  }

  Future<void> _terminateLock() async {
    setState(() => lockEndTime = null);
    await _firestore
        .collection('users')
        .doc(widget.studentId)
        .update({'lockEndTime': null});
  }

  void _showDurationPicker() {
    if (lockedPackages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Select apps to lock first!")));
      return;
    }
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Container(
          height: 350,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 20),
              Text("Select Lock Duration", style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
              Expanded(
                child: CupertinoTheme(
                  data: CupertinoThemeData(brightness: isDark ? Brightness.dark : Brightness.light),
                  child: CupertinoTimerPicker(
                    mode: CupertinoTimerPickerMode.hm,
                    initialTimerDuration: Duration(minutes: _selectedDuration),
                    onTimerDurationChanged: (val) => _selectedDuration = val.inMinutes,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: SizedBox(
                   width: double.infinity,
                   height: 56,
                   child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _activateLock(_selectedDuration == 0 ? 60 : _selectedDuration);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orangeAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text("Apply Lock", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                   ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }



  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLockActive = lockEndTime != null && DateTime.now().isBefore(lockEndTime!);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text("Lock ${widget.studentName}'s Apps", style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 18, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: isDark ? Colors.white : Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark 
                ? [const Color(0xFF2B1200), const Color(0xFF0B0E17)] // Dark Orange/Black for Parent
                : [const Color(0xFFFFF7ED), const Color(0xFFE2E8F0)],
          ),
        ),
        child: SafeArea(
          child: Column(
             children: [
                if (isLockActive)
                   Container(
                     margin: const EdgeInsets.all(20),
                     padding: const EdgeInsets.all(16),
                     decoration: BoxDecoration(
                       color: Colors.redAccent.withValues(alpha: 0.1),
                       borderRadius: BorderRadius.circular(16),
                       border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                     ),
                     child: Row(
                       mainAxisAlignment: MainAxisAlignment.center,
                       children: [
                         const Icon(Icons.lock_clock, color: Colors.redAccent),
                         const SizedBox(width: 12),
                         Text(
                           "Locks Active until ${_formatTime(lockEndTime!)}",
                           style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                         ),
                       ],
                     ),
                   ),

                Expanded(
                  child: loading 
                     ? const Center(child: CircularProgressIndicator(color: Colors.orangeAccent))
                     : GridView.builder(
                        padding: const EdgeInsets.all(20),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          childAspectRatio: 0.8,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemCount: installedApps.length,
                        itemBuilder: (context, index) {
                          final app = installedApps[index];
                          final pkg = app['packageName'];
                          final name = app['appName'];
                          final isSelected = lockedPackages.contains(pkg);
                          
                          return GestureDetector(
                            onTap: () => _toggleLock(pkg, !isSelected),
                            child: Container(
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.orangeAccent.withValues(alpha: 0.2)
                                    : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white70),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? Colors.orangeAccent
                                      : Colors.transparent,
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
                                      color: Colors.black.withValues(alpha: 0.3),
                                    ),
                                    child: AppIconWidget(
                                      packageName: app['packageName'],
                                      appName: app['appName'],
                                      iconBytes: app['decodedIcon'],
                                      size: 40,
                                    ),
                                  ),
                                  
                                  Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Text(
                                      name,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: isDark ? Colors.white : Colors.black87,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  
                                  if (isSelected)
                                    const Icon(Icons.check_circle, color: Colors.orangeAccent, size: 12),
                                ],
                              ),
                            ),
                          );
                        },
                     ),
                ),
             ],
          ),
        ),
      ),
      floatingActionButton: isLockActive
          ? FloatingActionButton.extended(
              backgroundColor: Colors.redAccent,
              icon: const Icon(Icons.stop_circle_outlined, color: Colors.white),
              label: const Text("STOP LOCK", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              onPressed: _terminateLock,
            )
          : FloatingActionButton.extended(
              backgroundColor: Colors.orangeAccent,
              icon: const Icon(Icons.timer, color: Colors.white),
              label: const Text("Set Timer", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              onPressed: _showDurationPicker,
            ),
    );
  }

  String _formatTime(DateTime time) {
    return "${time.hour.toString().padLeft(2,'0')}:${time.minute.toString().padLeft(2,'0')}";
  }
}
