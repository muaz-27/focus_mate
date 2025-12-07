package com.example.focus_mate

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent
import android.util.Log
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import android.content.pm.ServiceInfo

class FocusAccessibilityService : AccessibilityService() {

    companion object {
        private const val PREFS_NAME = "FocusMatePrefs"
        private const val KEY_USER_BLOCKED = "user_blocked_apps"
        private const val KEY_COMPANION_BLOCKED = "companion_blocked_apps"

        // We use Sets to avoid duplicates
        var userBlockedApps: Set<String> = HashSet()
        var companionBlockedApps: Set<String> = HashSet()

        // 1. Update the User's personal block list
        fun updateUserBlockedApps(context: Context, apps: List<String>) {
            userBlockedApps = apps.toSet()
            savePreferences(context)
            Log.d("FocusMate", "User Block List Updated: $userBlockedApps")
        }

        // 2. Update the Companion's block list (Does NOT overwrite user list)
        fun updateCompanionBlockedApps(context: Context, apps: List<String>) {
            companionBlockedApps = apps.toSet()
            savePreferences(context)
            Log.d("FocusMate", "Companion Block List Updated: $companionBlockedApps")
        }

        private fun savePreferences(context: Context) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit()
                .putStringSet(KEY_USER_BLOCKED, userBlockedApps)
                .putStringSet(KEY_COMPANION_BLOCKED, companionBlockedApps)
                .apply()
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        createNotificationChannel()
        loadPreferences()
        startForegroundService()
        Log.d("FocusMate", "Accessibility Service Connected")
    }

    private fun loadPreferences() {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        userBlockedApps = prefs.getStringSet(KEY_USER_BLOCKED, emptySet()) ?: emptySet()
        companionBlockedApps = prefs.getStringSet(KEY_COMPANION_BLOCKED, emptySet()) ?: emptySet()
        
        Log.d("FocusMate", "Loaded Lists -> User: $userBlockedApps | Companion: $companionBlockedApps")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null || event.packageName == null) return

        val packageName = event.packageName.toString()

        // --- CRITICAL FIX: ENABLE APP NAVIGATION ---
        // This ensures the service NEVER blocks FocusMate, allowing the user
        // to navigate inside the app even if "Companion Mode" is active.
        if (packageName == applicationContext.packageName) {
            return 
        }
        // -------------------------------------------

        // Combine both lists dynamically
        val allBlockedApps = userBlockedApps + companionBlockedApps

        if (allBlockedApps.contains(packageName)) {
            Log.d("FocusMate", "Blocking detected package: $packageName")
            
            // 1. Force the user back to the Home Screen
            performGlobalAction(GLOBAL_ACTION_HOME)
            
            // 2. Show the "Access Denied" notification
            showBlockNotification(packageName)
        }
    }

    private fun showBlockNotification(pkg: String) {
        // Intent to bring FocusMate to front if notification is clicked
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent, PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, "focus_mate_alert_channel")
            .setContentTitle("🚫 Focus Mode Active")
            .setContentText("This app is currently blocked.")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(2, notification)
    }

    private fun startForegroundService() {
        try {
            val notification = NotificationCompat.Builder(this, "focus_mate_service_channel")
                .setContentTitle("FocusMate is Running")
                .setContentText("Monitoring app usage...")
                .setSmallIcon(android.R.drawable.ic_lock_lock)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .build()

            if (Build.VERSION.SDK_INT >= 34) {
                startForeground(101, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } else {
                startForeground(101, notification)
            }
        } catch (e: Exception) {
            Log.e("FocusMate", "Error starting foreground service: ${e.message}")
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            
            // Channel for the persistent notification
            val serviceChannel = NotificationChannel(
                "focus_mate_service_channel", "Focus Service", NotificationManager.IMPORTANCE_LOW
            )
            manager.createNotificationChannel(serviceChannel)

            // Channel for the "Blocked" alert
            val alertChannel = NotificationChannel(
                "focus_mate_alert_channel", "Focus Alerts", NotificationManager.IMPORTANCE_HIGH
            )
            manager.createNotificationChannel(alertChannel)
        }
    }

    override fun onInterrupt() {
        Log.d("FocusMate", "Service Interrupted")
    }
}