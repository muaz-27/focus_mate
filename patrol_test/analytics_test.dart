import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:patrol/patrol.dart';
import 'package:focus_mate/main.dart' as app;

void main() {
  // CRITICAL: Disable GoogleFonts network fetching to prevent connection
  // errors during tests when the splash screen tries to load fonts.
  GoogleFonts.config.allowRuntimeFetching = false;

  patrolTest(
    'analytics_dashboard_flow',
    ($) async {
      // 1. Launch the app
      app.main();

      // 2. Wait for Splash Screen & Handle Persistent Login State.
      // The splash runs for ~3.8s + 600ms fade. Delay past it first so we
      // don't confuse the splash's 'Student' badge with the role card.
      await Future.delayed(const Duration(seconds: 5));

      // Check if the dashboard is already visible (persistent login from a
      // previous test run). Use try/catch because one or the other must be true.
      try {
        await $(RegExp('Welcome back,', caseSensitive: false))
            .waitUntilVisible(timeout: const Duration(seconds: 10));
        // Already logged in — skip the login flow.
      } catch (e) {
        // Not logged in. Navigate through role selection and login.

        // Tap the Student card using its unique description text.
        // This avoids accidentally tapping the splash's 'Student' badge.
        await $(RegExp('Take control', caseSensitive: false))
            .waitUntilVisible(timeout: const Duration(seconds: 20));
        await $(RegExp('Take control', caseSensitive: false)).tap();
        await Future.delayed(const Duration(seconds: 2));

        // Wait for the login form to appear
        await $(RegExp('Sign In', caseSensitive: false))
            .waitUntilVisible(timeout: const Duration(seconds: 20));
        await $(TextField).at(0).enterText('student@gmail.com');
        await $(TextField).at(1).enterText('12345678');

        // scrollTo() brings Sign In into view above the keyboard before tapping
        await $(RegExp('Sign In', caseSensitive: false)).scrollTo();
        await $(RegExp('Sign In', caseSensitive: false)).tap();

        // Wait for Firebase auth and dashboard to render
        await $(RegExp('Welcome back,', caseSensitive: false))
            .waitUntilVisible(timeout: const Duration(seconds: 30));
      }

      // 5. Scroll down to the Analytics tile and tap it
      await $(RegExp('Analytics', caseSensitive: false)).scrollTo().tap();

      // 6. Verify we successfully entered the Analytics Screen
      await $(RegExp('Insights|Quizzes', caseSensitive: false))
          .waitUntilVisible(timeout: const Duration(seconds: 15));

      // Wait for the data to finish loading
      await $(Scrollable).waitUntilVisible(timeout: const Duration(seconds: 15));

      // 7. Scroll down the Analytics Dashboard to check all widgets render
      await $(RegExp('Weekly Average', caseSensitive: false)).scrollTo();

      // 8. Final Assertion
      expect($(RegExp('Quizzes', caseSensitive: false)).exists, isTrue);
    },
  );
}

