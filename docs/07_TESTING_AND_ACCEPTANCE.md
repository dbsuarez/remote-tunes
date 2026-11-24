# RemoteTunes — Testing and Acceptance (v2)

Test both Infinix phones in both roles.

## Networks
- Same Wi‑Fi: local works.
- Hotspot: local works.
- Airplane+hotspot: local works.
- Different Wi‑Fi: online relay works.
- Mobile data both: online relay works.
- Internet available: URL playback works.
- Internet unavailable: local MP3 works.

## Phase acceptance
### Phase 0
- App builds/runs both phones.
- Dark Material 3.
- Drift initializes.
- Settings persist.
- Connection mode selector exists.
- No cloud required for local.

### Phase 1 Local control
- WebSocket server.
- mDNS/NSD discovery.
- Manual IP/port.
- Pairing.
- Token required.
- Play/pause/toggle/next/previous/seek/volume.
- State sync.
- Works offline/hotspot.

### Phase 2 Local player
- MP3 import.
- Folder import.
- Library.
- Queue.
- Background playback.
- Notification controls.

### Phase 3 URL playback
- URL plays.
- Errors handled.
- Recent URLs local.

### Phase 4 Online remote control
- Supabase Realtime relay.
- Online pairing.
- Online commands.
- Online state.
- Works across networks/mobile data.
- Local still works offline.

### Phase 5 External apps
- External mode.
- Notification Listener.
- Basic transport where supported.

### Phase 6 Web Controller
See the acceptance criteria in docs/17_WEB_CONTROLLER.md.

### Phase 8 Online Library
See the acceptance criteria in docs/18_PHASE_8_ONLINE_LIBRARY.md.

### Phase 7 Polish
- Album art, playlists, favorites, search, sleep timer, speed, diagnostics.
