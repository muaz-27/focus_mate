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

class FocusAccessibilityService : AccessibilityService() {

    companion object {
        var blockedPackageNames: List<String> = ArrayList()
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        createNotificationChannel()
        Log.d("FocusMate", "Service Connected")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null || event.packageName == null) return

        val packageName = event.packageName.toString()

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

        val notification = NotificationCompat.Builder(this, "focus_mate_channel")
            .setContentTitle("🚫 Access Denied")
            .setContentText("FocusMate blocked $pkg. Stay focused!")
            .setSmallIcon(android.R.drawable.ic_lock_lock) // Default lock icon
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(1, notification)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "focus_mate_channel",
                "Focus Alerts",
                NotificationManager.IMPORTANCE_HIGH
            )
            channel.description = "Alerts when a blocked app is opened"
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    override fun onInterrupt() {}
}