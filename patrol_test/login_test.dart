import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:focus_mate/main.dart' as app;

void main() {
  patrolTest(
    'student_login_flow',
    ($) async {
      // 1. Launch the app
      app.main();

      // 2. Wait for the splash screen to finish and the AuthScreen to appear
      await $(RegExp('Student', caseSensitive: false)).waitUntilVisible(timeout: const Duration(seconds: 10));

      // 3. Tap on the Student role card
      await $(RegExp('Student', caseSensitive: false)).tap();

      // 4. Wait for the LoginScreen to appear by checking for "Sign In"
      await $(RegExp('Sign In', caseSensitive: false)).waitUntilVisible();

      // 5. Enter the test credentials
      // The email field is the first TextField on the screen
      await $(TextField).at(0).enterText('student@gmail.com');
      
      // The password field is the second TextField on the screen
      await $(TextField).at(1).enterText('12345678');

      // 6. Tap the "Sign In" button to authenticate with Firebase
      await $(RegExp('Sign In', caseSensitive: false)).tap();

      // 7. Wait for Firebase Authentication to complete and the StudentDashboard to load
      // The dashboard header contains the text "Welcome back,"
      await $(RegExp('Welcome back,', caseSensitive: false)).waitUntilVisible(timeout: const Duration(seconds: 15));

      // 8. Assert that the dashboard successfully loaded
      expect($(RegExp('Welcome back,', caseSensitive: false)).exists, isTrue);
    },
  );
}
