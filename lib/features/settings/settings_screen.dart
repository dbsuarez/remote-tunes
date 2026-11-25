import 'file_access_tile.dart';
import 'package:flutter/material.dart';
import '../update/update_widgets.dart';
import 'album_art_dialog.dart';
import '../library/import_actions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/enums.dart';
import '../../core/online_defaults.dart';
import '../../core/router/app_router.dart';
import '../../core/song_list_style.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/settings_repository.dart';
import '../../providers/connection_providers.dart';
import '../../providers/providers.dart';
import '../external/external_limits.dart';
import '../home/widgets/connection_mode_selector.dart';
import '../online/online_setup.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(settingsProvider);
    final repo = ref.read(settingsRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not load settings. Please restart the app.',
                style: TextStyle(color: theme.colorScheme.error),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          data: (s) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              const _SectionHeader('Device'),
              _SavedTextField(
                label: 'Device name',
                value: s.deviceName,
                maxLength: 40,
                validator: (v) =>
                    v.trim().isEmpty ? 'Name cannot be empty' : null,
                onSave: repo.setDeviceName,
              ),
              const SizedBox(height: 24),
              const _SectionHeader('Connection mode'),
              ConnectionModeSelector(
                value: s.connectionMode,
                onChanged: repo.setConnectionMode,
              ),
              const SizedBox(height: 24),
              const _SectionHeader('Online relay (optional)'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable online relay'),
                subtitle: const Text(
                  'Optional. Lets a Controller on another network or mobile '
                  'data connect to the Player. Local mode never needs '
                  'internet or Supabase.',
                ),
                value: s.onlineRelayEnabled,
                onChanged: repo.setOnlineRelayEnabled,
              ),
              const SizedBox(height: 8),
              _SavedTextField(
                label: 'Supabase URL',
                value: s.supabaseUrl ?? '',
                keyboardType: TextInputType.url,
                validator: (v) {
                  final t = v.trim();
                  if (t.isEmpty) return null;
                  final uri = Uri.tryParse(t);
                  final ok = uri != null &&
                      (uri.scheme == 'https' || uri.scheme == 'http') &&
                      uri.host.isNotEmpty;
                  return ok ? null : 'Enter a valid http(s) URL';
                },
                onSave: repo.setSupabaseUrl,
              ),
              const SizedBox(height: 12),
              _SavedTextField(
                label: 'Supabase anon key',
                value: s.supabaseAnonKey ?? '',
                obscure: true,
                onSave: repo.setSupabaseAnonKey,
              ),
              const SizedBox(height: 12),
              _RelayTester(settings: s),
              if (s.supabaseUrl == OnlineDefaults.supabaseUrl &&
                  s.supabaseAnonKey == OnlineDefaults.supabaseAnonKey) ...[
                const SizedBox(height: 8),
                Text(
                  "These are pre-filled with this build's own Supabase "
                  'project. Change them to use a different one.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'Use your own free Supabase project. In its dashboard, copy the '
                'Project URL and the anon (public) key, and under Realtime '
                'settings allow public access so Broadcast works without '
                'sign-in. Only short playback commands and status messages '
                'pass through it. Music, file names and paths never do.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              const _SectionHeader('Playback defaults'),
              _VolumeSetting(
                value: s.defaultVolume,
                onSave: repo.setDefaultVolume,
              ),
              const SizedBox(height: 8),
              Text('Repeat and shuffle are remembered: they stay as you leave them with the buttons on Now Playing.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              Text('Repeat', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<RepeatMode>(
                  showSelectedIcon: false,
                  segments: [
                    for (final m in RepeatMode.values)
                      ButtonSegment(value: m, label: Text(m.label)),
                  ],
                  selected: {s.repeatMode},
                  onSelectionChanged: (v) => repo.setRepeatMode(v.first),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Shuffle'),
                value: s.shuffleEnabled,
                onChanged: repo.setShuffleEnabled,
              ),
              const SizedBox(height: 16),
              const _SectionHeader('Song list'),
              Text('Text size', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<SongListSize>(
                  showSelectedIcon: false,
                  segments: [
                    for (final z in SongListSize.values)
                      ButtonSegment(value: z, label: Text(z.label)),
                  ],
                  selected: {s.songListSize},
                  onSelectionChanged: (v) => repo.setSongListSize(v.first),
                ),
              ),
              const SizedBox(height: 16),
              const _SectionHeader('When the app opens'),
              RadioGroup<StartMode>(
                groupValue: s.startMode,
                onChanged: (v) {
                  if (v != null) repo.setStartMode(v);
                },
                child: Column(
                  children: [
                    for (final m in StartMode.values)
                      RadioListTile<StartMode>(
                        contentPadding: EdgeInsets.zero,
                        value: m,
                        title: Text(m.label),
                        subtitle: Text(m.description),
                      ),
                  ],
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Start remote playback when the app opens'),
                subtitle: const Text(
                    'Lets other phones control this one without pressing the button. '
                    'Uses a little battery and the network while the app runs.'),
                value: s.remoteAutoStart,
                onChanged: repo.setRemoteAutoStart,
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Queue opens at the song playing'),
                subtitle: const Text(
                    'Going to the Queue scrolls to the song that is playing now. Switch off to keep the list where you left it.'),
                value: s.queueScrollToCurrent,
                onChanged: repo.setQueueScrollToCurrent,
              ),
              const SizedBox(height: 8),
              const _SectionHeader('Look and feel'),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.palette_outlined),
                title: const Text('Skins'),
                subtitle: Text('Now: ${s.skin.name}'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(AppRoutes.skins),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Haptic feedback'),
                subtitle: const Text('A short vibration when you tap play, skip or pick something.'),
                value: s.hapticsEnabled,
                onChanged: repo.setHapticsEnabled,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Colors from album art'),
                subtitle: const Text(
                    'The Controller takes its accent color from the playing song\'s cover.'),
                value: s.accentFromArt,
                onChanged: repo.setAccentFromArt,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Lyrics from the internet'),
                subtitle: const Text(
                    'The Player looks up lyrics on LRCLIB (and lyrics.ovh) when you open them. '
                    'Only the song\'s title, artist, album and length are sent, and the lyrics '
                    'are kept on the Player.'),
                value: s.lyricsEnabled,
                onChanged: repo.setLyricsEnabled,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.equalizer_rounded),
                title: const Text('Equalizer'),
                subtitle: const Text('Presets and bands for the music on this phone.'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(AppRoutes.equalizer),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.graphic_eq_rounded),
                title: const Text('Even out loudness'),
                subtitle: const Text(
                    'Turns loud songs down to the level in their Replay Gain tags, so songs sound '
                    'about equally loud. Run "Update tags from files" once to read the tags. '
                    'It never turns a song up.'),
              ),
              RadioGroup<ReplayGainMode>(
                groupValue: s.replayGainMode,
                onChanged: (v) {
                  if (v != null) repo.setReplayGainMode(v);
                },
                child: Column(
                  children: [
                    for (final m in ReplayGainMode.values)
                      RadioListTile<ReplayGainMode>(
                        contentPadding: const EdgeInsets.only(left: 16),
                        dense: true,
                        value: m,
                        title: Text(m.label),
                      ),
                  ],
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.compare_arrows_rounded),
                title: Text(s.crossfadeSeconds == 0
                    ? 'Crossfade: off'
                    : 'Crossfade: ${s.crossfadeSeconds} seconds'),
                subtitle: const Text(
                    'One song fades out while the next fades in. Only for songs on this phone, '
                    'and only when the next song is also a file here.'),
              ),
              Slider(
                value: s.crossfadeSeconds.toDouble(),
                max: 12,
                divisions: 12,
                label: s.crossfadeSeconds == 0 ? 'Off' : '${s.crossfadeSeconds} s',
                onChanged: (v) => repo.setCrossfadeSeconds(v.round()),
              ),
              const AlbumArtTile(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.sell_outlined),
                title: const Text('Update tags from files'),
                subtitle: const Text(
                    'Reads the genre, year and album artist of every song again, so the '
                    'Genres, Years and Album Artists lists fill in. Nothing is changed in the files.'),
                onTap: () => refreshLibraryTags(context, ref),
              ),
              const FileAccessTile(),
              const SizedBox(height: 16),
              const _SectionHeader('App updates'),
              UpdateSettingsTiles(settings: s),
              const SizedBox(height: 16),
              const _SectionHeader('Advanced'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('External app control'),
                subtitle: const Text(
                  'Let a Controller control Spotify, YouTube Music or another '
                  'music app on the Player phone. Off by default. Takes effect '
                  'the next time you open Player mode.',
                ),
                value: s.externalAppControlEnabled,
                onChanged: (on) async {
                  // Turning it on needs the user to understand what it asks of
                  // Android first. Turning it off needs no confirmation.
                  if (on && !await _confirmExternal(context)) return;
                  await repo.setExternalAppControlEnabled(on);
                },
              ),
              const SizedBox(height: 8),
              _SavedTextField(
                label: 'Player port',
                value: s.lastPlayerPort.toString(),
                keyboardType: TextInputType.number,
                validator: (v) {
                  final n = int.tryParse(v.trim());
                  if (n == null || n < 1024 || n > 65535) {
                    return 'Enter a port between 1024 and 65535';
                  }
                  return null;
                },
                onSave: (v) => repo.setLastPlayerPort(int.parse(v.trim())),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.monitor_heart_outlined),
                title: const Text('Diagnostics'),
                subtitle: const Text('Version, network and library status you can copy'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(AppRoutes.diagnostics),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Explains Notification access before External App Control can be enabled.
Future<bool> _confirmExternal(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Control other music apps?'),
      content: SingleChildScrollView(child: const Text(externalConsentText)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Turn on'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.titleMedium
            ?.copyWith(color: theme.colorScheme.primary),
      ),
    );
  }
}

