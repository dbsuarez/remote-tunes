/// Only https links on jamendo.com are accepted from Jamendo's answers and
/// from Controllers (stream, artwork). Anything else is dropped.
String? jamendoHttpsUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.scheme != 'https') return null;
  final host = uri.host.toLowerCase();
  if (host != 'jamendo.com' && !host.endsWith('.jamendo.com')) return null;
  return uri.toString();
}

/// A Creative Commons licence link (any https or http creativecommons.org
/// page). Used for the licence shown with a track.
String? creativeCommonsUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  final uri = Uri.tryParse(url.trim());
  if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) return null;
  final host = uri.host.toLowerCase();
  if (host != 'creativecommons.org' && !host.endsWith('.creativecommons.org')) {
    return null;
  }
  return uri.toString();
}
