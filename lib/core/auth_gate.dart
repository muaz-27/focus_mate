import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focus_mate/providers/auth_provider.dart';
import 'package:focus_mate/providers/user_provider.dart';
import 'package:focus_mate/auth/auth_screen.dart';
import 'package:focus_mate/auth/email_verification_screen.dart';
import 'package:focus_mate/core/dashboard_router.dart';

/// Root authentication gate.
///
/// Uses Riverpod providers instead of nested StreamBuilder/FutureBuilder.
/// Watches [authStateProvider] for login state and [userProvider] for profile data.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => AuthScreen(onAuthComplete: (_, __) {}),
      data: (user) {
        // Not logged in
        if (user == null) {
          return AuthScreen(onAuthComplete: (_, __) {});
        }

        // Email not verified
        if (!user.emailVerified) {
          return const EmailVerificationScreen();
        }

        // Logged in + verified — watch user profile
        final userState = ref.watch(userProvider);

        return userState.when(
          loading: () => const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
          error: (_, __) {
            // Auth exists but profile missing — sign out
            ref.read(authServiceProvider).signOut();
            return AuthScreen(onAuthComplete: (_, __) {});
          },
          data: (userModel) {
            if (userModel == null) {
              ref.read(authServiceProvider).signOut();
              return AuthScreen(onAuthComplete: (_, __) {});
            }

            return const DashboardRouter();
          },
        );
      },
    );
  }
}
