package com.musik.musik_app

import android.content.Context
import android.net.wifi.WifiManager
import android.os.Build
import android.os.PowerManager

/**
 * Screen-off Wi-Fi power save drops ExoPlayer's HTTP buffer. just_audio 0.10
 * does not call ExoPlayer.setWakeMode(WAKE_MODE_NETWORK), and audio_service
 * only holds a CPU wake lock. This keeps the radio up while audio is playing.
 */
class PlaybackNetworkLock(context: Context) {
    private val appContext = context.applicationContext

    private val wakeLock: PowerManager.WakeLock =
        (appContext.getSystemService(Context.POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "musik:playback")
            .apply { setReferenceCounted(false) }

    private val wifiLock: WifiManager.WifiLock = run {
        val wifi = appContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            WifiManager.WIFI_MODE_FULL_LOW_LATENCY
        } else {
            @Suppress("DEPRECATION")
            WifiManager.WIFI_MODE_FULL_HIGH_PERF
        }
        wifi.createWifiLock(mode, "musik:playback").apply { setReferenceCounted(false) }
    }

    fun acquire() {
        if (!wakeLock.isHeld) {
            wakeLock.acquire()
        }
        if (!wifiLock.isHeld) {
            wifiLock.acquire()
        }
    }

    fun release() {
        if (wifiLock.isHeld) {
            wifiLock.release()
        }
        if (wakeLock.isHeld) {
            wakeLock.release()
        }
    }
}
