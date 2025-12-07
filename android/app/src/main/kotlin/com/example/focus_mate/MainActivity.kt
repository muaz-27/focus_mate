package com.example.focus_mate

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.focus_mate/blocker"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            
            // Handler 1: Update USER Blocked Apps
            if (call.method == "setBlockedApps") {
                val apps = call.argument<List<String>>("apps")
                if (apps != null) {
                    FocusAccessibilityService.updateUserBlockedApps(context, apps)
                    result.success(true)
                } else {
                    result.error("INVALID", "App list was null", null)
                }
            } 
            // Handler 2: Update COMPANION Blocked Apps (New Logic)
            else if (call.method == "setCompanionBlockedApps") {
                val apps = call.argument<List<String>>("apps")
                if (apps != null) {
                    FocusAccessibilityService.updateCompanionBlockedApps(context, apps)
                    result.success(true)
                } else {
                    result.error("INVALID", "App list was null", null)
                }
            }
            // Handler 3: Check Permissions
            else if (call.method == "isAccessibilityEnabled") {
                val enabled = isAccessibilityServiceEnabled(context, FocusAccessibilityService::class.java)
                result.success(enabled)
            } 
            else {
                result.notImplemented()
            }
        }
    }

    private fun isAccessibilityServiceEnabled(context: android.content.Context, service: Class<out android.accessibilityservice.AccessibilityService>): Boolean {
        val expectedComponentName = android.content.ComponentName(context, service)
        val enabledServicesSetting = android.provider.Settings.Secure.getString(
            context.contentResolver,
            android.provider.Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false

        val colonSplitter = android.text.TextUtils.SimpleStringSplitter(':')
        colonSplitter.setString(enabledServicesSetting)

        while (colonSplitter.hasNext()) {
            val componentNameString = colonSplitter.next()
            val enabledComponent = android.content.ComponentName.unflattenFromString(componentNameString)
            if (enabledComponent != null && enabledComponent == expectedComponentName) {
                return true
            }
        }
        return false
    }
}