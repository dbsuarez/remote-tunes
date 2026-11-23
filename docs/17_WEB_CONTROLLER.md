# RemoteTunes — Web Controller Specification

## Status

**Planned future phase.**  
**Do not implement during Phase 1.**

This feature becomes relevant after Phase 4 — Online Remote Control — is complete and stable.

RemoteTunes remains offline-first. Local Android-to-Android control must continue to work without internet. The web Controller is an optional online feature.

## 1. Objective

Add a web-based Controller so RemoteTunes can be controlled from a PC, tablet, or phone browser.

The web app is a **Controller only**. It does not replace the Android Player.

```text
Web Controller (browser)
        |
        v
Supabase Realtime relay
        |
        v
Android Player phone
```

The Android Player remains the only full Player in v1.

## 2. Product rules

- RemoteTunes is offline-first, not offline-only.
- Local Android-to-Android control must continue to work without internet.
- The web Controller requires internet because it uses Supabase Realtime.
- The web Controller is optional.
- The web Controller must not make online mode mandatory.
- The web Controller must not store or upload music files.
- The web Controller must not require a user account in v1.
- The Android Player remains the only full Player in v1.
- The web Controller must use the same JSON protocol, pairing flow, session-token model, and error codes as the Android app.

## 3. Web Controller capabilities

The web Controller may:

- Connect to an Android Player through a Supabase Realtime room.
- Pair using the same six-digit code and session-token model.
- Send the same JSON commands as the Android Controller.
- Receive the same playback-state updates.
- Control playback: play, pause, toggle, next, previous, seek, volume.
- View current track, artist, album, position, duration, and playing state.
- View and manage the Player queue.
- Browse and search the Player local library.
- Add songs to the queue.
- Send direct online audio URLs to the Player.
- View connection status: disconnected, connecting, pairing, connected, reconnecting, or error.
- Disconnect from the Player.

The web Controller must not:

- Play local MP3 files from the Android Player.
- Act as the Player.
- Store music files.
- Upload listening history or telemetry.
- Bypass pairing or session-token security.
- Receive local file paths from the Player.

## 4. Recommended transport

Use **Supabase Realtime** as the primary web Controller transport.

Reason:

- Works across different Wi‑Fi networks.
- Works over mobile data.
- Avoids browser local-network and mixed-content limitations.
- Uses the same JSON message protocol as the Android app.
- Allows a browser-based Controller and Android Player to communicate without a custom server.

Supabase Realtime Broadcast supports low-latency messaging between connected clients through channels.

### Local WebSocket option

A web Controller may later connect directly to the Player’s local WebSocket server when both devices are on the same local network.

However, browser security can complicate direct `ws://` connections, especially if the web app is served over HTTPS.

For v1 of the web Controller:

- Use Supabase Realtime only.
- Do not implement local WebSocket from web.
- Revisit direct local WebSocket later if needed.

## 5. Web app role

The web app has one role:

```text
Web Controller
```

It does not need a Player mode.

The Android app retains both roles:

```text
Controller
Player
```

## 6. Connection flow

1. User opens the web Controller.
2. User enters the Player’s room code.
3. Web Controller joins the Supabase Realtime channel.
4. Web Controller sends a pairing request.
5. Android Player shows the pairing request and six-digit code.
6. User enters the code in the web Controller.
7. Player validates the code.
8. Player issues a session token.
9. Web Controller stores the token locally in browser storage.
10. Web Controller can send commands.

## 7. Security rules

- Pairing is required before commands are accepted.
- Session token is required for every command.
- Room codes must be random and short-lived.
- Do not store music files in Supabase.
- Do not upload listening history or telemetry.
- Do not expose local file paths from the Player to the web Controller.
- Use the same JSON protocol and error codes as the Android app.
- The web Controller must reject commands without a valid session token.

## 8. Web UI

Use the same RemoteTunes visual identity and UX guardrails defined in `15_UX_DESIGN_GUARDRAILS.md`.

