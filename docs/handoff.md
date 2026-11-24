# RemoteTunes UX & Feature Upgrade Handoff

## Objective
Elevate RemoteTunes from a utilitarian remote-control tool to a "commercial-grade" premium music player while maintaining strict adherence to our design philosophy (see `docs/15_UX_DESIGN_GUARDRAILS.md`).

## Design Philosophy (Non-Negotiable)
RemoteTunes may use familiar music-player interaction patterns, but **must not copy Spotify’s** visual identity, logo, color palette, icons, artwork, typography, screen layouts, or branding. The app must have its own distinct identity, prioritizing:
- Connection state (Local/Online/Hotspot)
- Two-phone workflow (Controller/Player)
- "Tech-Forward" aesthetic (Dark charcoal background, electric teal/violet accents, sharp lines).

---

## Task Roadmap

### 1. Dynamic Accent System
*   **Goal:** Make the UI feel "aware" of the music. Extract dominant colors from album art and use them to tint playback icons and progress bars.
*   **Implementation:**
    *   Add `palette_generator` to `pubspec.yaml`.
    *   In `lib/features/player/playback_engine.dart`, implement a service to extract the `dominantColor` from album art.
    *   Update `PlaybackState` (in `lib/core/protocol/protocol.dart`) to include this color as an optional field, ensuring it syncs across the network to the Controller.
    *   Update `ControllerView` to use this color for UI accents (progress bars/icon glows).

### 2. Tactile Feedback
*   **Goal:** Add a premium, physical feel to the Controller interface.
*   **Implementation:**
    *   Create a reusable `HapticButton` widget in `lib/core/widgets/`.
    *   Standardize haptic patterns:
        *   `Play/Pause` -> `HapticFeedback.mediumImpact()`
        *   `Skip/Back` -> `HapticFeedback.lightImpact()`
        *   `Selection` -> `HapticFeedback.selectionClick()`
    *   Wrap all transport actions in `controller_views.dart` with this widget.

### 3. "Queue Peek" Interaction
*   **Goal:** Add professional navigation for queue management.
*   **Implementation:**
    *   On the "Now Playing" screen, implement a `DraggableScrollableSheet` overlay.
    *   The sheet should show the current song + the next 3 items.
    *   Ensure it feels like a native "peek" (partially opaque background, smooth drag) rather than a full page navigation.

---

## Developer Notes
- **Web Safety:** Remember that any changes to `lib/features/controller/` must be web-safe. No `dart:io` or heavy Flutter dependencies. Run `test/web_safety_test.dart` to verify.
- **Design Check:** Before finalizing UI changes, compare your work against the examples in `docs/15_UX_DESIGN_GUARDRAILS.md`. 
- **Palette Logic:** Ensure color extraction is non-blocking (use `Compute` or async streams) so the UI doesn't stutter when track changes occur.
