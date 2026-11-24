/// A Jamendo client ID baked into a build, so the Online tab works without
/// pasting one. Empty unless the build was given one:
///
///   fvm flutter build apk --debug --dart-define-from-file=docs/jamendo.json
///
/// `docs/jamendo.json` is ignored by git, so the ID is not in the repository.
/// (A client ID is not a password, but it is tied to your Jamendo account's
/// quota, so keep it out of the public source.) An ID the user pastes in the
/// app always wins over this one.
class JamendoDefaults {
  JamendoDefaults._();

  static const String clientId = String.fromEnvironment('JAMENDO_CLIENT_ID');
}
