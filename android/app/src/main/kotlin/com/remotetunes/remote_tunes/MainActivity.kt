package com.remotetunes.remote_tunes

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : AudioServiceActivity() {
    private var externalMedia: ExternalMediaBridge? = null
    private var groupSupport: GroupSupport? = null
    private var updateSupport: UpdateSupport? = null

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
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        externalMedia?.dispose()
        externalMedia = null
        groupSupport?.dispose()
        groupSupport = null
        updateSupport?.dispose()
        updateSupport = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