Do not copy Spotify’s exact visual identity, logo, color palette, icons, artwork, typography, screen layouts, or branding.

### Web Home

```text
RemoteTunes Web

[ Room code field ]
[ Connect to Player ]

Connection status:
[ Disconnected / Connecting / Paired ]

Recent rooms
- 482913
- 736204
```

### Web Controller dashboard

```text
Connected to: GT 30 Pro
Connection: Online

Now Playing
Example Song
Example Artist

[ Previous ] [ Play/Pause ] [ Next ]

Seek bar
0:42 ------------------ 3:30

Volume
[ speaker ] ------------------ [ speaker ]

Tabs:
[ Now Playing ] [ Queue ] [ Library ] [ URL ]
```

## 9. Flutter web support

Add web support to the existing Flutter project only when this phase begins:

```bash
flutter create . --platforms web
```

Run during development:

```bash
flutter run -d chrome
```

Build for production:

```bash
flutter build web
```

Flutter supports building the same Dart codebase for web, and web support can be added to an existing Flutter project.

## 10. Implementation tasks

When this phase begins:

1. Add web platform support to the Flutter project.
2. Create a web Controller entry point.
3. Reuse the existing RemoteTransport abstraction.
4. Implement SupabaseRealtimeTransport for web.
5. Implement web pairing flow.
6. Implement web Controller dashboard.
7. Implement now-playing state subscription.
8. Implement playback commands.
9. Implement queue commands.
10. Implement library request/response.
11. Implement URL playback command.
12. Add connection-status UI.
13. Add reconnect handling.
14. Test web Controller to Android Player across different networks.

## 11. Acceptance criteria

- [x] Web Controller can connect to Android Player through Supabase Realtime.
- [x] Web Controller can complete pairing.
- [x] Web Controller can send play, pause, toggle, next, previous, seek, and volume commands.
- [x] Web Controller receives playback-state updates.
- [x] Web Controller can browse Player library.
- [x] Web Controller can queue songs.
- [x] Web Controller can send an online audio URL.

_Ticked items were verified in a browser against a simulated Player on the real relay. Still to test with a real phone Player: different Wi-Fi networks, mobile data, local mode regression on phones._
- [ ] Web Controller works across different Wi‑Fi networks.
- [ ] Web Controller works over mobile data.
- [ ] Android local mode still works without internet.
- [x] No music files are uploaded to Supabase.
- [x] No user login is required in v1.

## 12. Phase placement

Add this as a new phase after Phase 4:

```text
Phase 6 — Web Controller
```

Then renumber the existing later phases if needed:

```text
Phase 0 — Foundation
Phase 1 — Local remote control
Phase 2 — Local MP3 player and queue
Phase 3 — Online URL playback
Phase 4 — Online remote control
Phase 5 — Spotify / YouTube Music external control
Phase 6 — Web Controller
Phase 7 — Polish
```

## 13. AI agent instruction

When this phase begins, tell the agent:

```text
Build the Web Controller only.

Do not modify the Android Player’s core behavior.
Do not make the web app a Player.
Do not store music files in Supabase.
Do not require login.
Use Supabase Realtime as the web Controller transport.
Use the same JSON protocol, pairing flow, session-token model, and error codes as the Android app.
Use the UX guardrails in 15_UX_DESIGN_GUARDRAILS.md.
Do not copy Spotify’s exact visual identity, logo, color palette, icons, artwork, typography, screen layouts, or branding.
```

## Opened from the Player's QR code
The Player's QR code is a link to this page with the pairing details after the `#` (`#/pair?v=1&r=<room>&t=<ticket>&n=<name>`). `main_web.dart` reads it before Flutter rewrites the address, `WebHome` connects online-only with the ticket straight away (a fresh scan beats an old saved session), and the address bar is cleared. The Player user still taps Accept. If the code has no online room, the page explains that the Player must be in online mode. Tests: `test/web_app_test.dart` (opened from the Player QR code), `test/pairing_qr_test.dart`.
