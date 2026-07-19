import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// Registers this device for push notifications (trip-expiry warnings sent
/// by the `warnExpiringGroups` Cloud Function) by keeping
/// `users/{uid}.fcmToken` current.
///
/// Deliberately does nothing with foreground messages or notification taps:
/// the in-app expiry banner (MapScreen) already covers the "app is open"
/// case, and a `notification`-payload FCM message is auto-displayed by
/// Android (and opens the app on tap) whenever it's backgrounded or
/// terminated, with zero extra code needed here.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _messaging = FirebaseMessaging.instance;
  StreamSubscription<User?>? _authSub;
  StreamSubscription<String>? _tokenSub;

  Future<void> init() async {
    try {
      await _messaging.requestPermission();
    } catch (_) {
      // Permission prompt unavailable/denied (or, on a platform without
      // messaging configured, e.g. iOS pre-APNs-setup) - push just won't
      // arrive; nothing else in the app depends on this succeeding.
    }

    _tokenSub = _messaging.onTokenRefresh.listen(_saveToken);

    // Covers both a fresh sign-in and an already-authenticated relaunch -
    // either way, make sure Firestore has this device's current token.
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) _syncCurrentToken();
    });
  }

  Future<void> _syncCurrentToken() async {
    try {
      final token = await _messaging.getToken();
      if (token != null) await _saveToken(token);
    } catch (_) {
      // Best-effort, same reasoning as requestPermission() above.
    }
  }

  Future<void> _saveToken(String token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance.collection('users').doc(uid).set(
      {'fcmToken': token},
      SetOptions(merge: true),
    );
  }

  void dispose() {
    _authSub?.cancel();
    _tokenSub?.cancel();
  }
}
