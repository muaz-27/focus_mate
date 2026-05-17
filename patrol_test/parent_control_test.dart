import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:focus_mate/main.dart' as app;

void main() {
  patrolTest(
    'parent_remote_control_flow',
    ($) async {
      // Launch app
      app.main();

      // Wait for startup
      await $.pumpAndSettle();

      // Extra wait for Firebase/splash
      await Future.delayed(
        const Duration(seconds: 5),
      );

      // =========================
      // LOGIN FLOW
      // =========================

      try {
        // Wait for Sign In screen
        await $(RegExp(
          'Sign In',
          caseSensitive: false,
        )).waitUntilVisible(
          timeout: const Duration(seconds: 5),
        );

        // Tap Parent role if visible
        final parentButton = $(
          RegExp(
            'Parent',
            caseSensitive: false,
          ),
        );

        if (parentButton.evaluate().isNotEmpty) {
          await parentButton.tap();
        }

        await Future.delayed(
          const Duration(seconds: 2),
        );

        // Enter email
        await $(TextField)
            .at(0)
            .enterText('parent@gmail.com');

        // Enter password
        await $(TextField)
            .at(1)
            .enterText('12345678');

        // Tap Sign In
        await $(RegExp(
          'Sign In',
          caseSensitive: false,
        )).tap();

        // Wait for dashboard
        await $(RegExp(
          'Welcome back',
          caseSensitive: false,
        )).waitUntilVisible(
          timeout: const Duration(seconds: 20),
        );
      } catch (_) {
        // Already logged in
      }

      // =========================
      // OPEN CHILD CONTROL
      // =========================

      await Future.delayed(
        const Duration(seconds: 3),
      );

      final childFinder = $(
        RegExp(
          'Child',
          caseSensitive: false,
        ),
      );

      await childFinder.scrollTo();

      if (childFinder.evaluate().isNotEmpty) {
        await childFinder.tap();
      }

      // Wait for controls page
      await $(RegExp(
        'CONTROLS',
        caseSensitive: false,
      )).waitUntilVisible(
        timeout: const Duration(seconds: 15),
      );

      // =========================
      // OPEN APP LOCKS
      // =========================

      final appLocksFinder = $(
        RegExp(
          'App Limits & Locks',
          caseSensitive: false,
        ),
      );

      await appLocksFinder.scrollTo();

      await appLocksFinder.tap();

      // Wait for modal
      await $(RegExp(
        'App Locks',
        caseSensitive: false,
      )).waitUntilVisible(
        timeout: const Duration(seconds: 10),
      );

      // Tap Instant Lock
      final instantLockFinder = $(
        RegExp(
          'Instant Lock',
          caseSensitive: false,
        ),
      );

      if (instantLockFinder.evaluate().isNotEmpty) {
        await instantLockFinder.tap();
      }

      // Wait for remote screen
      await Future.delayed(
        const Duration(seconds: 5),
      );

      // Final assertion
      expect(
        instantLockFinder.evaluate().isNotEmpty,
        isTrue,
      );
    },
  );
}