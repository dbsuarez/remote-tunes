import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/constants.dart';
import 'package:remote_tunes/core/url_validation.dart';

void main() {
  group('validateAudioUrl', () {
    test('accepts http and https links and trims whitespace', () {
      expect(validateAudioUrl('https://example.com/song.mp3').isValid, isTrue);
      expect(validateAudioUrl('  http://example.com/a/b.ogg?x=1#t ').isValid, isTrue);
      expect(validateAudioUrl('HTTPS://EXAMPLE.COM/Song.MP3').isValid, isTrue);
      expect(validateAudioUrl('http://192.168.1.5:8000/stream').isValid, isTrue);
      expect(validateAudioUrl('https://example.com/song.mp3').uri!.host, 'example.com');
    });

    test('rejects empty input', () {
      for (final v in [null, '', '   ']) {
        final c = validateAudioUrl(v);
        expect(c.isValid, isFalse);
        expect(c.error, contains('Paste a link'));
      }
    });

    test('rejects other schemes', () {
      for (final v in [
        'ftp://example.com/a.mp3',
        'file:///sdcard/a.mp3',
        'content://media/1',
        'javascript:alert(1)',
        'rtsp://example.com/a',
        'example.com/song.mp3',
      ]) {
        final c = validateAudioUrl(v);
        expect(c.isValid, isFalse, reason: v);
        expect(c.error, isNotNull);
      }
      expect(validateAudioUrl('ftp://x.com/a').error, contains('http://'));
    });

    test('rejects missing host, spaces, credentials and over-long links', () {
      expect(validateAudioUrl('https://').error, contains('no website'));
      expect(validateAudioUrl('https:///song.mp3').isValid, isFalse);
      expect(validateAudioUrl('https://exa mple.com/a.mp3').error, contains('spaces'));
      expect(validateAudioUrl('https://user:pw@example.com/a.mp3').error,
          contains('username'));
      expect(validateAudioUrl('https://example.com/${'a' * 3000}').error,
          contains('too long'));
    });
  });

  test('the built-in test MP3 link is valid (and keeps its /downloads/ path)', () {
    final c = validateAudioUrl(AppConstants.sampleAudioUrl);
    expect(c.isValid, isTrue, reason: c.error);
    expect(c.uri!.scheme, 'https');
    // Without "/downloads/" the site returns a 404 web page, not audio.
    expect(c.uri!.path, '/downloads/audio/mp3/music-sample-128kbps.mp3');
    expect(titleFromUrl(c.uri!), 'music-sample-128kbps');
  });

  group('titleFromUrl', () {
    String t(String u) => titleFromUrl(Uri.parse(u));

    test('uses the file name without its extension', () {
      expect(t('https://example.com/music/My_Song.mp3'), 'My Song');
      expect(t('https://example.com/a/b/track+one.ogg?x=1'), 'track one');
      expect(t('https://example.com/Caf%C3%A9%20Del%20Mar.flac'), 'Café Del Mar');
    });

    test('falls back to the host name', () {
      expect(t('https://radio.example.com/'), 'radio.example.com');
      expect(t('https://radio.example.com'), 'radio.example.com');
      expect(t('https://radio.example.com/.mp3'), 'radio.example.com');
    });

    test('keeps names without an extension', () {
      expect(t('https://example.com/live/stream'), 'stream');
    });
  });
}
