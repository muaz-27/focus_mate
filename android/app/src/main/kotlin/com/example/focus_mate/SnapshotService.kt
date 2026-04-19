package com.example.focus_mate

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.DisplayMetrics
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer

class SnapshotService : Service() {

    private var handlerThread: HandlerThread? = null
    private var backgroundHandler: Handler? = null
    private var mediaProjection: MediaProjection? = null

    // Persistent display + reader — kept alive for the lifetime of the projection
    private var persistentDisplay: VirtualDisplay? = null
    private var persistentReader: ImageReader? = null
    private var latestFrameBytes: ByteArray? = null

    // Screen metrics
    private var screenWidth   = 0
    private var screenHeight  = 0
    private var screenDensity = 0
    private var wakeLock: PowerManager.WakeLock? = null

    companion object {
        const val NOTIFICATION_ID          = 2001
        const val CHANNEL_ID               = "SnapshotServiceChannel"
        const val ACTION_START             = "START"
        const val ACTION_CAPTURE           = "CAPTURE"
        const val ACTION_START_AND_CAPTURE = "START_AND_CAPTURE"

        @Volatile var isRunning = false
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        handlerThread = HandlerThread("SnapshotBg")
        handlerThread?.start()
        backgroundHandler = Handler(handlerThread!!.looper)
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, createNotification())

        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "FocusMate::SnapshotWakeLock")
        wakeLock?.acquire()

        android.util.Log.d("FocusMate", "SnapshotService: onCreate isRunning=true, wakeLock acquired")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ""
        android.util.Log.d("FocusMate", "SnapshotService: onStartCommand action='$action' has_projection=${mediaProjection != null}")

        when (action) {
            ACTION_START, ACTION_START_AND_CAPTURE -> {
                if (mediaProjection == null) initProjection(intent!!)
                if (action == ACTION_START_AND_CAPTURE) captureAndReturn()
            }
            ACTION_CAPTURE -> {
                if (mediaProjection == null) {
                    // Try to recover
                    android.util.Log.w("FocusMate", "CAPTURE: no projection, attempting recovery")
                    val recovered = tryRecoverProjection()
                    if (!recovered) {
                        android.util.Log.e("FocusMate", "CAPTURE: recovery failed")
                        Handler(Looper.getMainLooper()).post {
                            MainActivity.captureResult?.error("CAPTURE_FAILED", "Monitoring not active", null)
                            MainActivity.captureResult = null
                        }
                        return START_STICKY
                    }
                }
                captureAndReturn()
            }
            "" -> {
                android.util.Log.d("FocusMate", "SnapshotService: restarted by system")
                tryRecoverProjection()
            }
        }
        return START_STICKY
    }

    private fun saveProjectionCredentials(resultCode: Int, data: Intent) {
        savedProjectionData = data
        savedResultCode = resultCode
        android.util.Log.d("FocusMate", "Projection credentials saved")
    }

    private fun tryRecoverProjection(): Boolean {
        val data = savedProjectionData
        val resultCode = savedResultCode
        if (data == null || resultCode == 0) {
            android.util.Log.w("FocusMate", "No saved projection credentials")
            return false
        }
        return try {
            val pm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            val mp = pm.getMediaProjection(resultCode, data)
            if (mp != null) {
                setupProjection(mp)
                android.util.Log.d("FocusMate", "Projection recovered successfully")
                true
            } else {
                android.util.Log.w("FocusMate", "getMediaProjection returned null")
                false
            }
        } catch (e: Exception) {
            android.util.Log.e("FocusMate", "Projection recovery failed: ${e.message}")
            false
        }
    }

    private fun initProjection(intent: Intent) {
        val resultCode = intent.getIntExtra("resultCode", 0)
        val data       = intent.getParcelableExtra<Intent>("data")
        if (resultCode == 0 || data == null) return

        saveProjectionCredentials(resultCode, data)

        val pm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val mp = pm.getMediaProjection(resultCode, data) ?: return
        setupProjection(mp)
    }

    /**
     * Sets up a persistent VirtualDisplay + ImageReader that continuously receives
     * screen frames. This means the first AND subsequent captures are instant — we
     * just grab the last frame from the reader.
     */
    private fun setupProjection(mp: MediaProjection) {
        // Clean up any existing persistent resources
        tearDownPersistentDisplay()

        mp.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() {
                android.util.Log.d("FocusMate", "MediaProjection stopped externally")
                mediaProjection = null
                tearDownPersistentDisplay()
                android.util.Log.d("FocusMate", "Service staying alive for potential recovery")
            }
        }, Handler(Looper.getMainLooper()))

        mediaProjection = mp

        val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        wm.defaultDisplay.getRealMetrics(metrics)
        screenWidth   = metrics.widthPixels
        screenHeight  = metrics.heightPixels
        screenDensity = metrics.densityDpi

        android.util.Log.d("FocusMate", "MediaProjection ready: ${screenWidth}x${screenHeight}")

        // Create persistent ImageReader + VirtualDisplay
        createPersistentDisplay(mp)
    }

    /**
     * Creates and keeps alive a VirtualDisplay + ImageReader. The ImageReader
     * continuously receives frames from the system; we just grab the latest
     * whenever a capture is requested. This avoids the "second capture fails"
     * problem that happens when you destroy/recreate VirtualDisplays.
     */
    private fun createPersistentDisplay(mp: MediaProjection) {
        val reader = ImageReader.newInstance(screenWidth, screenHeight, PixelFormat.RGBA_8888, 2)

        reader.setOnImageAvailableListener({ imgReader ->
            val image = imgReader.acquireLatestImage()
            if (image != null) {
                try {
                    val plane       = image.planes[0]
                    val buffer      = plane.buffer as ByteBuffer
                    val rowPadding  = plane.rowStride - plane.pixelStride * screenWidth
                    val bitmapWidth = screenWidth + rowPadding / plane.pixelStride

                    val bmp = Bitmap.createBitmap(bitmapWidth, screenHeight, Bitmap.Config.ARGB_8888)
                    bmp.copyPixelsFromBuffer(buffer)
                    val cropped = Bitmap.createBitmap(bmp, 0, 0, screenWidth, screenHeight)

                    val out = ByteArrayOutputStream()
                    cropped.compress(Bitmap.CompressFormat.JPEG, 70, out)
                    latestFrameBytes = out.toByteArray()

                    bmp.recycle()
                    cropped.recycle()
                } catch (e: Exception) {
                    android.util.Log.e("FocusMate", "Frame processing error: ${e.message}")
                } finally {
                    image.close()
                }
            }
        }, backgroundHandler)

        try {
            val display = mp.createVirtualDisplay(
                "ScreenCapture",
                screenWidth, screenHeight, screenDensity,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                reader.surface, null, backgroundHandler
            )
            if (display != null) {
                persistentReader = reader
                persistentDisplay = display
                android.util.Log.d("FocusMate", "Persistent VirtualDisplay created successfully")
            } else {
                android.util.Log.e("FocusMate", "Persistent VirtualDisplay creation returned null")
                reader.close()
            }
        } catch (e: Exception) {
            android.util.Log.e("FocusMate", "Persistent VirtualDisplay creation failed: ${e.message}")
            reader.close()
        }
    }

    private fun tearDownPersistentDisplay() {
        try { persistentDisplay?.release() } catch (_: Exception) {}
        try { persistentReader?.close() } catch (_: Exception) {}
        persistentDisplay = null
        persistentReader = null
        latestFrameBytes = null
    }

    /**
     * Returns the latest cached frame to Flutter immediately.
     * If no frame is cached yet (e.g., display just started), waits briefly.
     */
    private fun captureAndReturn() {
        backgroundHandler?.post {
            // If we have a cached frame, return it immediately
            var bytes = latestFrameBytes
            if (bytes != null) {
                android.util.Log.d("FocusMate", "captureAndReturn: returning cached frame (${bytes.size} bytes)")
                Handler(Looper.getMainLooper()).post {
                    MainActivity.captureResult?.success(bytes)
                    MainActivity.captureResult = null
                }
                return@post
            }

            // No frame yet — wait up to 3 seconds for the first frame to arrive
            android.util.Log.d("FocusMate", "captureAndReturn: no cached frame, waiting up to 3s...")
            for (i in 0 until 30) {
                try { Thread.sleep(100) } catch (_: InterruptedException) {}
                bytes = latestFrameBytes
                if (bytes != null) {
                    android.util.Log.d("FocusMate", "captureAndReturn: got frame after ${(i+1)*100}ms (${bytes.size} bytes)")
                    Handler(Looper.getMainLooper()).post {
                        MainActivity.captureResult?.success(bytes)
                        MainActivity.captureResult = null
                    }
                    return@post
                }
            }

            // Still no frame after 3s — the projection might be dead
            android.util.Log.e("FocusMate", "captureAndReturn: no frame after 3s timeout")
            Handler(Looper.getMainLooper()).post {
                MainActivity.captureResult?.error("CAPTURE_FAILED", "No frame available", null)
                MainActivity.captureResult = null
            }
        }
    }

    override fun onDestroy() {
        android.util.Log.d("FocusMate", "SnapshotService.onDestroy")
        isRunning = false
        tearDownPersistentDisplay()
        handlerThread?.quitSafely()
        try { mediaProjection?.stop() } catch (_: Exception) {}
        try { wakeLock?.release() } catch (_: Exception) {}
        wakeLock = null
        stopForeground(true)
        super.onDestroy()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        android.util.Log.d("FocusMate", "SnapshotService: onTaskRemoved — service persists")
        super.onTaskRemoved(rootIntent)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(CHANNEL_ID, "Screen Monitoring", NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java).createNotificationChannel(ch)
        }
    }

    private fun createNotification(): Notification =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("FocusMate")
            .setContentText("Screen monitoring active")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .build()
}

// Static fields to hold projection data across service restarts within the same process
private var savedProjectionData: Intent? = null
private var savedResultCode: Int = 0
