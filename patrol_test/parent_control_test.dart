import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:focus_mate/main.dart' as app;

void main() {
  patrolTest(
    'parent_remote_control_flow',
    ($) async {
      // 1. Launch the app
      app.main();

      // 2. Wait for Splash Screen & Select "Parent" Role
      // We assume the app data was cleared before this test so we start fresh!
      await $(RegExp(r'^Parent$', caseSensitive: false)).waitUntilVisible(timeout: const Duration(seconds: 10));
      await Future.delayed(const Duration(seconds: 1));
      await $(RegExp(r'^Parent$', caseSensitive: false)).tap();
      await Future.delayed(const Duration(seconds: 1));

      // 3. Login Flow
      await $(RegExp(r'^Sign In$', caseSensitive: false)).waitUntilVisible();
      await $(TextField).at(0).enterText('parent@gmail.com');
      await $(TextField).at(1).enterText('p12345678');
      
      // Tap the Sign In button
      await $(RegExp(r'^Sign In$', caseSensitive: false)).tap();

      // 4. Wait for Parent Dashboard to render
      await $(RegExp('Parent Dashboard|Monitored Children', caseSensitive: false))
          .waitUntilVisible(timeout: const Duration(seconds: 15));

      // 5. NATIVE OS INTERACTION!
      // This is Patrol's superpower. We will pull down the Android Notification shade natively,
      // wait 2 seconds so you can see it, and then close it using the native back button.
      await $.native.openNotifications();
      await Future.delayed(const Duration(seconds: 2));
      await $.native.pressBack();

      // 6. Enter the Remote Control Interface
      // It looks for the first "Control" button on the monitored student list
      await $(RegExp('Control', caseSensitive: false)).waitUntilVisible(timeout: const Duration(seconds: 10));
      await $(RegExp('Control', caseSensitive: false)).tap();

      // 7. Verify we successfully routed to the ParentChildControlPage
      await $(RegExp('App Locks', caseSensitive: false)).waitUntilVisible(timeout: const Duration(seconds: 10));

      // Navigate to the Analytics tab of the child
      await $(RegExp('Analytics', caseSensitive: false)).tap();

      // Pause to ensure UI animation completes smoothly
      await Future.delayed(const Duration(seconds: 2));

      // 8. Final Assertion: Ensure we are inside the Analytics tab
      expect($(RegExp('Analytics', caseSensitive: false)).exists, isTrue);
    },
  );
}
