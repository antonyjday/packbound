import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:app_links/app_links.dart';
import '../utils/invite_link.dart';

/// Listens for `https://packbound.net/join/CODE` universal links (and the
/// legacy `packbound://join/CODE` custom scheme), whether the app was
/// launched cold by tapping the link or was already running in the
/// background.
///
/// Deliberately simple rather than routing directly: it just exposes a
/// `ValueNotifier` with the pending code. Whatever screen is in a
/// position to act on it (currently HomeScreen, once the user is signed
/// in) listens and consumes it. This avoids needing a global navigator
/// key + deciding "is it safe to push a route right now" from outside
/// the widget tree, especially awkward during a cold start before auth
/// state is even known yet.
class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  final _appLinks = AppLinks();
  final ValueNotifier<String?> pendingInviteCode = ValueNotifier(null);
  StreamSubscription<Uri>? _sub;

  Future<void> init() async {
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) _handle(initialUri);
    } catch (_) {
      // No initial link, or platform channel not ready yet - fine, the
      // stream subscription below still catches links tapped later.
    }

    _sub = _appLinks.uriLinkStream.listen(_handle, onError: (_) {});
  }

  void _handle(Uri uri) {
    final code = extractInviteCode(uri.toString());
    if (code != null && code.isNotEmpty) {
      pendingInviteCode.value = code;
    }
  }

  /// Call once a pending code has been used (or shown to the user and
  /// dismissed) so it doesn't get re-consumed on the next rebuild.
  void clearPending() => pendingInviteCode.value = null;

  void dispose() => _sub?.cancel();
}
