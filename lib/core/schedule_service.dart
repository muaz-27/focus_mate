import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'native_blocker.dart';

class AppSchedule {
  final String id;
  final String type; // 'self' or 'companion'
  final String name;
  final List<int> days; // 1 = Monday, 7 = Sunday
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final List<String> lockedApps;
  final String status; // 'active', 'requested', 'inactive'
  final List<String> exemptions;
  final String? companionId;

  AppSchedule({
    required this.id,
    required this.type,
    required this.name,
    required this.days,
    required this.startTime,
    required this.endTime,
    required this.lockedApps,
    required this.status,
    required this.exemptions,
    this.companionId,
  });

  factory AppSchedule.fromMap(Map<String, dynamic> map, String id) {
    return AppSchedule(
      id: id,
      type: map['type'] ?? 'self',
      name: map['name'] ?? 'Untitled Schedule',
      days: List<int>.from(map['days'] ?? []),
      startTime: TimeOfDay(
        hour: map['startTime']?['hour'] ?? 0,
        minute: map['startTime']?['minute'] ?? 0,
      ),
      endTime: TimeOfDay(
        hour: map['endTime']?['hour'] ?? 0,
        minute: map['endTime']?['minute'] ?? 0,
      ),
      lockedApps: List<String>.from(map['lockedApps'] ?? []),
      status: map['status'] ?? 'inactive',
      exemptions: List<String>.from(map['exemptions'] ?? []),
      companionId: map['companionId'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'name': name,
      'days': days,
      'startTime': {'hour': startTime.hour, 'minute': startTime.minute},
      'endTime': {'hour': endTime.hour, 'minute': endTime.minute},
      'lockedApps': lockedApps,
      'status': status,
      'exemptions': exemptions,
      'companionId': companionId,
    };
  }

  Map<String, dynamic> toJson() {
    return toMap()..addAll({'id': id});
  }
}

class ScheduleService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Stream of user schedules
  Stream<List<AppSchedule>> getSchedulesStream(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('schedules')
        .snapshots()
        .map((snapshot) {
      final List<AppSchedule> schedules = snapshot.docs
          .map((doc) => AppSchedule.fromMap(doc.data(), doc.id))
          .toList();
      return schedules;
    });
  }

  /// Syncs an individual user's active schedules directly to native background service.
  /// Call this whenever schedules are added/edited, or on app startup.
  Future<void> syncSchedulesToNative(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('schedules')
          .where('status', isEqualTo: 'active')
          .get();

      final schedules = snapshot.docs
          .map((doc) => AppSchedule.fromMap(doc.data(), doc.id))
          .toList();
          
      final String jsonString = jsonEncode(schedules.map((s) => s.toJson()).toList());
      await NativeBlocker.setSchedules(jsonString);
    } catch (e) {
      print("Error syncing schedules to native: \$e");
    }
  }

  /// Creates or updates a schedule
  Future<void> saveSchedule(String userId, AppSchedule schedule) async {
    final docRef = schedule.id.isEmpty
        ? _firestore.collection('users').doc(userId).collection('schedules').doc()
        : _firestore.collection('users').doc(userId).collection('schedules').doc(schedule.id);

    await docRef.set(schedule.toMap());
  }

  /// Deletes a schedule
  Future<void> deleteSchedule(String userId, String scheduleId) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('schedules')
        .doc(scheduleId)
        .delete();
  }

  /// Temporarily unblocks an app for a given schedule
  Future<void> addExemption(String userId, String scheduleId, String packageName) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('schedules')
        .doc(scheduleId)
        .update({
      'exemptions': FieldValue.arrayUnion([packageName])
    });
  }

  /// Removes a temporary unblock
  Future<void> removeExemption(String userId, String scheduleId, String packageName) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('schedules')
        .doc(scheduleId)
        .update({
      'exemptions': FieldValue.arrayRemove([packageName])
    });
  }

  /// Checks if a schedule is currently enforcing locks based on the current time and day.
  bool isCurrentlyActive(AppSchedule schedule) {
    if (schedule.status != 'active') return false;
    
    final now = DateTime.now();
    final currentDay = now.weekday; // 1 = Monday, 7 = Sunday
    
    if (!schedule.days.contains(currentDay)) return false;
    
    final start = schedule.startTime.hour * 60 + schedule.startTime.minute;
    final end = schedule.endTime.hour * 60 + schedule.endTime.minute;
    final currentTime = now.hour * 60 + now.minute;
    
    if (end < start) {
      // Crosses midnight
      return currentTime >= start || currentTime < end;
    } else {
      return currentTime >= start && currentTime < end;
    }
  }
}
