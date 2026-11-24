import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'group_models.dart';

/// This phone playing along with the Player (group play). Null where that is
/// not possible, which is everywhere except the phone app (the web Controller
/// has no audio of its own): the Group card is then simply not shown. The phone
/// app supplies the real one in `main.dart`.
final groupFollowerProvider = Provider<GroupFollower?>((ref) => null);

/// Live status of [groupFollowerProvider] for the Group card.
final groupStatusProvider = StreamProvider.autoDispose<GroupStatus>((ref) async* {
  final f = ref.watch(groupFollowerProvider);
  if (f == null) return;
  yield f.status;
  yield* f.statusStream;
});
