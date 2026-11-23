# RemoteTunes — Architecture (v2)

## Overview
Offline-first, online-optional.

```text
Local:  Controller ---> local Wi‑Fi/hotspot ---> Player
Online: Controller ---> Supabase Realtime ---> Player
```

## Modes
- Auto: try local, fallback online.
- Local only: no internet.
- Online only: Supabase Realtime relay.

## Local mode
Player hosts WebSocket server on port 8765, advertises mDNS/NSD, accepts Controller, validates pairing/token, plays audio, sends state.

Controller discovers, connects, sends commands, receives state.

## Online mode
Both phones connect to Supabase Realtime channel `remotetunes:<room-code>`. Room code is random/short-lived. Same JSON protocol as local. No music files stored in Supabase. No login required in v1.

## Stack
- Flutter
- Riverpod
- Drift/SQLite
- just_audio
- audio_service
- shelf + shelf_web_socket
- web_socket_channel
- bonsoir or Android NSD
- supabase_flutter
- file_picker
- audio_metadata_reader or platform channel

## Transport abstraction
```dart
abstract class RemoteTransport {
  Future<void> connect();
  Stream<RemoteMessage> get messages;
  Future<void> send(RemoteMessage message);
  Future<void> disconnect();
}
```
Implementations: LocalWebSocketTransport, SupabaseRealtimeTransport.

## Rules
- Do not remove online features.
- Do not make online mandatory.
- Do not make local depend on Supabase.
- Do not store music in Supabase.
- Shared RemoteTransport abstraction.
