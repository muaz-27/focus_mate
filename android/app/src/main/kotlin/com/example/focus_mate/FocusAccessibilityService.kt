package com.example.focus_mate

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent
import android.util.Log
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import androidx.core.app.NotificationCompat
import android.content.pm.ServiceInfo

class FocusAccessibilityService : AccessibilityService() {

    companion object {
        var blockedPackageNames: List<String> = ArrayList()
        private const val PREFS_NAME = "FocusMatePrefs"
        private const val KEY_BLOCKED_APPS = "blocked_apps"

        fun updateBlockedApps(context: Context, apps: List<String>) {
            blockedPackageNames = apps
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit().putStringSet(KEY_BLOCKED_APPS, apps.toSet()).apply()
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        createNotificationChannel()
        loadBlockedApps()
        startForegroundService()
        Log.d("FocusMate", "Service Connected & Foreground Started")
    }

    private fun loadBlockedApps() {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val set = prefs.getStringSet(KEY_BLOCKED_APPS, emptySet())
        blockedPackageNames = set?.toList() ?: emptyList()
        Log.d("FocusMate", "Loaded blocked apps: $blockedPackageNames")
    }

    private fun startForegroundService() {
        try {
            val notification = NotificationCompat.Builder(this, "focus_mate_service_channel")
                .setContentTitle("FocusMate Active")
                .setContentText("Monitoring for distractions...")
                .setSmallIcon(android.R.drawable.ic_lock_lock)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .build()

            if (Build.VERSION.SDK_INT >= 34) { // Android 14+
                startForeground(101, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } else {
                startForeground(101, notification)
            }
        } catch (e: Exception) {
            Log.e("FocusMate", "Error starting foreground service: ${e.message}")
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null || event.packageName == null) return

        val packageName = event.packageName.toString()

        // CRITICAL: Never block ourselves!
        if (packageName == this.packageName) return

        if (blockedPackageNames.contains(packageName)) {
            Log.d("FocusMate", "Blocking: $packageName")
            
            // 1. Force Home
            performGlobalAction(GLOBAL_ACTION_HOME)

            // 2. Show Notification (Instead of Toast)
            showBlockNotification(packageName)
        }
    }

    private fun showBlockNotification(pkg: String) {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent, PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, "focus_mate_alert_channel")
            .setContentTitle("🚫 Access Denied")
            .setContentText("FocusMate blocked $pkg. Stay focused!")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(2, notification)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)

            // Channel for the Foreground Service (Silent/Low Priority)
            val serviceChannel = NotificationChannel(
                "focus_mate_service_channel",
                "Focus Service",
                NotificationManager.IMPORTANCE_LOW
            )
            serviceChannel.description = "Keeps FocusMate running"
            manager.createNotificationChannel(serviceChannel)

            // Channel for Alerts (High Priority)
            val alertChannel = NotificationChannel(
                "focus_mate_alert_channel",
                "Focus Alerts",
                NotificationManager.IMPORTANCE_HIGH
            )
            alertChannel.description = "Alerts when a blocked app is opened"
            manager.createNotificationChannel(alertChannel)
        }
    }

    override fun onInterrupt() {}
}