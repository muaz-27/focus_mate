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

    // Screen metrics — set once on init
    private var screenWidth   = 0
    private var screenHeight  = 0
    private var screenDensity = 0
    private var isCaptureInProgress = false
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

        // Acquire a partial wake lock to prevent Samsung from dozing the service
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
                if (action == ACTION_START_AND_CAPTURE) captureOneFrame()
            }
            ACTION_CAPTURE -> {
                if (mediaProjection == null) {
                    android.util.Log.e("FocusMate", "CAPTURE: no MediaProjection")
                    Handler(Looper.getMainLooper()).post {
                        MainActivity.captureResult?.error("CAPTURE_FAILED", "Monitoring not active", null)
                        MainActivity.captureResult = null
                    }
                } else {
                    captureOneFrame()
                }
            }
        }
        return START_STICKY
    }

    private fun initProjection(intent: Intent) {
        val resultCode = intent.getIntExtra("resultCode", 0)
        val data       = intent.getParcelableExtra<Intent>("data")
        if (resultCode == 0 || data == null) return

        val pm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val mp = pm.getMediaProjection(resultCode, data) ?: return

        mp.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() {
                android.util.Log.d("FocusMate", "MediaProjection stopped externally")
                mediaProjection = null
                isRunning = false
                stopSelf()
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
    }

    /**
     * Creates a FRESH VirtualDisplay + ImageReader for EACH capture request.
     * This guarantees that Vivo delivers at least one frame (the initial render).
     * Both are released after the frame is grabbed — but MediaProjection stays alive.
     *
     * On Android 14 the key constraint is: never call mediaProjection.stop() or
     * registerCallback more than once. createVirtualDisplay can be called multiple times.
     */
    private fun captureOneFrame() {
        if (isCaptureInProgress) {
            android.util.Log.w("FocusMate", "captureOneFrame: already in progress")
            return
        }
        isCaptureInProgress = true

        val mp = mediaProjection
        if (mp == null) {
            android.util.Log.e("FocusMate", "captureOneFrame: no projection")
            isCaptureInProgress = false
            Handler(Looper.getMainLooper()).post {
                MainActivity.captureResult?.error("CAPTURE_FAILED", "No projection", null)
                MainActivity.captureResult = null
            }
            return
        }

        // Create fresh ImageReader + VirtualDisplay per capture
        val reader = ImageReader.newInstance(screenWidth, screenHeight, PixelFormat.RGBA_8888, 2)
        android.util.Log.d("FocusMate", "captureOneFrame: creating fresh VirtualDisplay")

        val display: VirtualDisplay?
        try {
            display = mp.createVirtualDisplay(
                "ScreenCapture",
                screenWidth, screenHeight, screenDensity,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                reader.surface, null, backgroundHandler
            )
        } catch (e: Exception) {
            android.util.Log.e("FocusMate", "createVirtualDisplay exception: ${e.message}")
            reader.close()
            isCaptureInProgress = false
            Handler(Looper.getMainLooper()).post {
                MainActivity.captureResult?.error("CAPTURE_FAILED", "VirtualDisplay error: ${e.message}", null)
                MainActivity.captureResult = null
            }
            return
        }

        if (display == null) {
            android.util.Log.e("FocusMate", "createVirtualDisplay returned null")
            reader.close()
            isCaptureInProgress = false
            Handler(Looper.getMainLooper()).post {
                MainActivity.captureResult?.error("CAPTURE_FAILED", "Null VirtualDisplay", null)
                MainActivity.captureResult = null
            }
            return
        }

        android.util.Log.d("FocusMate", "captureOneFrame: VirtualDisplay created, waiting for frame (5s timeout)")

        // 5-second timeout in case Vivo still throttles
        val timeoutRunnable = Runnable {
            if (isCaptureInProgress) {
                android.util.Log.e("FocusMate", "captureOneFrame: TIMEOUT 5s")
                isCaptureInProgress = false
                reader.setOnImageAvailableListener(null, null)
                try { display.release() } catch (_: Exception) {}
                try { reader.close() } catch (_: Exception) {}
                Handler(Looper.getMainLooper()).post {
                    MainActivity.captureResult?.error("CAPTURE_FAILED", "Timeout: no frame", null)
                    MainActivity.captureResult = null
                }
            }
        }
        backgroundHandler?.postDelayed(timeoutRunnable, 5000)

        reader.setOnImageAvailableListener({ imgReader ->
            backgroundHandler?.removeCallbacks(timeoutRunnable)
            imgReader.setOnImageAvailableListener(null, null)
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
                    val bytes = out.toByteArray()

                    android.util.Log.d("FocusMate", "captureOneFrame: SUCCESS ${bytes.size} bytes")
                    Handler(Looper.getMainLooper()).post {
                        MainActivity.captureResult?.success(bytes)
                        MainActivity.captureResult = null
                    }
                    bmp.recycle()
                    cropped.recycle()
                } catch (e: Exception) {
                    android.util.Log.e("FocusMate", "captureOneFrame exception: ${e.message}")
                    Handler(Looper.getMainLooper()).post {
                        MainActivity.captureResult?.error("CAPTURE_FAILED", e.message, null)
                        MainActivity.captureResult = null
                    }
                } finally {
                    image.close()
                    try { display.release() } catch (_: Exception) {}
                    try { reader.close() } catch (_: Exception) {}
                    isCaptureInProgress = false
                }
            } else {
                android.util.Log.e("FocusMate", "captureOneFrame: null image")
                isCaptureInProgress = false
                try { display.release() } catch (_: Exception) {}
                try { reader.close() } catch (_: Exception) {}
                Handler(Looper.getMainLooper()).post {
                    MainActivity.captureResult?.error("CAPTURE_FAILED", "Null image", null)
                    MainActivity.captureResult = null
                }
            }
        }, backgroundHandler)
    }

    override fun onDestroy() {
        android.util.Log.d("FocusMate", "SnapshotService.onDestroy")
        isRunning = false
        handlerThread?.quitSafely()
        try { mediaProjection?.stop() } catch (_: Exception) {}
        try { wakeLock?.release() } catch (_: Exception) {}
        wakeLock = null
        stopForeground(true)
        super.onDestroy()
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
