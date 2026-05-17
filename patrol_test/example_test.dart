import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:focus_mate/main.dart' as app;

void main() {
  patrolTest(
    'app_launches_and_shows_initial_screen',
    ($) async {
      // Launch the app
      app.main();

      // Wait for the splash screen to finish and the AuthScreen to appear.
      // We use Patrol's idiomatic selector `$` to find and wait for the 'Student' text.
      await $(RegExp('Student', caseSensitive: false)).waitUntilVisible(timeout: const Duration(seconds: 10));

      // Tap on the Student role card
      await $(RegExp('Student', caseSensitive: false)).tap();

      // Verify that it transitioned to the Login/Signup screen by checking for the Sign In button
      await $(RegExp('Sign In', caseSensitive: false)).waitUntilVisible();
    },
  );
}
