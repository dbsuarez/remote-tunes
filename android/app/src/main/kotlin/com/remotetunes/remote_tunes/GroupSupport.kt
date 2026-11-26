package com.remotetunes.remote_tunes

import android.app.Activity
import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.net.wifi.WifiManager
import android.os.Build
import android.os.PowerManager
import android.view.WindowManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Helpers for group play (two phones playing the same song in sync).
 *
 *  - [setLocks]: while on, the CPU stays awake, the Wi-Fi radio is kept in a
 *    fast mode (power saving adds jittery delay, which hurts the clock
 *    measurements) and, if asked, the screen stays on. Released when off.
 *  - [outputRoute]: where the sound goes (speaker, wired, Bluetooth, ...).
 *    Bluetooth adds a large and variable delay that breaks sync.
 *  - [outputLatencyMs]: the phone's own estimate of its audio output delay,
 *    when it will tell (a hidden Android call; null if not available).
 *
 * Nothing here reads or sends any personal data.
 */
class GroupSupport(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "remotetunes/group")
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "setLocks" -> {
                    setLocks(
                        call.argument<Boolean>("enabled") == true,
                        call.argument<Boolean>("keepScreenOn") == true,
                    )
                    result.success(null)
                }
                "keepScreenOn" -> {
                    // Just the screen flag (for long jobs such as adding music).
                    val on = call.argument<Boolean>("on") == true
                    activity.runOnUiThread {
                        if (on) {
                            activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                    }
                    result.success(null)
                }
                "brightness" -> {
                    // This window only; -1 is the phone's usual brightness.
                    val level = (call.argument<Double>("level") ?: -1.0).toFloat()
                    activity.runOnUiThread {
                        val params = activity.window.attributes
                        params.screenBrightness = level
                        activity.window.attributes = params
                    }
                    result.success(null)
                }
                "outputRoute" -> result.success(outputRoute())
                "outputLatencyMs" -> result.success(outputLatencyMs())
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("group_native", e.message, null)
        }
    }

    private fun setLocks(enabled: Boolean, keepScreenOn: Boolean) {
        if (enabled) {
            if (wakeLock == null) {
                val pm = activity.getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = pm.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    "RemoteTunes:group",
                ).apply { setReferenceCounted(false) }
            }
            // A safety limit: released by itself after 6 hours.
            wakeLock?.acquire(6 * 60 * 60 * 1000L)

            if (wifiLock == null) {
                val wm = activity.applicationContext
                    .getSystemService(Context.WIFI_SERVICE) as WifiManager
                @Suppress("DEPRECATION")
                val mode = if (Build.VERSION.SDK_INT >= 29)
                    WifiManager.WIFI_MODE_FULL_LOW_LATENCY
                else
                    WifiManager.WIFI_MODE_FULL_HIGH_PERF
                wifiLock = wm.createWifiLock(mode, "RemoteTunes:group").apply {
                    setReferenceCounted(false)
                }
            }
            if (wifiLock?.isHeld != true) wifiLock?.acquire()
        } else {
            if (wakeLock?.isHeld == true) wakeLock?.release()
            if (wifiLock?.isHeld == true) wifiLock?.release()
        }
        activity.runOnUiThread {
            if (enabled && keepScreenOn) {
                activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            } else {
                activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
        }
    }

    private fun outputRoute(): String {
        val am = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val devices = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        var wired = false
        for (d in devices) {
            when (d.type) {
                AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
                AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> return "bluetooth"
                AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
                AudioDeviceInfo.TYPE_WIRED_HEADSET,
                AudioDeviceInfo.TYPE_USB_HEADSET,
                AudioDeviceInfo.TYPE_USB_DEVICE -> wired = true
                else -> {
                    // Newer Bluetooth types exist on Android 12+.
                    if (Build.VERSION.SDK_INT >= 31 &&
                        (d.type == AudioDeviceInfo.TYPE_BLE_HEADSET ||
                            d.type == AudioDeviceInfo.TYPE_BLE_SPEAKER ||
                            d.type == AudioDeviceInfo.TYPE_BLE_BROADCAST)
                    ) return "bluetooth"
                }
            }
        }
        return if (wired) "wired" else "speaker"
    }

    private fun outputLatencyMs(): Int? {
        return try {
            val am = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val m = AudioManager::class.java.getMethod("getOutputLatency", Int::class.javaPrimitiveType)
            val v = m.invoke(am, AudioManager.STREAM_MUSIC) as Int
            if (v in 1..2000) v else null
        } catch (e: Throwable) {
            null // a hidden call: not every phone allows it
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        try {
            setLocks(false, false)
        } catch (_: Exception) {
        }
    }
}
