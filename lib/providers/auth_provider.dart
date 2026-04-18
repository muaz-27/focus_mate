import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focus_mate/core/auth_service.dart';

/// Singleton instance of [AuthService].
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

/// Streams the current [User] from Firebase Auth.
/// Emits null when the user is logged out.
final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});
