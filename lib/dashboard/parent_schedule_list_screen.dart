import 'package:flutter/material.dart';

import '../core/schedule_service.dart';
import 'parent_schedule_lock_form.dart';

class ParentScheduleListScreen extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String parentId;

  const ParentScheduleListScreen({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.parentId,
  });

  @override
  State<ParentScheduleListScreen> createState() => _ParentScheduleListScreenState();
}

class _ParentScheduleListScreenState extends State<ParentScheduleListScreen> {
  final ScheduleService _scheduleService = ScheduleService();

  String _formatTime(TimeOfDay time) {
    final hc = time.hour > 12 ? time.hour - 12 : (time.hour == 0 ? 12 : time.hour);
    final period = time.hour >= 12 ? "PM" : "AM";
    return "$hc:${time.minute.toString().padLeft(2, '0')} $period";
  }

  String _formatDays(List<int> days) {
    if (days.length == 7) return "Everyday";
    if (days.length == 5 && !days.contains(6) && !days.contains(7)) {
      return "Weekdays";
    }
    if (days.length == 2 && days.contains(6) && days.contains(7)) {
      return "Weekends";
    }
    const dayNames = {1: 'M', 2: 'T', 3: 'W', 4: 'T', 5: 'F', 6: 'S', 7: 'S'};
    return days.map((d) => dayNames[d]).join(', ');
  }



  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text('${widget.studentName}\'s Schedules', style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
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
                  ? [const Color(0xFF3D1E00), const Color(0xFF0B0E17)] 
                  : [const Color(0xFFFFF7ED), const Color(0xFFE2E8F0)],
              ),
            ),
          ),
          SafeArea(
            child: StreamBuilder<List<AppSchedule>>(
              stream: _scheduleService.getSchedulesStream(widget.studentId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.orangeAccent));
                }
                if (snapshot.hasError) {
                  return const Center(child: Text("Error loading schedules"));
                }
                
                // Filter schedules to only show those created by this companion
                final schedules = (snapshot.data ?? []).where((s) => s.companionId == widget.parentId).toList();

                if (schedules.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.schedule, size: 60, color: Colors.grey.withOpacity(0.5)),
                        const SizedBox(height: 16),
                        const Text("No active schedules", style: TextStyle(fontSize: 16, color: Colors.grey)),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: schedules.length,
                  itemBuilder: (context, index) {
                    final schedule = schedules[index];
                    
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withOpacity(0.05) : Colors.white70,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.orangeAccent.withOpacity(0.3),
                        ),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ParentScheduleLockForm(
                                studentId: widget.studentId,
                                studentName: widget.studentName,
                                parentId: widget.parentId,
                                existingSchedule: schedule,
                              ),
                            ),
                          );
                        },
                        title: Text(schedule.name, style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text("${_formatTime(schedule.startTime)} - ${_formatTime(schedule.endTime)}", 
                              style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
                            Text(_formatDays(schedule.days), 
                              style: const TextStyle(color: Colors.orangeAccent, fontSize: 12)),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                          onPressed: () {
                             _scheduleService.deleteSchedule(widget.studentId, schedule.id);
                          },
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ParentScheduleLockForm(
                studentId: widget.studentId,
                studentName: widget.studentName,
                parentId: widget.parentId,
              ),
            ),
          );
        },
        backgroundColor: Colors.orangeAccent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text("New Schedule", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}
