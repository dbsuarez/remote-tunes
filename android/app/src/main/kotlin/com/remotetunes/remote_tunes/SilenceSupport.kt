package com.remotetunes.remote_tunes

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteOrder
import java.util.concurrent.Executors
import kotlin.math.abs

/**
 * Finds where the sound of a song really stops, so a long silent tail can be skipped. Only the end of
 * the file is decoded. Nothing is changed or sent anywhere.
 */
class SilenceSupport(messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "remotetunes/silence")
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    init {
        channel.setMethodCallHandler { call, result ->
            val path = call.argument<String>("path")
            if (call.method != "soundEnd" || path == null) {
                result.notImplemented()
                return@setMethodCallHandler
            }
            worker.execute {
                val found = try {
                    soundEnd(path)
                } catch (_: Exception) {
                    null // A file that cannot be read this way simply plays to its end.
                }
                main.post { result.success(found) }
            }
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        worker.shutdown()
    }

    /** {"end": ms, "duration": ms}, or null if it cannot be told. */
    private fun soundEnd(path: String): Map<String, Long>? {
        // The last minute first; a song with an even longer silence is looked at further back.
        for (window in longArrayOf(60_000_000L, 600_000_000L)) {
            val extractor = MediaExtractor()
            try {
                extractor.setDataSource(path)
                val track = (0 until extractor.trackCount).firstOrNull {
                    extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
                } ?: return null
                val format = extractor.getTrackFormat(track)
                if (!format.containsKey(MediaFormat.KEY_DURATION)) return null
                val duration = format.getLong(MediaFormat.KEY_DURATION)
                extractor.selectTrack(track)
                val from = maxOf(0L, duration - window)
                extractor.seekTo(from, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
                val last = lastSound(extractor, format)
                if (last != null) return mapOf("end" to last / 1000, "duration" to duration / 1000)
                if (from == 0L) return null
            } finally {
                extractor.release()
            }
        }
        return null
    }

    /** The time (µs) of the last sample louder than about -50 dB, or null if none or on trouble. */
    private fun lastSound(extractor: MediaExtractor, format: MediaFormat): Long? {
        val codec = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
        try {
            codec.configure(format, null, null, 0)
            codec.start()
            val info = MediaCodec.BufferInfo()
            var rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            var floats = false
            var inputDone = false
            var last: Long? = null
            val deadline = SystemClock.elapsedRealtime() + 20_000
            while (SystemClock.elapsedRealtime() < deadline) {
                if (!inputDone) {
                    val i = codec.dequeueInputBuffer(5_000)
                    if (i >= 0) {
                        val size = extractor.readSampleData(codec.getInputBuffer(i)!!, 0)
                        if (size < 0) {
                            codec.queueInputBuffer(i, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            codec.queueInputBuffer(i, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
                val o = codec.dequeueOutputBuffer(info, 5_000)
                if (o == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val out = codec.outputFormat
                    rate = out.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    channels = out.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    floats = out.containsKey(MediaFormat.KEY_PCM_ENCODING) &&
                        out.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_FLOAT
                } else if (o >= 0) {
                    if (info.size > 0) {
                        val buffer = codec.getOutputBuffer(o)!!.order(ByteOrder.nativeOrder())
                        buffer.position(info.offset)
                        buffer.limit(info.offset + info.size)
                        var index = -1
                        if (floats) {
                            val samples = buffer.asFloatBuffer()
                            for (n in samples.limit() - 1 downTo 0) {
                                if (abs(samples.get(n)) > 0.0032f) { index = n; break }
                            }
                        } else {
                            val samples = buffer.asShortBuffer()
                            for (n in samples.limit() - 1 downTo 0) {
                                if (abs(samples.get(n).toInt()) > 104) { index = n; break }
                            }
                        }
                        if (index >= 0) {
                            last = info.presentationTimeUs + (index / channels) * 1_000_000L / rate
                        }
                    }
                    codec.releaseOutputBuffer(o, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return last
                }
            }
            return null // Took too long: better not to guess.
        } finally {
            codec.release()
        }
    }
}
