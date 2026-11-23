# Phase 4 — Online Remote Control

## Objective
Optional online remote control using Supabase Realtime.

## Scope
- Supabase Realtime transport.
- Online room code.
- Online pairing.
- Online command relay.
- Online state relay.
- Connection mode selector.
- Auto/local/online switching.
- Reconnection.

## Protocol
Same JSON as local. Channel: remotetunes:<room-code>.

## Acceptance
- Online relay works.
- Online pairing works.
- Online commands work.
- Online state works.
- Works across networks/mobile data.
- Local still works offline.
