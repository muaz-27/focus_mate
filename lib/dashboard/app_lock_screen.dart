import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:installed_apps/app_info.dart';
import 'package:android_intent_plus/android_intent.dart';
import '../core/usage_service.dart';
import 'dart:typed_data';


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
    final apps = await _usageService.getInstalledAppsList(); // already fetches icons
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
    await FirebaseFirestore.instance.collection('users').doc(widget.userId).update({
      'lockEndTime': null,
    });
  }

  Future<void> _toggleLock(String packageName, bool isLocked) async {
    setState(() {
      isLocked ? lockedPackages.add(packageName) : lockedPackages.remove(packageName);
    });

    await FirebaseFirestore.instance.collection('users').doc(widget.userId).update({
      'lockedApps': lockedPackages,
    });
  }

  void _openAccessibilitySettings() {
    const AndroidIntent intent = AndroidIntent(action: 'android.settings.ACCESSIBILITY_SETTINGS');
    intent.launch();
  }

  void _showDurationPicker() {
    if (lockedPackages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Select apps to lock first!"),
      ));
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
              const Text("Select Lock Duration",
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _timeOption(15, "15m"),
                  _timeOption(30, "30m"),
                  _timeOption(60, "1h"),
                ],
              ),

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: _timeOption(120, "2 Hours (Deep Work)"),
              )
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
          // ============== ACCESSIBILITY REMINDER ==============
          Container(
            width: double.infinity,
            color: Colors.blueAccent.withOpacity(0.2),
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.blueAccent),
                const SizedBox(width: 10),
                const Expanded(
                    child: Text("Enable Accessibility for instant blocking.",
                        style: TextStyle(color: Colors.white70, fontSize: 12))),
                TextButton(onPressed: _openAccessibilitySettings, child: const Text("OPEN"))
              ],
            ),
          ),

          // ============== LOCK TIMER DISPLAY ==============
          if (isLockActive)
            Container(
              width: double.infinity,
              color: Colors.green.withOpacity(0.2),
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  const Text("🔒 LOCK ACTIVE UNTIL:",
                      style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                  Text(_getRemainingTime(),
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                ],
              ),
            ),

          // ============== APPS LIST ==============
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: installedApps.length,
                    itemBuilder: (context, index) {
                      final app = installedApps[index];
                      final isSelected = lockedPackages.contains(app.packageName);

                      // App icon extraction
                      Uint8List? iconData = app.icon != null ? Uint8List.fromList(app.icon!) : null;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: isSelected ? Border.all(color: Colors.redAccent.withOpacity(0.6), width: 1.4) : null,
                        ),

                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.black45,
                            radius: 22,
                            child: iconData != null
                                ? ClipOval(
                                    child: Image.memory(iconData, width: 40, height: 40, fit: BoxFit.cover),
                                  )
                                : const Icon(Icons.apps, color: Colors.white70),
                          ),

                          title: Text(
                            app.name ?? "Unknown",
                            style: TextStyle(
                                color: isSelected ? Colors.redAccent : Colors.white,
                                fontWeight: FontWeight.w500,
                                fontSize: 15),
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
              backgroundColor: Colors.red,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text("STOP LOCK"),
              onPressed: _terminateLock,
            )
          : FloatingActionButton.extended(
              backgroundColor: Colors.blueAccent,
              icon: const Icon(Icons.timer),
              label: const Text("Set Lock Timer"),
              onPressed: _showDurationPicker,
            ),
    );
  }
}
