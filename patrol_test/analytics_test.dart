import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:focus_mate/main.dart' as app;

void main() {
  patrolTest(
    'analytics_dashboard_flow',
    ($) async {
      // 1. Launch the app
      app.main();

      // 2. Wait for Splash Screen & Handle Persistent Login State
      // Since a previous test may have logged us in, we check if the dashboard appears first.
      try {
        await $(RegExp('Welcome back,', caseSensitive: false)).waitUntilVisible(timeout: const Duration(seconds: 8));
        // If we found the dashboard, we are already logged in! Skip to step 5.
      } catch (e) {
        // If it timed out, we must be on the AuthScreen. Let's log in.
        await $(RegExp('Student', caseSensitive: false)).tap();
        
        await $(RegExp('Sign In', caseSensitive: false)).waitUntilVisible();
        await $(TextField).at(0).enterText('student@gmail.com');
        await $(TextField).at(1).enterText('12345678');
        await $(RegExp('Sign In', caseSensitive: false)).tap();

        // 4. Wait for Dashboard to render after login
        await $(RegExp('Welcome back,', caseSensitive: false)).waitUntilVisible(timeout: const Duration(seconds: 15));
      }

      // 5. Scroll down to the Analytics tile and tap it
      // scrollTo() automatically finds a scrollable container and scrolls until the target is visible
      await $(RegExp('Analytics', caseSensitive: false)).scrollTo().tap();

      // 6. Verify we successfully entered the Analytics Screen
      // The screen header is "My Stats's Insights" and there is a "Quizzes" action button
      await $(RegExp('Insights|Quizzes', caseSensitive: false)).waitUntilVisible(timeout: const Duration(seconds: 10));

      // Wait for the data to finish loading (SingleChildScrollView appears)
      await $(Scrollable).waitUntilVisible(timeout: const Duration(seconds: 15));

      // 7. Scroll down the Analytics Dashboard to ensure all charts and widgets render without layout overflow errors
      // scrollTo() automatically scrolls the view until the text is found
      await $(RegExp('Weekly Average', caseSensitive: false)).scrollTo();

      // 8. Final Assertion
      expect($(RegExp('Quizzes', caseSensitive: false)).exists, isTrue);
    },
  );
}
