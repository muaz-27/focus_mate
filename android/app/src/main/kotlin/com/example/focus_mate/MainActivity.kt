package com.example.focus_mate

import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.focus_mate/blocker"
    
    companion object {
        var captureResult: MethodChannel.Result? = null
        private const val REQUEST_STARTUP_PERMISSION = 1001
        private const val REQUEST_CAPTURE_PERMISSION = 1002
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            
            if (call.method == "setBlockedApps") {
                val apps = call.argument<List<String>>("apps")
                if (apps != null) { FocusAccessibilityService.updateUserBlockedApps(context, apps); result.success(true) }
                else result.error("INVALID", "App list null", null)
            } 
            else if (call.method == "setCompanionBlockedApps") {
                val apps = call.argument<List<String>>("apps")
                if (apps != null) { FocusAccessibilityService.updateCompanionBlockedApps(context, apps); result.success(true) }
                else result.error("INVALID", "App list null", null)
            }
            else if (call.method == "setSchedules") {
                val schedulesJson = call.argument<String>("schedulesJson")
                if (schedulesJson != null) { FocusAccessibilityService.updateSchedules(context, schedulesJson); result.success(true) }
                else result.error("INVALID", "Schedules JSON null", null)
            }
            else if (call.method == "isAccessibilityServiceAlive") {
                result.success(isAccessibilityServiceEnabled(context, FocusAccessibilityService::class.java))
            }
            else if (call.method == "isSnapshotServiceRunning") {
                result.success(SnapshotService.isRunning)
            } 
            // Called at startup: shows the one-time permission dialog
            else if (call.method == "requestScreenCapturePermission") {
                if (SnapshotService.isRunning) {
                    // Already running from a previous session — no dialog needed
                    result.success(true)
                } else {
                    val pm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                    startActivityForResult(pm.createScreenCaptureIntent(), REQUEST_STARTUP_PERMISSION)
                    result.success(true)
                }
            }
            // Called each time a capture is needed
            else if (call.method == "captureScreen") {
                captureResult = result
                if (SnapshotService.isRunning) {
                    // VirtualDisplay is alive — capture silently with no dialog
                    val intent = Intent(this, SnapshotService::class.java).apply {
                        action = SnapshotService.ACTION_CAPTURE
                    }
                    startService(intent)
                } else {
                    // Service not running: we can't safely request permission from background.
                    // The startup initScreenCapture() will handle restarting the service
                    // when the child next opens the app.
                    android.util.Log.w("FocusMate", "captureScreen: service not running — returning error")
                    captureResult?.error("SERVICE_NOT_READY", "Screen monitoring not active", null)
                    captureResult = null
                }
            }
            else if (call.method == "stopScreenCaptureService") {
                if (SnapshotService.isRunning) {
                    val intent = Intent(this, SnapshotService::class.java)
                    stopService(intent)
                }
                result.success(true)
            }
            else {
                result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        val isOk = resultCode == Activity.RESULT_OK && data != null
        when (requestCode) {
            REQUEST_STARTUP_PERMISSION -> {
                if (isOk) startSnapshotService(resultCode, data!!, captureNow = false)
            }
            REQUEST_CAPTURE_PERMISSION -> {
                if (isOk) {
                    startSnapshotService(resultCode, data!!, captureNow = true)
                } else {
                    captureResult?.error("PERMISSION_DENIED", "Screen capture permission denied", null)
                    captureResult = null
                }
            }
        }
    }

    private fun startSnapshotService(resultCode: Int, data: Intent, captureNow: Boolean) {
        val intent = Intent(this, SnapshotService::class.java).apply {
            action = if (captureNow) "START_AND_CAPTURE" else SnapshotService.ACTION_START
            putExtra("resultCode", resultCode)
            putExtra("data", data)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent)
        else startService(intent)
    }

    private fun isAccessibilityServiceEnabled(context: android.content.Context, service: Class<out android.accessibilityservice.AccessibilityService>): Boolean {
        val expectedComponentName = android.content.ComponentName(context, service)
        val setting = android.provider.Settings.Secure.getString(context.contentResolver, android.provider.Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: return false
        val splitter = android.text.TextUtils.SimpleStringSplitter(':')
        splitter.setString(setting)
        while (splitter.hasNext()) {
            val component = android.content.ComponentName.unflattenFromString(splitter.next())
            if (component != null && component == expectedComponentName) return true
        }
        return false
    }
}