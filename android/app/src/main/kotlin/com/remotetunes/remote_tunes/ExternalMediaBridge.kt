package com.remotetunes.remote_tunes

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

/**
 * Lets Dart see and control the media session of another music app (Spotify,
 * YouTube Music, ...) on this phone. Used by "External App Control".
 *
 * Needs the user to grant Notification access to [MediaListenerService]. It only
 * reads media sessions (which app, title, artist, play state): never
 * notification text. Nothing here is stored or sent anywhere except back to
 * Dart on this phone.
 *
 * All calls run on the main thread.
 */
class ExternalMediaBridge(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val main = Handler(Looper.getMainLooper())
    private val sessionManager =
        context.getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val listener = ComponentName(context, MediaListenerService::class.java)

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private var sink: EventChannel.EventSink? = null

    private var running = false
    private var selectedPackage: String? = null
    private val controllers = LinkedHashMap<String, MediaController>()
    private val callbacks = HashMap<String, MediaController.Callback>()

    private val sessionsChanged =
        MediaSessionManager.OnActiveSessionsChangedListener { list ->
            onSessions(list ?: emptyList())
        }

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    fun dispose() {
        stopListening()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    // ------------------------------------------------------------ channels

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "sdkInt" -> result.success(Build.VERSION.SDK_INT)
                "isAccessGranted" -> result.success(accessGranted())
                "openAccessSettings" -> {
                    openAccessSettings()
                    result.success(null)
                }
                "openAppInfo" -> {
                    openAppInfo()
                    result.success(null)
                }
                "start" -> {
                    startListening()
                    result.success(snapshot())
                }
                "stop" -> {
                    stopListening()
                    result.success(null)
                }
                "selectSession" -> {
                    selectedPackage = call.argument<String>("package")
                    emit()
                    result.success(null)
                }
                "play" -> control(result) { it.transportControls.play() }
                "pause" -> control(result) { it.transportControls.pause() }
                "next" -> control(result) { it.transportControls.skipToNext() }
                "previous" -> control(result) { it.transportControls.skipToPrevious() }
                "seekTo" -> {
                    val ms = (call.argument<Number>("positionMs") ?: 0).toLong()
                    control(result) { it.transportControls.seekTo(ms) }
                }
                "setVolume" -> {
                    val v = (call.argument<Number>("volume") ?: 0.0).toDouble()
                    val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                    audio.setStreamVolume(
                        AudioManager.STREAM_MUSIC,
                        (v.coerceIn(0.0, 1.0) * max).roundToInt(),
                        0,
                    )
                    emit()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: SecurityException) {
            result.error("NO_ACCESS", "Notification access is not allowed.", null)
        } catch (e: Exception) {
            result.error("FAILED", e.message ?: "Something went wrong.", null)
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        emit()
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    // ------------------------------------------------------------- access

    /** True if the user has granted Notification access to this app. */
    private fun accessGranted(): Boolean {
        val flat = Settings.Secure.getString(
            context.contentResolver,
            "enabled_notification_listeners",
        ) ?: return false
        return flat.split(":").any {
            ComponentName.unflattenFromString(it)?.packageName == context.packageName
        }
    }

    private fun openAccessSettings() {
        val intent =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS).putExtra(
                    Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME,
                    listener.flattenToString(),
                )
            } else {
                Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
            }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            context.startActivity(intent)
        } catch (e: Exception) {
            // Some phones lack the detail screen: fall back to the general list.
            context.startActivity(
                Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        }
    }

    /** App info page, where Android 13+ offers "Allow restricted settings". */
    private fun openAppInfo() {
        context.startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.parse("package:${context.packageName}"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    }

    // ------------------------------------------------------------ sessions

    private fun startListening() {
        if (running) {
            refresh()
            return
        }
        if (!accessGranted()) return
        try {
            sessionManager.addOnActiveSessionsChangedListener(sessionsChanged, listener, main)
            running = true
            refresh()
        } catch (e: SecurityException) {
            running = false
        }
    }

    private fun stopListening() {
        if (running) {
            try {
                sessionManager.removeOnActiveSessionsChangedListener(sessionsChanged)
            } catch (e: Exception) {
                // already gone
            }
        }
        running = false
        for ((pkg, cb) in callbacks) {
            controllers[pkg]?.unregisterCallback(cb)
        }
        callbacks.clear()
        controllers.clear()
    }

    private fun refresh() {
        try {
            onSessions(sessionManager.getActiveSessions(listener))
        } catch (e: SecurityException) {
            running = false
            emit()
        }
    }

    private fun onSessions(list: List<MediaController>) {
        // RemoteTunes' own session must never be controlled by itself.
        val wanted = list.filter { it.packageName != context.packageName }
        val wantedPackages = wanted.map { it.packageName }.toSet()

        for (pkg in controllers.keys.toList()) {
            if (pkg !in wantedPackages) {
                callbacks.remove(pkg)?.let { controllers[pkg]?.unregisterCallback(it) }
                controllers.remove(pkg)
            }
        }
        for (c in wanted) {
            if (!controllers.containsKey(c.packageName)) {
                val cb = object : MediaController.Callback() {
                    override fun onPlaybackStateChanged(state: PlaybackState?) = emit()
                    override fun onMetadataChanged(metadata: MediaMetadata?) = emit()
                    override fun onSessionDestroyed() {
                        main.post { refresh() }
                    }
                }
                c.registerCallback(cb, main)
                callbacks[c.packageName] = cb
            }
            controllers[c.packageName] = c
        }
        emit()
    }

    /** The session to show/control: the user's pick, else one that is playing. */
    private fun current(): MediaController? {
        val all = controllers.values.toList()
        selectedPackage?.let { p -> all.firstOrNull { it.packageName == p }?.let { return it } }
        return all.firstOrNull { isPlaying(it) }
            ?: all.firstOrNull { it.metadata != null }
            ?: all.firstOrNull()
    }

    private fun isPlaying(c: MediaController) =
        c.playbackState?.state == PlaybackState.STATE_PLAYING

    private fun control(result: MethodChannel.Result, action: (MediaController) -> Unit) {
        val c = current()
        if (c == null) {
            result.error("NO_SESSION", "No music app is playing on this phone.", null)
            return
        }
        action(c)
        result.success(null)
    }

    // ------------------------------------------------------------ snapshot

    private fun label(pkg: String): String =
        try {
            val pm = context.packageManager
            pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
        } catch (e: Exception) {
            pkg
        }

    private fun sessionMap(c: MediaController): Map<String, Any?> = mapOf(
        "package" to c.packageName,
        "label" to label(c.packageName),
        "isPlaying" to isPlaying(c),
        "title" to c.metadata?.getString(MediaMetadata.METADATA_KEY_TITLE),
    )

    private fun trackMap(c: MediaController): Map<String, Any?> {
        val m = c.metadata
        val st = c.playbackState
        val duration = m?.getLong(MediaMetadata.METADATA_KEY_DURATION) ?: 0L
        var position = st?.position ?: 0L
        if (st != null && st.state == PlaybackState.STATE_PLAYING) {
            val elapsed = SystemClock.elapsedRealtime() - st.lastPositionUpdateTime
            position += (elapsed * st.playbackSpeed).toLong()
        }
        if (duration > 0) position = position.coerceIn(0L, duration) else position = position.coerceAtLeast(0L)
        val actions = st?.actions ?: 0L
        fun can(a: Long) = (actions and a) != 0L
        return mapOf(
            "package" to c.packageName,
            "label" to label(c.packageName),
            "title" to (m?.getString(MediaMetadata.METADATA_KEY_TITLE)
                ?: m?.getString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE)),
            "artist" to (m?.getString(MediaMetadata.METADATA_KEY_ARTIST)
                ?: m?.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST)
                ?: m?.getString(MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE)),
            "album" to m?.getString(MediaMetadata.METADATA_KEY_ALBUM),
            "durationMs" to duration,
            "positionMs" to position,
            "isPlaying" to (st?.state == PlaybackState.STATE_PLAYING),
            "isBuffering" to (st?.state == PlaybackState.STATE_BUFFERING),
            "canSeek" to can(PlaybackState.ACTION_SEEK_TO),
            "canNext" to can(PlaybackState.ACTION_SKIP_TO_NEXT),
            "canPrevious" to can(PlaybackState.ACTION_SKIP_TO_PREVIOUS),
        )
    }

    private fun snapshot(): Map<String, Any?> {
        val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
        val now = audio.getStreamVolume(AudioManager.STREAM_MUSIC)
        val cur = if (running) current() else null
        return mapOf(
            "accessGranted" to accessGranted(),
            "sessions" to controllers.values.map { sessionMap(it) },
            "current" to cur?.let { trackMap(it) },
            "volume" to now.toDouble() / max,
        )
    }

    private fun emit() {
        sink?.success(snapshot())
    }

    companion object {
        const val METHOD_CHANNEL = "remotetunes/external_media"
        const val EVENT_CHANNEL = "remotetunes/external_media/events"
    }
}
