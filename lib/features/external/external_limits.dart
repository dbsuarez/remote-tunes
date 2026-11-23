/// What controlling another music app can and cannot do. Shown on both phones:
/// the spec says never to promise full control (docs/13, FR-80, FR-82).
const String externalLimitsText =
    'Basic controls only: play, pause, next, previous, seek and volume. Which '
    'ones work depends on the other app: ads, radio and podcasts often block '
    'skipping or seeking. You cannot pick songs, use the queue or the library, '
    'or play links while controlling another app. Control stops if the other '
    'app is closed or Android shuts it down to save battery. Not every app is '
    'supported, and Spotify and YouTube Music can change how they behave in '
    'updates.';

/// Explained before the user can turn External App Control on.
const String externalConsentText =
    'To control other music apps, Android requires you to allow RemoteTunes '
    '"Notification access".\n\n'
    'RemoteTunes uses it only to see which music app is playing (its name, '
    'title and artist) and to press play, pause, next and previous. It does '
    'not read your notifications or messages, stores nothing, and sends only '
    "that playback information to the Controller you paired with.\n\n"
    'You will allow it in Android\'s settings the first time you switch the '
    'Player to another app, and you can turn it off there or here at any time.';
