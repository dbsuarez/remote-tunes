# Next tasks

Ideas queued by the project owner. Nothing here is built unless ticked.

## Poweramp-inspired additions

(Inspiration only. Own look and own code, see [docs/15](15_UX_DESIGN_GUARDRAILS.md).)

### Audio engine (Player side)
- [x] Gapless playback: the next local song is lined up in just_audio's playlist (`QueuePlaybackEngine._preloadIfChanged`, `AudioBackend.setNext`). Internet tracks and repeat-one still load normally. Not yet heard on a phone.
- [ ] Crossfade (a fade between songs; needs two players or a volume ramp, and a setting for its length)
- [ ] 10-band graphic EQ with per-output presets (speaker / wired / Bluetooth)
- [ ] Replay Gain scanner (background isolate)

### Library and metadata (Player side)
- [ ] Folder browser view
- [ ] Auto playlists (Recent, Top, New)
- [ ] Album art auto-fetcher service
- [ ] Basic tag editor

### UI/UX (both sides)
- [ ] Skinning engine (JSON themes)
- [ ] Visualizer tab (Player only)
- [ ] Gesture: edge-swipe for Queue Peek / Library
- [ ] Rich MediaSession / lock-screen controls

## Releases and self-update (built)
- [x] Release APKs on GitHub Releases (`.github/workflows/release.yml`, see README "Releases and updates").
- [x] In-app update: Settings > App updates, and a card on Home when a newer version exists.
