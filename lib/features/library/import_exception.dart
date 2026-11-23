/// A failed import with a message safe to show the user. Kept in its own file
/// (no dart:io) so UI code shared with the web Controller can recognise it.
class ImportException implements Exception {
  ImportException(this.message);
  final String message;

  @override
  String toString() => message;
}
