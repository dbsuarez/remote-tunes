package com.remotetunes.remote_tunes

import android.service.notification.NotificationListenerService

/**
 * An empty notification listener.
 *
 * Android only lets an app look at other apps' media sessions (to control
 * Spotify, YouTube Music, ...) if the user has granted it "Notification access".
 * This service is the component that grant applies to.
 *
 * It deliberately does NOT override onNotificationPosted / onNotificationRemoved:
 * RemoteTunes never reads notification contents. It only uses the access to ask
 * Android which media sessions are active (see ExternalMediaBridge).
 */
class MediaListenerService : NotificationListenerService()
