package com.example.focus_mate

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.focus_mate/blocker"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "setBlockedApps") {
                // Receive list from Flutter
                val apps = call.argument<List<String>>("apps")
                if (apps != null) {
                    FocusAccessibilityService.blockedPackageNames = apps
                    result.success(true)
                } else {
                    result.error("INVALID", "List was null", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}