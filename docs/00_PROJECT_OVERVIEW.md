# RemoteTunes — Project Overview (v2)

Offline-first Flutter app: one Android phone controls music playback on another. Local mode works without internet; online mode is optional.

## Roles
- Controller: discovers, pairs, sends commands, views state.
- Player: hosts local server or joins online relay, plays audio, manages queue, reports state.

## Connection modes
- Local only: same Wi‑Fi or hotspot, no internet.
- Online only: Supabase Realtime relay, internet required.
- Auto: prefer local, fall back to online.

## MVP
- Local discovery, manual IP/port, pairing, session token.
- Local WebSocket control.
- Optional Supabase Realtime online relay.
- Play/pause/toggle/next/previous/seek/volume.
- Local MP3 library and queue.
- Background playback and Android media notification.
- Direct online audio URL playback.

## Rules
- Offline-first, not offline-only.
- Do not remove online features.
- Do not make online mode mandatory.
- Do not make local mode depend on Supabase.
- Do not store music files in Supabase.
- No forced login in v1.
- Build one phase at a time.

## Phases
0 Foundation  
1 Local remote control  
2 Local MP3 player and queue  
3 Online URL playback  
4 Online remote control via Supabase Realtime  
5 Spotify/YouTube Music external control  
6 Polish  
