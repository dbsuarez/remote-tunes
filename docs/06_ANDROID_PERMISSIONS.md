# RemoteTunes — Android Permissions (v2)

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.CAMERA" />        <!-- QR scanning -->
<uses-permission android:name="android.permission.RECORD_AUDIO" />  <!-- group play, Auto-align: listens for ~15 s, nothing saved or sent -->
<uses-permission android:name="android.permission.NEARBY_WIFI_DEVICES" android:usesPermissionFlags="neverForLocation" />
```

Inside application:
```xml
<service android:name="com.ryanheise.audioservice.AudioService" android:foregroundServiceType="mediaPlayback" android:exported="true">
  <intent-filter><action android:name="android.media.browse.MediaBrowserService" /></intent-filter>
</service>
<receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver" android:exported="true">
  <intent-filter><action android:name="android.intent.action.MEDIA_BUTTON" /></intent-filter>
</receiver>
```

Group play (docs/16) takes a partial wake lock and a high-performance Wi-Fi lock while it runs (`GroupSupport.kt`) and keeps the screen on on the phone that plays along; all are released when it ends. RECORD_AUDIO is asked only when the user taps Auto-align.

Use file_picker/SAF for local files. Notification Listener only for External App Control. Battery optimization guidance for Infinix.
