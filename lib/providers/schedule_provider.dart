import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focus_mate/core/schedule_service.dart';

/// Streams all schedules for a given user.
///
/// Usage: `ref.watch(schedulesProvider(userId))`
/// Returns a reactive list of [AppSchedule] objects.
final schedulesProvider = StreamProvider.family<List<AppSchedule>, String>((ref, userId) {
  return ScheduleService().getSchedulesStream(userId);
});

/// Singleton instance of [ScheduleService] for imperative actions
/// (create, delete, sync to native).
final scheduleServiceProvider = Provider<ScheduleService>((ref) {
  return ScheduleService();
});
