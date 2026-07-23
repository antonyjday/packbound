/// Builds the shareable deep link for a group invite. Uses a custom URL
/// scheme (packbound://join/CODE) rather than a universal/app link, since
/// those require hosting verification files (apple-app-site-association,
/// assetlinks.json) on a real domain you control - see PLATFORM_SETUP.md
/// for upgrading to that later.
String buildInviteLink(String inviteCode) => 'packbound://join/$inviteCode';

/// Parses an invite code out of arbitrary scanned/tapped/pasted input.
/// Handles:
///   - a raw code someone typed or wrote by hand: "AB2XQ9"
///   - our own deep link: "packbound://join/AB2XQ9"
///   - the same link with a trailing slash or query params, which some
///     scanners/share sheets normalize to
String? extractInviteCode(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  final uri = Uri.tryParse(trimmed);
  if (uri != null && uri.scheme == 'packbound' && uri.host == 'join') {
    if (uri.pathSegments.isNotEmpty) return uri.pathSegments.first.toUpperCase();
  }
  if (uri != null && uri.pathSegments.contains('join')) {
    final idx = uri.pathSegments.indexOf('join');
    if (idx + 1 < uri.pathSegments.length) {
      return uri.pathSegments[idx + 1].toUpperCase();
    }
  }

  // Not a recognizable URL - treat the whole string as the raw code.
  return trimmed.toUpperCase();
}
