# Phase 0 — Setup (v2)

## Packages
```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.6.1
  go_router: ^14.0.0
  drift: ^2.20.0
  sqlite3_flutter_libs: ^0.5.24
  path_provider: ^2.1.4
  path: ^1.9.0
  shared_preferences: ^2.3.2
  supabase_flutter: ^2.8.0
  just_audio: ^0.10.0
  audio_service: ^0.18.18
  file_picker: ^8.0.0
  uuid: ^4.5.1
dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0
  build_runner: ^2.4.13
  drift_dev: ^2.20.0
```

## Commands
```bash
flutter create remote_tunes
cd remote_tunes
flutter pub add flutter_riverpod go_router drift sqlite3_flutter_libs path_provider path shared_preferences supabase_flutter just_audio audio_service file_picker uuid
flutter pub add --dev build_runner drift_dev
flutter pub get
flutter run
```

## Home
Device name, connection mode selector, Start as PLAYER, Start as CONTROLLER, history, settings.

## Settings
Device name, connection mode, online relay toggle, Supabase URL/key, default volume, repeat, shuffle, external app control, last port.

## Android
Permissions and audio service manifest as in permissions doc.

## Acceptance
- App runs both phones.
- Mode selector works.
- Settings persist.
- DB initializes.
- Supabase included but not required for local.
