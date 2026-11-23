/// Validation for direct audio URLs (FR-57, FR-58). Pure Dart.
class UrlCheck {
  const UrlCheck.ok(this.uri) : error = null;
  const UrlCheck.invalid(this.error) : uri = null;

  /// The cleaned-up address when valid.
  final Uri? uri;

  /// Plain-language reason when invalid.
  final String? error;

  bool get isValid => uri != null;
}

const int maxUrlLength = 2048;

/// Checks that [input] is a usable http(s) link. Does not touch the network.
UrlCheck validateAudioUrl(String? input) {
  final text = (input ?? '').trim();
  if (text.isEmpty) {
    return const UrlCheck.invalid('Paste a link to an audio file.');
  }
  if (text.length > maxUrlLength) {
    return const UrlCheck.invalid('That link is too long.');
  }
  if (RegExp(r'\s').hasMatch(text)) {
    return const UrlCheck.invalid('Links cannot contain spaces.');
  }
  final Uri uri;
  try {
    uri = Uri.parse(text);
  } on FormatException {
    return const UrlCheck.invalid("That doesn't look like a valid link.");
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    return const UrlCheck.invalid(
      'Only http:// and https:// links are supported.',
    );
  }
  if (uri.host.isEmpty) {
    return const UrlCheck.invalid("That link has no website address.");
  }
  if (uri.userInfo.isNotEmpty) {
    return const UrlCheck.invalid(
      "Links with a username or password aren't supported.",
    );
  }
  return UrlCheck.ok(uri);
}

/// A short readable title for a URL: the file name without its extension, or
/// the host name when the path has no file name.
String titleFromUrl(Uri uri) {
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.isNotEmpty) {
    // Uri.pathSegments is already percent-decoded.
    var name = segments.last;
    final dot = name.lastIndexOf('.');
    // "song.mp3" -> "song"; a bare ".mp3" has no name, so use the host.
    if (dot >= 0) name = name.substring(0, dot);
    name = name.replaceAll(RegExp(r'[_+]+'), ' ').trim();
    if (name.isNotEmpty) return name;
  }
  return uri.host;
}
