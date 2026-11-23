/// Supabase project this build uses for the online relay (Phase 4), so phones
/// don't need the URL and key typed in.
///
/// These are the project's **Project URL** and **publishable (anon) key**. The
/// publishable key is designed to be shipped inside apps; it is not a secret.
/// (Never put the `service_role` key or a database password here.)
///
/// What the user types in Settings → Online relay always wins over these. To
/// build for a different project without editing code:
///   flutter build apk --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///                     --dart-define=SUPABASE_KEY=sb_publishable_...
class OnlineDefaults {
  OnlineDefaults._();

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://olsojrthovfpjcfqilew.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_KEY',
    defaultValue: 'sb_publishable_15rIwXQHj2fs4WGztP6Tvg_g1MYWvrS',
  );
}
