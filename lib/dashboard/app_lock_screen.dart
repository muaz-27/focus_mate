import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:installed_apps/app_info.dart';
import 'package:android_intent_plus/android_intent.dart'; // NEW: For Settings Intent
import '../core/usage_service.dart';

class AppLockScreen extends StatefulWidget {
  final String userId;

  const AppLockScreen({super.key, required this.userId});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  final UsageService _usageService = UsageService();
  
  List<AppInfo> installedApps = [];
  List<String> lockedPackages = [];
  DateTime? lockEndTime;
  Timer? _uiTimer; 
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    final apps = await _usageService.getInstalledAppsList();
    final doc = await FirebaseFirestore.instance.collection('users').doc(widget.userId).get();

    if (mounted) {
      setState(() {
        installedApps = apps;
        installedApps.sort((a, b) => (a.name ?? "").compareTo(b.name ?? ""));
        
        if (doc.exists) {
          final data = doc.data()!;
          lockedPackages = List<String>.from(data['lockedApps'] ?? []);
          if (data['lockEndTime'] != null) {
            lockEndTime = (data['lockEndTime'] as Timestamp).toDate();
            _startUiCountdown(); 
          }
        }
        loading = false;
      });
    }
  }

  void _startUiCountdown() {
    _uiTimer?.cancel();
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (lockEndTime != null && DateTime.now().isAfter(lockEndTime!)) {
            _terminateLock(); 
          }
        });
      }
    });
  }

  Future<void> _terminateLock() async {
    _uiTimer?.cancel();
    setState(() => lockEndTime = null);
    await FirebaseFirestore.instance.collection('users').doc(widget.userId).update({'lockEndTime': null});
  }

  Future<void> _toggleLock(String packageName, bool isLocked) async {
    setState(() {
      isLocked ? lockedPackages.add(packageName) : lockedPackages.remove(packageName);
    });
    await FirebaseFirestore.instance.collection('users').doc(widget.userId).update({'lockedApps': lockedPackages});
  }

  void _openAccessibilitySettings() {
    const AndroidIntent intent = AndroidIntent(action: 'android.settings.ACCESSIBILITY_SETTINGS');
    intent.launch();
  }

  // 🔹 NEW: TIMER SELECTION SHEET
  void _showDurationPicker() {
    if (lockedPackages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Select apps to lock first!")));
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          height: 280,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Select Lock Duration", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              
              // Quick Options
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _timeOption(15, "15m"),
                  _timeOption(30, "30m"),
                  _timeOption(60, "1h"),
                ],
              ),
              const SizedBox(height: 20),
              
              // Full width option
              SizedBox(
                width: double.infinity,
                child: _timeOption(120, "2 Hours (Deep Work)"),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _timeOption(int minutes, String label) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blueAccent.withOpacity(0.2),
        foregroundColor: Colors.blueAccent,
        side: const BorderSide(color: Colors.blueAccent),
      ),
      onPressed: () {
        Navigator.pop(context);
        _activateLock(minutes);
      },
      child: Text(label),
    );
  }

  Future<void> _activateLock(int minutes) async {
    DateTime targetTime = DateTime.now().add(Duration(minutes: minutes));
    setState(() => lockEndTime = targetTime);
    _startUiCountdown();
    await FirebaseFirestore.instance.collection('users').doc(widget.userId).update({
      'lockEndTime': Timestamp.fromDate(targetTime),
    });
  }
  
  String _getRemainingTime() {
    if (lockEndTime == null) return "";
    Duration diff = lockEndTime!.difference(DateTime.now());
    return "${diff.inHours.toString().padLeft(2, '0')}:${(diff.inMinutes % 60).toString().padLeft(2, '0')}:${(diff.inSeconds % 60).toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    bool isLockActive = lockEndTime != null && DateTime.now().isBefore(lockEndTime!);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text("Block Distractions"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
      ),
      body: Column(
        children: [
          
          Container(
            width: double.infinity,
            color: Colors.blueAccent.withOpacity(0.2),
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.blueAccent),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    "Enable Accessibility for instant blocking.",
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: _openAccessibilitySettings,
                  child: const Text("OPEN"),
                )
              ],
            ),
          ),

          if (isLockActive)
            Container(
              width: double.infinity,
              color: Colors.green.withOpacity(0.2),
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  const Text("🔒 LOCK ACTIVE UNTIL:", style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                  Text(_getRemainingTime(), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                ],
              ),
            ),

          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: installedApps.length,
                    itemBuilder: (context, index) {
                      final app = installedApps[index];
                      final isSelected = lockedPackages.contains(app.packageName);
                      final firstLetter = (app.name != null && app.name!.isNotEmpty) ? app.name![0].toUpperCase() : "?";

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: isSelected ? Border.all(color: Colors.redAccent.withOpacity(0.5)) : null,
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.white10,
                            child: Text(firstLetter, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                          title: Text(
                            app.name ?? "Unknown",
                            style: TextStyle(color: isSelected ? Colors.redAccent : Colors.white, fontWeight: FontWeight.w500),
                          ),
                          trailing: Switch(
                            value: isSelected,
                            activeColor: Colors.redAccent,
                            inactiveThumbColor: Colors.grey,
                            onChanged: (val) => _toggleLock(app.packageName!, val),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: isLockActive
          ? FloatingActionButton.extended(
              onPressed: _terminateLock,
              backgroundColor: Colors.red,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text("STOP LOCK"),
            )
          : FloatingActionButton.extended(
              onPressed: _showDurationPicker, // 🔹 OPENS BOTTOM SHEET
              backgroundColor: Colors.blueAccent,
              icon: const Icon(Icons.timer),
              label: const Text("Set Lock Timer"),
            ),
    );
  }
}