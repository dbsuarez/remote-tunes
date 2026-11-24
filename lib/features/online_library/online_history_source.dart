import '../../core/protocol/library_models.dart';
import '../controller/controller_client.dart';

/// What the history screen needs from the Player. The history is kept on the
/// Player phone; entries are played again by id (the stream link never leaves
/// the Player).
abstract class OnlineHistorySource {
  /// Newest first, and whether the Player is recording history.
  Future<({LibraryPage<RemoteHistoryItem> page, bool enabled})> load(
      {int offset, int limit});

  Future<void> play(RemoteHistoryItem item, {required bool queue});
  Future<void> remove(RemoteHistoryItem item);
  Future<void> clear();
  Future<void> setEnabled(bool enabled);
}

/// The Controller's view of the Player's history: protocol requests.
class ClientHistorySource implements OnlineHistorySource {
  ClientHistorySource(this._client);

  final ControllerClient _client;

  @override
  Future<({LibraryPage<RemoteHistoryItem> page, bool enabled})> load(
          {int offset = 0, int limit = 50}) =>
      _client.onlineHistory(offset: offset, limit: limit);

  @override
  Future<void> play(RemoteHistoryItem item, {required bool queue}) =>
      _client.playHistory(item.id, queue: queue);

  @override
  Future<void> remove(RemoteHistoryItem item) => _client.removeHistory(item.id);

  @override
  Future<void> clear() => _client.clearHistory();

  @override
  Future<void> setEnabled(bool enabled) => _client.setHistoryEnabled(enabled);
}

/// "Today 14:05", "Yesterday 09:30", or "12 Nov 2026".
String playedLabel(DateTime now, int secondsSinceEpoch) {
  if (secondsSinceEpoch <= 0) return '';
  final t = DateTime.fromMillisecondsSinceEpoch(secondsSinceEpoch * 1000);
  String two(int n) => n.toString().padLeft(2, '0');
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final time = '${two(t.hour)}:${two(t.minute)}';
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today $time';
  if (diff == 1) return 'Yesterday $time';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${t.day} ${months[t.month - 1]} ${t.year}';
}
