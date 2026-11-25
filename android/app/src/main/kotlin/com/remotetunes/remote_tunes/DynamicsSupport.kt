package com.remotetunes.remote_tunes

import android.media.audiofx.DynamicsProcessing
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.sqrt

/**
 * A real multi-band equalizer: Android's DynamicsProcessing effect (Android 9
 * and newer) with one filter band per slider, at any frequencies, plus a
 * limiter that stops boosts from clipping, and one broadband compressor stage
 * (the multiband compressor used as a single band over the whole sound) that
 * evens out loud and quiet parts. It is attached to a player's audio session,
 * one per session (crossfade uses two players).
 *
 * Some phones do not allow it; then "set" returns false and the app falls back
 * to the phone's own (five band) equalizer.
 */
class DynamicsSupport(messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "remotetunes/dynamics")
    private val effects = HashMap<Int, Pair<DynamicsProcessing, Int>>() // session -> (effect, bands)

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        releaseAll()
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "supported" -> result.success(Build.VERSION_CODES.P <= Build.VERSION.SDK_INT)
            "set" -> {
                val session = call.argument<Int>("session") ?: 0
                val enabled = call.argument<Boolean>("enabled") ?: false
                val hz = call.argument<List<Double>>("hz") ?: emptyList()
                val gains = call.argument<List<Double>>("gains") ?: emptyList()
                val limiter = call.argument<Boolean>("limiter") ?: false
                val compressor = Compressor(
                    call.argument<Boolean>("compressor") ?: false,
                    (call.argument<Double>("threshold") ?: -24.0).toFloat(),
                    (call.argument<Double>("ratio") ?: 2.0).toFloat(),
                    (call.argument<Double>("attack") ?: 20.0).toFloat(),
                    (call.argument<Double>("release") ?: 250.0).toFloat(),
                    (call.argument<Double>("makeup") ?: 0.0).toFloat(),
                )
                result.success(set(session, enabled, hz, gains, limiter, compressor))
            }
            "release" -> {
                release(call.argument<Int>("session") ?: 0)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** The compressor's settings: on or off, level it starts at (dB), ratio, speeds (ms), and make-up gain (dB). */
    private data class Compressor(
        val on: Boolean,
        val thresholdDb: Float,
        val ratio: Float,
        val attackMs: Float,
        val releaseMs: Float,
        val makeupDb: Float,
    )

    private fun set(
        session: Int,
        enabled: Boolean,
        hz: List<Double>,
        gains: List<Double>,
        limiter: Boolean,
        compressor: Compressor,
    ): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return false
        if (session <= 0 || hz.isEmpty() || hz.size != gains.size) return false
        return try {
            var entry = effects[session]
            if (entry == null || entry.second != hz.size) {
                entry?.first?.release()
                val config = DynamicsProcessing.Config.Builder(
                    DynamicsProcessing.VARIANT_FAVOR_FREQUENCY_RESOLUTION,
                    2, // stereo
                    true, hz.size, // pre-EQ: our bands
                    true, 1, // multiband compressor: one band over the whole sound
                    false, 0, // no post-EQ
                    true, // limiter
                ).build()
                val dp = DynamicsProcessing(0, session, config)
                entry = Pair(dp, hz.size)
                effects[session] = entry
            }
            val dp = entry.first
            // The equalizer stage runs only when it is wanted (the compressor can run alone).
            dp.setPreEqAllChannelsTo(DynamicsProcessing.Eq(true, enabled, hz.size))
            dp.setMbcAllChannelsTo(DynamicsProcessing.Mbc(true, compressor.on, 1))
            dp.setMbcBandAllChannelsTo(
                0,
                DynamicsProcessing.MbcBand(
                    compressor.on,
                    20000f, // the one band covers everything
                    compressor.attackMs,
                    compressor.releaseMs,
                    compressor.ratio,
                    compressor.thresholdDb,
                    6f, // soft knee
                    -90f, // noise gate: off in effect
                    1f, // no expander
                    0f,
                    compressor.makeupDb,
                ),
            )
            for (i in hz.indices) {
                // A band runs up to the halfway point (on a log scale) to the next one.
                val edge = if (i == hz.size - 1) 20000.0 else sqrt(hz[i] * hz[i + 1])
                dp.setPreEqBandAllChannelsTo(
                    i,
                    DynamicsProcessing.EqBand(true, edge.toFloat(), gains[i].toFloat()),
                )
            }
            dp.setLimiterAllChannelsTo(
                DynamicsProcessing.Limiter(true, limiter, 0, 1f, 60f, 10f, -2f, 0f),
            )
            dp.enabled = enabled || compressor.on
            true
        } catch (e: Exception) {
            release(session)
            false
        }
    }

    private fun release(session: Int) {
        try {
            effects.remove(session)?.first?.release()
        } catch (_: Exception) {
        }
    }

    private fun releaseAll() {
        for (s in effects.keys.toList()) release(s)
    }
}
