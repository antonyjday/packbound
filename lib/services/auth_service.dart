import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Handles user identity. Anonymous auth is enough for a convoy app -
/// no email/password friction needed, but each device gets a stable uid.
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  String? get uid => _auth.currentUser?.uid;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<User> signInAnonymously(String displayName) async {
    final result = await _auth.signInAnonymously();
    final user = result.user!;

    // Also set this on the Auth profile itself (not just the Firestore
    // users doc) - map markers and the member roster read
    // currentUser?.displayName, not the Firestore doc, when labeling "me".
    await user.updateDisplayName(displayName);
    await user.reload();

    await _db.collection('users').doc(user.uid).set({
      'displayName': displayName,
      'lastSeen': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return _auth.currentUser!;
  }

  Future<void> signOut() => _auth.signOut();
}
