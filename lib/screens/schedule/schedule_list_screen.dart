import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focus_mate/core/schedule_service.dart';
import 'package:focus_mate/providers/schedule_provider.dart';
import 'package:focus_mate/screens/schedule/schedule_lock_form.dart';
import 'package:focus_mate/screens/locks/unlock_request_screen.dart';

class ScheduleListScreen extends ConsumerWidget {
  final String userId;
  final bool companionActive;
  final String? companionId;
  final String? companionName;

  const ScheduleListScreen({
    super.key,
    required this.userId,
    required this.companionActive,
    this.companionId,
    this.companionName,
  });

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

  void _showScheduleDetails(BuildContext context, AppSchedule schedule, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(schedule.name, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
              const SizedBox(height: 8),
              Text("${_formatTime(schedule.startTime)} - ${_formatTime(schedule.endTime)}", style: const TextStyle(fontSize: 16, color: Colors.amberAccent)),
              const SizedBox(height: 4),
              Text(_formatDays(schedule.days), style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
              const SizedBox(height: 16),
              Text("Locked Apps: ${schedule.lockedApps.length}", style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final schedulesAsync = ref.watch(schedulesProvider(userId));
    final scheduleService = ref.read(scheduleServiceProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text("App Lock Schedules", style: TextStyle(fontWeight: FontWeight.bold)),
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
                  ? [const Color(0xFF1A1F35), const Color(0xFF0B0E17)] 
                  : [const Color(0xFFF8FAFC), const Color(0xFFE2E8F0)],
              ),
            ),
          ),
          SafeArea(
            child: schedulesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator(color: Colors.amberAccent)),
              error: (_, __) => const Center(child: Text("Error loading schedules")),
              data: (schedules) {
                if (schedules.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.schedule, size: 60, color: Colors.grey.withValues(alpha: 0.5)),
                        const SizedBox(height: 16),
                        const Text("No schedules set", style: TextStyle(fontSize: 16, color: Colors.grey)),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: schedules.length,
                  itemBuilder: (context, index) {
                    final schedule = schedules[index];
                    final isRequested = schedule.status == 'requested';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white70,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isRequested ? Colors.orange.withValues(alpha: 0.5) : Colors.amberAccent.withValues(alpha: 0.3),
                        ),
                      ),
                      child: ListTile(
                        onTap: () {
                          _showScheduleDetails(context, schedule, isDark);
                        },
                        title: Row(
                          children: [
                            Text(schedule.name, style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
                            const SizedBox(width: 8),
                            if (isRequested)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                                child: const Text("Pending", style: TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text("${_formatTime(schedule.startTime)} - ${_formatTime(schedule.endTime)}", 
                              style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
                            Text(_formatDays(schedule.days), 
                              style: const TextStyle(color: Colors.amberAccent, fontSize: 12)),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (companionActive && schedule.status == 'active' && companionId != null)
                              IconButton(
                                icon: const Icon(Icons.lock_open, color: Colors.purpleAccent),
                                tooltip: "Request App Unlock",
                                onPressed: () {
                                  Navigator.push(
                                    context, 
                                    MaterialPageRoute(builder: (_) => UnlockRequestScreen(userId: userId, companionId: companionId!))
                                  );
                                },
                              ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                              onPressed: () {
                                 scheduleService.deleteSchedule(userId, schedule.id);
                                 scheduleService.syncSchedulesToNative(userId);
                              },
                            ),
                          ],
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
              builder: (_) => ScheduleLockForm(
                userId: userId,
                companionActive: companionActive,
                companionId: companionId,
                companionName: companionName,
              ),
            ),
          );
        },
        backgroundColor: Colors.amberAccent,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text("New Schedule", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}
