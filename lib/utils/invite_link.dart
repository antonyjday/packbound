/// Builds the shareable deep link for a group invite. Uses the
/// https://packbound.net/join/CODE Android App Link (verified via
/// website/.well-known/assetlinks.json) rather than the packbound://
/// custom scheme, so the link still does something useful - opens a
/// normal webpage with a download link and the code - for whoever it's
/// shared with who doesn't have the app installed yet. The custom scheme
/// still exists and still works (see AndroidManifest.xml) for anything
/// that already builds/parses a packbound:// link.
String buildInviteLink(String inviteCode) => 'https://packbound.net/join/$inviteCode';

/// Parses an invite code out of arbitrary scanned/tapped/pasted input.
/// Handles:
///   - a raw code someone typed or wrote by hand: "AB2XQ9"
///   - the universal link: "https://packbound.net/join/AB2XQ9"
///   - the legacy custom-scheme deep link: "packbound://join/AB2XQ9"
///   - any of the above with a trailing slash or query params, which some
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
