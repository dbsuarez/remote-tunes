import 'package:crypto/crypto.dart';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// Persists pairing *history* (never the token: docs/03_DATA_MODEL.md says
/// tokens must not be stored in plaintext, so Phase 1 keeps them in memory).
abstract class PairedControllersStore {
  /// Marks every row inactive (called when the Player server starts).
  Future<void> deactivateAll();

  Future<void> upsert({
    required String sessionId,
    required String controllerName,
    required String? controllerAddress,
    required String connectionType,
  });

  Future<void> setActive(String sessionId, bool active);

  // -- Trusted devices (reconnect without pairing again) --

  /// Remembers this Controller as trusted. Only a hash of [token] is kept.
  Future<void> trust({required String sessionId, required String token});

  /// A trusted Controller, or null if unknown or forgotten.
  Future<TrustedController?> findTrusted(String sessionId);

  Future<List<TrustedController>> listTrusted();

  Future<void> forget(String sessionId);

  Future<void> forgetAll();
}

/// A Controller the Player trusts.
class TrustedController {
  const TrustedController({
    required this.sessionId,
    required this.name,
    required this.tokenHash,
    required this.lastSeen,
  });

  final String sessionId;
  final String name;
  final String tokenHash;
  final DateTime lastSeen;
}

/// SHA-256 (hex) of a session token.
String hashToken(String token) => sha256.convert(utf8.encode(token)).toString();

class DriftPairedControllersStore implements PairedControllersStore {
  DriftPairedControllersStore(this._db);

  final AppDatabase _db;

  @override
  Future<void> deactivateAll() => _db
      .update(_db.pairedControllers)
      .write(const PairedControllersCompanion(active: Value(false)));

  @override
  Future<void> upsert({
    required String sessionId,
    required String controllerName,
    required String? controllerAddress,
    required String connectionType,
  }) {
    final now = DateTime.now();
    return _db.into(_db.pairedControllers).insertOnConflictUpdate(
          PairedControllersCompanion.insert(
            sessionId: sessionId,
            controllerName: controllerName,
            controllerAddress: Value(controllerAddress),
            connectionType: connectionType,
            pairedAt: Value(now),
            lastSeenAt: Value(now),
            active: const Value(true),
          ),
        );
  }

  @override
  Future<void> setActive(String sessionId, bool active) {
    return (_db.update(_db.pairedControllers)
          ..where((t) => t.sessionId.equals(sessionId)))
        .write(PairedControllersCompanion(
      active: Value(active),
      lastSeenAt: Value(DateTime.now()),
    ));
  }

  @override
  Future<void> trust({required String sessionId, required String token}) {
    return (_db.update(_db.pairedControllers)
          ..where((t) => t.sessionId.equals(sessionId)))
        .write(PairedControllersCompanion(
      tokenHash: Value(hashToken(token)),
      trusted: const Value(true),
    ));
  }

  TrustedController _toTrusted(PairedController r) => TrustedController(
        sessionId: r.sessionId,
        name: r.controllerName,
        tokenHash: r.tokenHash ?? '',
        lastSeen: r.lastSeenAt,
      );

  @override
  Future<TrustedController?> findTrusted(String sessionId) async {
    final r = await (_db.select(_db.pairedControllers)
          ..where((t) => t.sessionId.equals(sessionId) & t.trusted.equals(true)))
        .getSingleOrNull();
    return (r == null || r.tokenHash == null) ? null : _toTrusted(r);
  }

  @override
  Future<List<TrustedController>> listTrusted() async {
    final rows = await (_db.select(_db.pairedControllers)
          ..where((t) => t.trusted.equals(true))
          ..orderBy([(t) => OrderingTerm.desc(t.lastSeenAt)]))
        .get();
    return [for (final r in rows) _toTrusted(r)];
  }

  @override
  Future<void> forget(String sessionId) {
    return (_db.update(_db.pairedControllers)
          ..where((t) => t.sessionId.equals(sessionId)))
        .write(const PairedControllersCompanion(
      tokenHash: Value(null),
      trusted: Value(false),
    ));
  }

  @override
  Future<void> forgetAll() => _db.update(_db.pairedControllers).write(
      const PairedControllersCompanion(tokenHash: Value(null), trusted: Value(false)));
}
