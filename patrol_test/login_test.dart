import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:patrol/patrol.dart';
import 'package:focus_mate/main.dart' as app;

void main() {
  // CRITICAL: Disable GoogleFonts network fetching.
  // Without this, the test crashes with "Connection reset by peer" when the
  // splash screen tries to load fonts from fonts.gstatic.com during the test.
  GoogleFonts.config.allowRuntimeFetching = false;

  patrolTest(
    'student_login_flow',
    ($) async {
      // 1. Launch the app
      app.main();

      // 2. The splash screen shows a 'Student' badge within ~1s of startup.
      //    We must wait past the splash duration (3.8s anim + 0.6s fade = 4.4s)
      //    before asserting on the role selection screen.
      await Future.delayed(const Duration(seconds: 5));

      // 3. Now wait for the role selection screen's Student card to appear.
      //    "Take control" is the Student card's unique description — it only
      //    exists on the AuthScreen, not the SplashScreen.
      await $(RegExp('Take control', caseSensitive: false))
          .waitUntilVisible(timeout: const Duration(seconds: 20));

      // 4. Tap the Student card — the whole card is a GestureDetector, so
      //    tapping any text in it (including the description) triggers navigation.
      await $(RegExp('Take control', caseSensitive: false)).tap();
      // Wait for the login screen to fully render
      await Future.delayed(const Duration(seconds: 2));

      // 4. Wait for the LoginScreen to appear by checking for "Sign In"
      //    Give Firebase time to render the login form.
      await $(RegExp('Sign In', caseSensitive: false))
          .waitUntilVisible(timeout: const Duration(seconds: 20));

      // 5. Enter the test credentials
      await $(TextField).at(0).enterText('student@gmail.com');
      await $(TextField).at(1).enterText('12345678');

      // 6. After typing, the soft keyboard may push the Sign In button below
      //    the visible viewport. scrollTo() scrolls it back into the
      //    hit-testable area above the keyboard before tapping.
      await $(RegExp('Sign In', caseSensitive: false)).scrollTo();
      await $(RegExp('Sign In', caseSensitive: false)).tap();

      // 7. Wait for Firebase Authentication to complete and the StudentDashboard to load
      await $(RegExp('Welcome back,', caseSensitive: false))
          .waitUntilVisible(timeout: const Duration(seconds: 20));

      // 8. Assert that the dashboard successfully loaded
      expect($(RegExp('Welcome back,', caseSensitive: false)).exists, isTrue);
    },
  );
}
