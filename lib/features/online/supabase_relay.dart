import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/online/relay.dart';
import '../../core/online/room_code.dart';

/// The real online relay: Supabase Realtime *Broadcast*. No tables, no login,
/// no files: only short-lived messages between the two phones in a room.
///
/// A plain [SupabaseClient] is used (not `Supabase.initialize`), so the keys
/// entered in Settings can change without restarting the app, and nothing
/// Supabase-related runs unless the user turns the online relay on.
class SupabaseRelayFactory {
  SupabaseRelayFactory({required String url, required String anonKey})
      : _client = SupabaseClient(url, anonKey);

  final SupabaseClient _client;

  RelayChannel call(String roomCode) => SupabaseRelayChannel(_client, roomCode);

  /// Closes the connection to Supabase. Call when the Player/Controller leaves.
  Future<void> dispose() async {
    try {
      await _client.dispose();
    } catch (_) {}
  }
}

class SupabaseRelayChannel implements RelayChannel {
  SupabaseRelayChannel(this._client, this.roomCode);

  static const _event = 'rt';

  final SupabaseClient _client;
  final String roomCode;

  RealtimeChannel? _channel;
  final StreamController<RelayFrame> _frames = StreamController.broadcast();
  final StreamController<RelayStatus> _status = StreamController.broadcast();
  bool _joined = false;
  bool _left = false;

  @override
  Stream<RelayFrame> get frames => _frames.stream;

  @override
  Stream<RelayStatus> get status => _status.stream;

  @override
  Future<void> join() async {
    final done = Completer<void>();
    final channel = _client.channel(
      RoomCode.channelName(roomCode),
      // `self: false`: never hear our own messages. No acks: faster, and
      // delivery problems surface through the connection status instead.
      opts: const RealtimeChannelConfig(self: false, ack: false),
    );
    channel.onBroadcast(
      event: _event,
      callback: (payload) {
        final frame = RelayFrame.fromPayload(payload);
        if (frame != null && !_frames.isClosed) _frames.add(frame);
      },
    );
    channel.subscribe((status, error) {
      switch (status) {
        case RealtimeSubscribeStatus.subscribed:
          if (!done.isCompleted) {
            done.complete();
          } else if (!_status.isClosed) {
            _status.add(RelayStatus.connected); // rejoined by itself
          }
        case RealtimeSubscribeStatus.channelError:
        case RealtimeSubscribeStatus.timedOut:
        case RealtimeSubscribeStatus.closed:
          if (!done.isCompleted) {
            done.completeError(RelayException(_explain(status, error)));
          } else if (!_status.isClosed && !_left) {
            _status.add(status == RealtimeSubscribeStatus.closed
                ? RelayStatus.closed
                : RelayStatus.error);
          }
      }
    });
    _channel = channel;

    try {
      await done.future;
    } catch (_) {
      await _remove();
      rethrow;
    }
    _joined = true;
  }

  @override
  Future<void> send(RelayFrame frame) async {
    final channel = _channel;
    if (!_joined || channel == null) {
      throw RelayException('Not connected to the online relay.');
    }
    final ChannelResponse result;
    try {
      result = await channel.sendBroadcastMessage(
        event: _event,
        payload: frame.toPayload(),
      );
    } catch (_) {
      throw RelayException('The online relay could not send that message.');
    }
    if (result != ChannelResponse.ok) {
      throw RelayException(
        result == ChannelResponse.timedOut
            ? 'The online relay took too long. Check the internet connection.'
            : 'The online relay could not send that message.',
      );
    }
  }

  @override
  Future<void> leave() async {
    _left = true;
    _joined = false;
    await _remove();
    if (!_frames.isClosed) await _frames.close();
    if (!_status.isClosed) await _status.close();
  }

  Future<void> _remove() async {
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      try {
        await _client.removeChannel(channel);
      } catch (_) {}
    }
  }

  /// Plain-language reason for a failed join. The raw error is not shown (it
  /// may contain keys or URLs).
  String _explain(RealtimeSubscribeStatus status, Object? error) {
    final text = '$error'.toLowerCase();
    if (text.contains('unauthorized') ||
        text.contains('forbidden') ||
        text.contains('403') ||
        text.contains('401') ||
        text.contains('invalid api key') ||
        text.contains('jwt')) {
      return 'The online relay refused the connection. Check the Supabase URL '
          'and anon key in Settings, and that Realtime allows public access.';
    }
    if (status == RealtimeSubscribeStatus.timedOut) {
      return 'The online relay took too long to answer. Check the internet '
          'connection.';
    }
    return "Couldn't connect to the online relay. Check the internet "
        'connection and the Supabase URL and anon key in Settings.';
  }
}
