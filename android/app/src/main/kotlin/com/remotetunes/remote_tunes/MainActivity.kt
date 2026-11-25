package com.remotetunes.remote_tunes

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : AudioServiceActivity() {
    private var externalMedia: ExternalMediaBridge? = null
    private var groupSupport: GroupSupport? = null
    private var updateSupport: UpdateSupport? = null
    private var visualizerSupport: VisualizerSupport? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createMediaChannel()
    }

    /**
     * The playback notification's channel. Made here (not by the audio library)
     * so it can have normal importance with no sound or vibration: a "low"
     * channel is hidden from the lock screen on some phones.
     */
    private fun createMediaChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(MEDIA_CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            MEDIA_CHANNEL_ID,
            "RemoteTunes playback",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            setSound(null, null)
            enableVibration(false)
            enableLights(false)
            setShowBadge(false)
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
    }

    companion object {
        const val MEDIA_CHANNEL_ID = "com.remotetunes.remote_tunes.media"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Phase 5: control of other music apps (see ExternalMediaBridge).
        externalMedia = ExternalMediaBridge(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        )
        // Phase 9: keep-awake / Wi-Fi mode / output route for group play.
        groupSupport = GroupSupport(this, flutterEngine.dartExecutor.binaryMessenger)
        // Self-update from GitHub Releases.
        updateSupport = UpdateSupport(this, flutterEngine.dartExecutor.binaryMessenger)
        visualizerSupport = VisualizerSupport(flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        externalMedia?.dispose()
        externalMedia = null
        groupSupport?.dispose()
        groupSupport = null
        updateSupport?.dispose()
        updateSupport = null
        visualizerSupport?.dispose()
        visualizerSupport = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
