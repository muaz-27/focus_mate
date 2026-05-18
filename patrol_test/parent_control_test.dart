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

      // 5. Enter the Remote Control Interface
      // It looks for the first "Control" button on the monitored student list
      await $(RegExp('Control', caseSensitive: false)).waitUntilVisible(timeout: const Duration(seconds: 10));
      await $(RegExp('Control', caseSensitive: false)).tap();

      // 6. Verify we successfully routed to the ParentChildControlPage (the control list)
      await $(RegExp('App Limits & Locks', caseSensitive: false)).waitUntilVisible(timeout: const Duration(seconds: 10));

      // Pause to ensure UI animation completes smoothly
      await Future.delayed(const Duration(seconds: 2));

      // 7. Open the Snapshots Viewer
      await $(RegExp('Snapshots', caseSensitive: false)).tap();
      
      // Wait for the Snapshots Screen to fully render (either it shows snapshots or "No snapshots yet")
      await $(RegExp('Snapshots|Recent|No snapshots yet', caseSensitive: false)).waitUntilVisible(timeout: const Duration(seconds: 10));

      // Keep the screen open for 5 seconds so you can visually verify it loaded
      await Future.delayed(const Duration(seconds: 5));

      // 8. Click the arrow Back Button in the top left corner
      await $(BackButton).tap();

      // Pause for 2 seconds to see the back animation finish
      await Future.delayed(const Duration(seconds: 2));

      // 9. Open App Limits & Locks Modal
      await $(RegExp('App Limits & Locks', caseSensitive: false)).tap();
      await Future.delayed(const Duration(seconds: 1));

      // 10. Tap Instant Lock
      await $(RegExp('Instant Lock', caseSensitive: false)).tap();
      
      // Give the screen a moment to open and start its fetching process
      await Future.delayed(const Duration(seconds: 2));

      // Actively wait for the data to finish loading by checking if the loading text is still there (up to 30 seconds)
      for (int i = 0; i < 30; i++) {
        final isRefreshing = $(RegExp('Refreshing from device', caseSensitive: false)).exists;
        final isLoading = $(RegExp('Loading apps from child', caseSensitive: false)).exists;
        
        if (!isRefreshing && !isLoading) {
          break; // Data is fully loaded!
        }
        await Future.delayed(const Duration(seconds: 1));
      }

      // Now that the data is definitely loaded, pause for 5 seconds so you can see the fully loaded screen
      await Future.delayed(const Duration(seconds: 5));
    },
  );
}
