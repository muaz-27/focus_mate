import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focus_mate/providers/schedule_provider.dart';
import 'package:focus_mate/screens/schedule/parent_schedule_lock_form.dart';
import 'package:focus_mate/theme/app_colors.dart';
import 'package:focus_mate/theme/app_theme.dart';

class ParentScheduleListScreen extends ConsumerWidget {
  final String studentId;
  final String studentName;
  final String parentId;

  const ParentScheduleListScreen({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.parentId,
  });

  String _formatTime(TimeOfDay time) {
    final hc = time.hour > 12
        ? time.hour - 12
        : (time.hour == 0 ? 12 : time.hour);
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
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final schedulesAsync = ref.watch(schedulesProvider(studentId));
    final scheduleService = ref.read(scheduleServiceProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          '$studentName\'s Schedules',
          style: const TextStyle(fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
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
            decoration: AppTheme.screenBackground(
              context,
              AppColors.roleGradients['parent']!,
            ),
          ),
          SafeArea(
            child: schedulesAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: Colors.orangeAccent),
              ),
              error: (_, __) =>
                  const Center(child: Text("Error loading schedules")),
              data: (allSchedules) {
                // Filter schedules to only show those created by this companion
                final schedules = allSchedules
                    .where((s) => s.companionId == parentId)
                    .toList();

                if (schedules.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.schedule,
                          size: 60,
                          color: Colors.grey.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "No active schedules",
                          style: TextStyle(fontSize: 16, color: isDark ? Colors.white70 : Colors.grey.shade700),
                        ),
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
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.white70,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.orangeAccent.withValues(alpha: 0.3),
                        ),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ParentScheduleLockForm(
                                studentId: studentId,
                                studentName: studentName,
                                parentId: parentId,
                                existingSchedule: schedule,
                              ),
                            ),
                          );
                        },
                        title: Text(
                          schedule.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(
                              "${_formatTime(schedule.startTime)} - ${_formatTime(schedule.endTime)}",
                              style: TextStyle(
                                color: isDark ? Colors.white70 : Colors.black54,
                              ),
                            ),
                            Text(
                              _formatDays(schedule.days),
                              style: const TextStyle(
                                color: Colors.orangeAccent,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.redAccent,
                          ),
                          onPressed: () {
                            scheduleService.deleteSchedule(
                              studentId,
                              schedule.id,
                            );
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
                studentId: studentId,
                studentName: studentName,
                parentId: parentId,
              ),
            ),
          );
        },
        backgroundColor: Colors.orangeAccent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text(
          "New Schedule",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