/// Text field that saves on submit or when focus is lost, if valid.
class _SavedTextField extends StatefulWidget {
  const _SavedTextField({
    required this.label,
    required this.value,
    required this.onSave,
    this.validator,
    this.keyboardType,
    this.obscure = false,
    this.maxLength,
  });

  final String label;
  final String value;
  final Future<void> Function(String) onSave;
  final String? Function(String)? validator;
  final TextInputType? keyboardType;
  final bool obscure;
  final int? maxLength;

  @override
  State<_SavedTextField> createState() => _SavedTextFieldState();
}

class _SavedTextFieldState extends State<_SavedTextField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);
  final FocusNode _focus = FocusNode();
  String? _error;
  late bool _hidden = widget.obscure;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(covariant _SavedTextField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _commit() async {
    final text = _controller.text;
    final err = widget.validator?.call(text);
    setState(() => _error = err);
    if (err == null && text != widget.value) {
      await widget.onSave(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focus,
      keyboardType: widget.keyboardType,
      obscureText: _hidden,
      maxLength: widget.maxLength,
      autocorrect: false,
      enableSuggestions: !widget.obscure,
      onSubmitted: (_) => _commit(),
      decoration: InputDecoration(
        labelText: widget.label,
        errorText: _error,
        counterText: '',
        suffixIcon: widget.obscure
            ? IconButton(
                tooltip: _hidden ? 'Show' : 'Hide',
                icon: Icon(_hidden
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _hidden = !_hidden),
              )
            : null,
      ),
    );
  }
}

/// Default volume slider: stored 0.0–1.0, shown as 0–100%.
class _VolumeSetting extends StatefulWidget {
  const _VolumeSetting({required this.value, required this.onSave});

  final double value;
  final Future<void> Function(double) onSave;

  @override
  State<_VolumeSetting> createState() => _VolumeSettingState();
}

class _VolumeSettingState extends State<_VolumeSetting> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final v = _dragging ?? widget.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Default volume: ${(v * 100).round()}%'),
        Slider(
          value: v,
          onChanged: (x) => setState(() => _dragging = x),
          onChangeEnd: (x) async {
            await widget.onSave(x);
            if (mounted) setState(() => _dragging = null);
          },
        ),
      ],
    );
  }
}

/// "Test online relay": joins a throw-away room to check the URL and key.
class _RelayTester extends ConsumerStatefulWidget {
  const _RelayTester({required this.settings});

  final AppSettings settings;

  @override
  ConsumerState<_RelayTester> createState() => _RelayTesterState();
}

class _RelayTesterState extends ConsumerState<_RelayTester> {
  bool _busy = false;
  RelayTestResult? _result;

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _result = null;
    });
    RelayTestResult result;
    try {
      result = await ref.read(relayTesterProvider)(widget.settings);
    } catch (_) {
      result = const RelayTestResult.failed("Couldn't test the online relay.");
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _result = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = _result;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
          onPressed: _busy ? null : _run,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.network_check_rounded),
          label: Text(_busy ? 'Testing…' : 'Test online relay'),
        ),
        if (r != null) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                r.success ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                size: 18,
                color: r.success ? RtColors.teal : theme.colorScheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(r.message, style: theme.textTheme.bodySmall)),
            ],
          ),
        ],
      ],
    );
  }
}
