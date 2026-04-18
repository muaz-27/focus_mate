import 'package:flutter/material.dart';
import 'package:device_apps/device_apps.dart';
import 'package:focus_mate/core/schedule_service.dart';
import 'package:focus_mate/core/usage_service.dart';

class ScheduleLockForm extends StatefulWidget {
  final String userId;
  final bool companionActive;
  final String? companionId;
  final String? companionName;

  const ScheduleLockForm({
    super.key,
    required this.userId,
    required this.companionActive,
    this.companionId,
    this.companionName,
  });

  @override
  State<ScheduleLockForm> createState() => _ScheduleLockFormState();
}

class _ScheduleLockFormState extends State<ScheduleLockForm> {
  final ScheduleService _scheduleService = ScheduleService();
  final UsageService _usageService = UsageService();

  final _nameController = TextEditingController();
  List<int> _selectedDays = [];
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 17, minute: 0);
  
  List<Application> _installedApps = [];
  List<String> _selectedApps = [];
  bool _loadingApps = true;

  @override
  void initState() {
    super.initState();
    if (!widget.companionActive) {
      _loadApps();
    } else {
      _loadingApps = false;
    }
  }

  Future<void> _loadApps() async {
    final apps = await _usageService.getInstalledAppsList();
    if (mounted) {
      setState(() {
        _installedApps = apps.where((app) => app.packageName != 'com.example.focus_mate').toList();
        _installedApps.sort((a, b) => a.appName.toLowerCase().compareTo(b.appName.toLowerCase()));
        _loadingApps = false;
      });
    }
  }

  void _saveSchedule() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Name cannot be empty")));
      return;
    }
    if (_selectedDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Select at least one day")));
      return;
    }
    if (!widget.companionActive && _selectedApps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Select at least one app to block")));
      return;
    }

    final schedule = AppSchedule(
      id: '',
      type: widget.companionActive ? 'companion' : 'self',
      name: _nameController.text.trim(),
      days: _selectedDays,
      startTime: _startTime,
      endTime: _endTime,
      lockedApps: _selectedApps,
      status: widget.companionActive ? 'requested' : 'active',
      exemptions: [],
      companionId: widget.companionActive ? widget.companionId : null,
    );

    await _scheduleService.saveSchedule(widget.userId, schedule);
    
    if (!widget.companionActive) {
      await _scheduleService.syncSchedulesToNative(widget.userId);
    }

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
        title: const Text("New Schedule", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
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
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _nameController,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                    decoration: InputDecoration(
                      labelText: "Schedule Name (e.g., School Time)",
                      labelStyle: TextStyle(color: isDark ? Colors.white54 : Colors.black54),
                      filled: true,
                      fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  Text("Select Days", style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: List.generate(7, (index) {
                      final dayNum = index + 1;
                      final isSelected = _selectedDays.contains(dayNum);
                      const dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                      
                      return FilterChip(
                        label: Text(dayLabels[index]),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            selected ? _selectedDays.add(dayNum) : _selectedDays.remove(dayNum);
                          });
                        },
                        selectedColor: Colors.amberAccent.withValues(alpha: 0.3),
                        checkmarkColor: Colors.amberAccent,
                        backgroundColor: isDark ? Colors.white10 : Colors.black12,
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
                            final time = await showTimePicker(context: context, initialTime: _startTime);
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
                            final time = await showTimePicker(context: context, initialTime: _endTime);
                            if (time != null) setState(() => _endTime = time);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  if (widget.companionActive) ...[
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(color: Colors.amberAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
                      child: Column(
                        children: [
                          const Icon(Icons.people_alt, color: Colors.amberAccent, size: 40),
                          const SizedBox(height: 12),
                          Text("Schedule Request", style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 18)),
                          const SizedBox(height: 8),
                          Text("Your companion '\${widget.companionName}' will choose which apps are blocked during this time.",
                              textAlign: TextAlign.center, style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
                        ],
                      ),
                    )
                  ] else ...[
                     Text("Select Apps to Block", style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
                     const SizedBox(height: 12),
                     if (_loadingApps) 
                       const Center(child: CircularProgressIndicator())
                     else
                       ListView.builder(
                         shrinkWrap: true,
                         physics: const NeverScrollableScrollPhysics(),
                         itemCount: _installedApps.length,
                         itemBuilder: (context, index) {
                           final app = _installedApps[index];
                           final isSelected = _selectedApps.contains(app.packageName);
                           return CheckboxListTile(
                             title: Text(app.appName, style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                             subtitle: Text(app.packageName, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                             value: isSelected,
                             onChanged: (val) {
                               setState(() {
                                 if (val == true) _selectedApps.add(app.packageName);
                                 else _selectedApps.remove(app.packageName);
                               });
                             },
                             activeColor: Colors.amberAccent,
                             checkColor: Colors.black,
                           );
                         },
                       ),
                  ],

                  const SizedBox(height: 50),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _saveSchedule,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amberAccent,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text(widget.companionActive ? "Request Schedule" : "Save Schedule", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
            Text(title, style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 12)),
            const SizedBox(height: 8),
            Text(time.format(context), style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 24, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}