import 'package:flutter_test/flutter_test.dart';
import 'package:convoy_app/utils/invite_link.dart';

void main() {
  group('buildInviteLink', () {
    test('builds the packbound.net universal link', () {
      expect(buildInviteLink('AB2XQ9'), 'https://packbound.net/join/AB2XQ9');
    });
  });

  group('extractInviteCode', () {
    test('accepts a raw code typed or written by hand', () {
      expect(extractInviteCode('AB2XQ9'), 'AB2XQ9');
    });

    test('uppercases a lowercase raw code', () {
      expect(extractInviteCode('ab2xq9'), 'AB2XQ9');
    });

    test('extracts the code from the legacy custom-scheme deep link', () {
      expect(extractInviteCode('packbound://join/AB2XQ9'), 'AB2XQ9');
    });

    test('handles a trailing slash some share sheets add', () {
      expect(extractInviteCode('packbound://join/AB2XQ9/'), 'AB2XQ9');
    });

    test('extracts the code from our own universal link', () {
      expect(extractInviteCode('https://packbound.net/join/AB2XQ9'), 'AB2XQ9');
    });

    test('extracts the code from our universal link with a trailing slash', () {
      expect(extractInviteCode('https://packbound.net/join/AB2XQ9/'), 'AB2XQ9');
    });

    test('extracts the code even if "join" is a path segment rather than the host',
        () {
      expect(extractInviteCode('https://example.com/join/AB2XQ9'), 'AB2XQ9');
    });

    test('trims surrounding whitespace', () {
      expect(extractInviteCode('  AB2XQ9  '), 'AB2XQ9');
    });

    test('returns null for an empty or whitespace-only string', () {
      expect(extractInviteCode(''), null);
      expect(extractInviteCode('   '), null);
    });
  });
}
