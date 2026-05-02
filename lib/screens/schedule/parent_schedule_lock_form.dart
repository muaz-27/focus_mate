import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:focus_mate/core/schedule_service.dart';
import 'package:focus_mate/theme/app_colors.dart';
import 'package:focus_mate/theme/app_theme.dart';
import '../../core/widgets/app_icon_widget.dart';

class ParentScheduleLockForm extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String parentId;
  final AppSchedule? existingSchedule;

  const ParentScheduleLockForm({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.parentId,
    this.existingSchedule,
  });

  @override
  State<ParentScheduleLockForm> createState() => _ParentScheduleLockFormState();
}

class _ParentScheduleLockFormState extends State<ParentScheduleLockForm> {
  final ScheduleService _scheduleService = ScheduleService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final _nameController = TextEditingController();
  List<int> _selectedDays = [];
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 17, minute: 0);

  List<Map<String, dynamic>> _installedApps = [];
  List<String> _selectedApps = [];
  bool _loadingApps = true;

  @override
  void initState() {
    super.initState();
    if (widget.existingSchedule != null) {
      _nameController.text = widget.existingSchedule!.name;
      _selectedDays = List.from(widget.existingSchedule!.days);
      _startTime = widget.existingSchedule!.startTime;
      _endTime = widget.existingSchedule!.endTime;
      _selectedApps = List.from(widget.existingSchedule!.lockedApps);
    }
    _loadApps();
  }

  Future<void> _loadApps() async {
    try {
      final appsCollection = _firestore
          .collection('users')
          .doc(widget.studentId)
          .collection('data_v2');
      final shardsSnapshot = await appsCollection.get();
      List<Map<String, dynamic>> allApps = [];

      if (shardsSnapshot.docs.isNotEmpty) {
        for (var doc in shardsSnapshot.docs) {
          if (doc.data().containsKey('installedApps')) {
            final shardApps = List<Map<String, dynamic>>.from(
              doc.data()['installedApps'],
            );
            allApps.addAll(shardApps);
          }
        }
      } else {
        // Fallback Check 'data/installed_apps'
        final legacyDoc = await _firestore
            .collection('users')
            .doc(widget.studentId)
            .collection('data')
            .doc('installed_apps')
            .get();

        if (legacyDoc.exists && legacyDoc.data() != null) {
          final data = legacyDoc.data() as Map<String, dynamic>;
          if (data.containsKey('installedApps')) {
            allApps = List<Map<String, dynamic>>.from(data['installedApps']);
          }
        } else {
          // Fallback to user doc
          final userDoc = await _firestore
              .collection('users')
              .doc(widget.studentId)
              .get();
          if (userDoc.exists && userDoc.data()!.containsKey('installedApps')) {
            allApps = List<Map<String, dynamic>>.from(
              userDoc.data()!['installedApps'],
            );
          }
        }
      }

      allApps.sort(
        (a, b) => (a['appName'] as String).toLowerCase().compareTo(
          (b['appName'] as String).toLowerCase(),
        ),
      );

      final iconCollection = _firestore
          .collection('users')
          .doc(widget.studentId)
          .collection('app_icons');
      final iconsSnapshot = await iconCollection.get();
      Map<String, String> iconMap = {};
      for (var doc in iconsSnapshot.docs) {
        if (doc.data().containsKey('icon')) {
          iconMap[doc.id] = doc.data()['icon'];
        }
      }

      if (mounted) {
        setState(() {
          _installedApps = allApps
              .where((app) => app['packageName'] != 'com.example.focus_mate')
              .map((app) {
                final newApp = Map<String, dynamic>.from(app);
                final pkg = newApp['packageName'];
                final iconBase64 = iconMap[pkg] ?? newApp['iconBytes'];
                if (iconBase64 != null && iconBase64 is String) {
                  try {
                    newApp['decodedIcon'] = base64Decode(iconBase64);
                  } catch (e) {}
                }
                return newApp;
              })
              .toList();
          _loadingApps = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingApps = false);
    }
  }

  void _saveSchedule() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Name cannot be empty")));
      return;
    }
    if (_selectedDays.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Select at least one day")));
      return;
    }
    if (_selectedApps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Select at least one app to block")),
      );
      return;
    }

    final schedule = AppSchedule(
      id: widget.existingSchedule?.id ?? '',
      type: widget.existingSchedule?.type ?? 'companion',
      name: _nameController.text.trim(),
      days: _selectedDays,
      startTime: _startTime,
      endTime: _endTime,
      lockedApps: _selectedApps,
      status: widget.existingSchedule?.status ?? 'active',
      exemptions: widget.existingSchedule?.exemptions ?? [],
      companionId: widget.existingSchedule?.companionId ?? widget.parentId,
    );

    await _scheduleService.saveSchedule(widget.studentId, schedule);

    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          widget.existingSchedule != null ? "Edit Schedule" : "New Schedule",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          Container(
            height: double.infinity,
            width: double.infinity,
            decoration: AppTheme.screenBackground(
              context,
              AppColors.roleGradients['parent']!,
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _nameController,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    decoration: InputDecoration(
                      labelText: "Schedule Name (e.g., School Time)",
                      labelStyle: TextStyle(
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                      filled: true,
                      fillColor: isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  Text(
                    "Select Days",
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: List.generate(7, (index) {
                      final dayNum = index + 1;
                      final isSelected = _selectedDays.contains(dayNum);
                      const dayLabels = [
                        'Mon',
                        'Tue',
                        'Wed',
                        'Thu',
                        'Fri',
                        'Sat',
                        'Sun',
                      ];

                      return FilterChip(
                        label: Text(dayLabels[index]),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            selected
                                ? _selectedDays.add(dayNum)
                                : _selectedDays.remove(dayNum);
                          });
                        },
                        selectedColor: Colors.orangeAccent.withValues(
                          alpha: 0.3,
                        ),
                        checkmarkColor: Colors.orangeAccent,
                        backgroundColor: isDark
                            ? Colors.white10
                            : Colors.black12,
                      );
                    }),
                  ),
                  const SizedBox(height: 24),

                  Row(
                    children: [
                      Expanded(
                        child: _TimePickerCard(
                          title: "Start Time",
                          time: _startTime,
                          isDark: isDark,
                          onTap: () async {
                            final time = await showTimePicker(
                              context: context,
                              initialTime: _startTime,
                            );
                            if (time != null) setState(() => _startTime = time);
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _TimePickerCard(
                          title: "End Time",
                          time: _endTime,
                          isDark: isDark,
                          onTap: () async {
                            final time = await showTimePicker(
                              context: context,
                              initialTime: _endTime,
                            );
                            if (time != null) setState(() => _endTime = time);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  Text(
                    "Select Apps to Block",
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_loadingApps)
                    const Center(
                      child: CircularProgressIndicator(
                        color: Colors.orangeAccent,
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _installedApps.length,
                      itemBuilder: (context, index) {
                        final app = _installedApps[index];
                        final isSelected = _selectedApps.contains(
                          app['packageName'],
                        );
                        return CheckboxListTile(
                          title: Row(
                            children: [
                              AppIconWidget(
                                packageName: app['packageName'],
                                appName: app['appName'],
                                iconBytes: app['decodedIcon'],
                                size: 32,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  app['appName'],
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            app['packageName'],
                            style: TextStyle(
                              fontSize: 10,
                              color: isDark ? Colors.grey[400] : Colors.grey.shade600,
                            ),
                          ),
                          value: isSelected,
                          onChanged: (val) {
                            setState(() {
                              if (val == true)
                                _selectedApps.add(app['packageName']);
                              else
                                _selectedApps.remove(app['packageName']);
                            });
                          },
                          activeColor: Colors.orangeAccent,
                          checkColor: Colors.white,
                        );
                      },
                    ),

                  const SizedBox(height: 50),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _saveSchedule,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orangeAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        widget.existingSchedule != null
                            ? "Update Schedule"
                            : "Save Schedule",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimePickerCard extends StatelessWidget {
  final String title;
  final TimeOfDay time;
  final bool isDark;
  final VoidCallback onTap;

  const _TimePickerCard({
    required this.title,
    required this.time,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
        ),
        child: Column(
          children: [
            Text(
              title,
              style: TextStyle(
                color: isDark ? Colors.white54 : Colors.black54,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              time.format(context),
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
