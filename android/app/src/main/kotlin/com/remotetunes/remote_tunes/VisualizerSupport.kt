package com.remotetunes.remote_tunes

import android.media.audiofx.Visualizer
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.hypot
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

/**
 * Reads the sound the app is playing as a spectrum (a handful of bars) for the
 * visualizer. Nothing is recorded or kept: Android's Visualizer only hands over
 * the loudness of each frequency range, and it needs the microphone permission
 * for that.
 */
class VisualizerSupport(messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "remotetunes/visualizer")
    private val main = Handler(Looper.getMainLooper())
    private var visualizer: Visualizer? = null

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        stop()
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                val session = call.argument<Int>("session") ?: 0
                val bars = (call.argument<Int>("bars") ?: 24).coerceIn(4, 64)
                result.success(start(session, bars))
            }
            "stop" -> {
                stop()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun start(session: Int, bars: Int): Boolean {
        stop()
        return try {
            val v = Visualizer(session)
            v.enabled = false
            v.captureSize = min(1024, Visualizer.getCaptureSizeRange()[1])
            v.setDataCaptureListener(
                object : Visualizer.OnDataCaptureListener {
                    override fun onWaveFormDataCapture(vis: Visualizer?, data: ByteArray?, rate: Int) {}

                    override fun onFftDataCapture(vis: Visualizer?, fft: ByteArray?, rate: Int) {
                        if (fft == null) return
                        val out = spectrum(fft, bars)
                        main.post { channel.invokeMethod("bars", out) }
                    }
                },
                min(Visualizer.getMaxCaptureRate() / 2, 20000),
                false,
                true,
            )
            v.enabled = true
            visualizer = v
            true
        } catch (e: Exception) {
            // No permission, or this phone does not allow it for this sound.
            stop()
            false
        }
    }

    private fun stop() {
        try {
            visualizer?.enabled = false
            visualizer?.release()
        } catch (_: Exception) {
        }
        visualizer = null
    }

    /** [bars] numbers from 0 to 1, low frequencies first, spaced like hearing is. */
    private fun spectrum(fft: ByteArray, bars: Int): List<Double> {
        val bins = fft.size / 2 // bin k: real at 2k, imaginary at 2k + 1 (bin 0 is DC)
        val out = ArrayList<Double>(bars)
        val first = 1.0
        val last = (bins - 1).toDouble()
        for (b in 0 until bars) {
            val from = first * (last / first).pow(b.toDouble() / bars)
            val to = first * (last / first).pow((b + 1).toDouble() / bars)
            val lo = from.toInt().coerceIn(1, bins - 1)
            val hi = max(lo, to.toInt()).coerceIn(1, bins - 1)
            var peak = 0.0
            for (k in lo..hi) {
                val re = fft[2 * k].toDouble()
                val im = fft[2 * k + 1].toDouble()
                peak = max(peak, hypot(re, im))
            }
            // Loudness on a log scale so quiet detail is visible.
            val level = if (peak <= 1) 0.0 else (ln(peak) / ln(181.0))
            out.add(level.coerceIn(0.0, 1.0))
        }
        return out
    }
}
