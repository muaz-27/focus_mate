import 'package:cloud_firestore/cloud_firestore.dart';

enum UserRole {
  user,
  companion,
  parent,
}

class UserModel {
  final String id;
  final String name;
  final String email;
  final UserRole role;
  final DateTime createdAt;
  final List<String>? linkedUsers;
  final String? linkedCompanion;
  final int studyTime;
  final int dailyGoal;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.createdAt,
    this.linkedUsers,
    this.linkedCompanion,
    this.studyTime = 0,
    this.dailyGoal = 120,
  });

  factory UserModel.fromMap(Map<String, dynamic> data, String id) {
    return UserModel(
      id: id,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      role: _parseRole(data['role']),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      linkedUsers: (data['linkedUsers'] as List<dynamic>?)?.map((e) => e.toString()).toList(),
      linkedCompanion: data['linkedCompanion'],
      studyTime: data['studyTime'] ?? 0,
      dailyGoal: data['dailyGoal'] ?? 120,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'role': role.name,
      'createdAt': Timestamp.fromDate(createdAt),
      if (linkedUsers != null) 'linkedUsers': linkedUsers,
      if (linkedCompanion != null) 'linkedCompanion': linkedCompanion,
      'studyTime': studyTime,
      'dailyGoal': dailyGoal,
    };
  }

  static UserRole _parseRole(String? role) {
    switch (role) {
      case 'companion':
        return UserRole.companion;
      case 'parent':
        return UserRole.parent;
      default:
        return UserRole.user;
    }
  }

  UserModel copyWith({
    String? name,
    String? email,
    UserRole? role,
    DateTime? createdAt,
    List<String>? linkedUsers,
    String? linkedCompanion,
    int? studyTime,
    int? dailyGoal,
  }) {
    return UserModel(
      id: this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      createdAt: createdAt ?? this.createdAt,
      linkedUsers: linkedUsers ?? this.linkedUsers,
      linkedCompanion: linkedCompanion ?? this.linkedCompanion,
      studyTime: studyTime ?? this.studyTime,
      dailyGoal: dailyGoal ?? this.dailyGoal,
    );
  }
}
