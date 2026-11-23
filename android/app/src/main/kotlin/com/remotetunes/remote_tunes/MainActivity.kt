package com.remotetunes.remote_tunes

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : AudioServiceActivity() {
    private var externalMedia: ExternalMediaBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Phase 5: control of other music apps (see ExternalMediaBridge).
        externalMedia = ExternalMediaBridge(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        externalMedia?.dispose()
        externalMedia = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
