import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:focus_mate/main.dart' as app;

void main() {
  patrolTest(
    'student_dashboard_companion_request_flow',
    ($) async {
      // =========================================================
      // 1. Launch the app
      // =========================================================
      app.main();

      // Wait for the splash screen animation to complete (~3.8s)
      // and for Firebase/AuthGate to initialise.
      await $.pumpAndSettle();
      await Future.delayed(const Duration(seconds: 6));

      // =========================================================
      // 2. LOGIN FLOW (handles clearPackageData wiping auth state)
      //
      // NOTE: System-level Android permissions (Accessibility,
      // Usage Stats, Overlay, Draw-on-top, Battery Optimisation)
      // are stored at OS level and are NOT cleared by
      // clearPackageData – so grant them once manually; they
      // will persist across all test runs.
      // =========================================================
      try {
        // If the login / role-selection screen is visible, log in.
        await $(RegExp('Sign In', caseSensitive: false)).waitUntilVisible(
          timeout: const Duration(seconds: 8),
        );

        // Select the Student role if the selector is shown.
        final studentButton = $(RegExp('Student', caseSensitive: false));
        if (studentButton.evaluate().isNotEmpty) {
          await studentButton.tap();
          await Future.delayed(const Duration(seconds: 1));
        }

        // Enter student credentials.
        // *** UPDATE THESE TO MATCH YOUR FIREBASE TEST ACCOUNT ***
        await $(TextField).at(0).enterText('student@gmail.com');
        await $(TextField).at(1).enterText('12345678');

        // Tap Sign In.
        await $(RegExp('Sign In', caseSensitive: false)).tap();

        // Wait for the Student Dashboard to appear.
        await $(RegExp('App Lock', caseSensitive: false)).waitUntilVisible(
          timeout: const Duration(seconds: 30),
        );
      } catch (_) {
        // Already logged in as student – fall through to the dashboard.
      }

      // =========================================================
      // 3. Verify we are on the Student Dashboard
      // =========================================================
      try {
        await $(RegExp('App Lock', caseSensitive: false)).waitUntilVisible(
          timeout: const Duration(seconds: 15),
        );
      } catch (e) {
        fail(
          'Could not reach the Student Dashboard.\n'
          'Make sure:\n'
          '  • A valid student account exists in Firebase (student@gmail.com / 12345678).\n'
          '  • Android system permissions (Accessibility, Usage Stats, Overlay,\n'
          '    Battery Optimisation) are pre-granted on the device – they survive\n'
          '    clearPackageData and only need granting once.\n'
          'Error: $e',
        );
      }

      // =========================================================
      // 4. Automate: Student Dashboard → App Lock → Companion Control
      // =========================================================

      // Scroll to "App Lock" if needed, then tap it.
      await $(RegExp('App Lock', caseSensitive: false)).scrollTo().tap();

      // Wait for the Lock Mode selection modal.
      await $(RegExp('Companion Control', caseSensitive: false))
          .waitUntilVisible(timeout: const Duration(seconds: 10));

      // Select "Companion Control".
      await $(RegExp('Companion Control', caseSensitive: false)).tap();

      // Tap "Confirm".
      await $(RegExp('Confirm', caseSensitive: false)).waitUntilVisible();
      await $(RegExp('Confirm', caseSensitive: false)).tap();

      // Wait for the Companion Request page.
      await $(RegExp('Start Request', caseSensitive: false))
          .waitUntilVisible(timeout: const Duration(seconds: 15));

      // Tap "Start Request".
      await $(RegExp('Start Request', caseSensitive: false)).tap();

      // Allow a moment to verify the UI moved past the request page.
      await $.pumpAndSettle();
      await Future.delayed(const Duration(seconds: 3));
    },
  );
}
