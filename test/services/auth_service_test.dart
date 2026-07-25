import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:convoy_app/services/auth_service.dart';

void main() {
  late FakeFirebaseFirestore db;
  late MockFirebaseAuth auth;
  late AuthService service;

  setUp(() {
    db = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(signedIn: false);
    service = AuthService(auth: auth, firestore: db);
  });

  test('uid/currentUser are null before signing in', () {
    expect(service.uid, isNull);
    expect(service.currentUser, isNull);
  });

  group('signInAnonymously', () {
    test('signs in and sets the display name on the Auth profile', () async {
      final user = await service.signInAnonymously('Alex');

      expect(user.displayName, 'Alex');
      expect(service.uid, user.uid);
      expect(service.currentUser?.uid, user.uid);
    });

    test('writes a matching users/{uid} Firestore doc', () async {
      final user = await service.signInAnonymously('Alex');

      final doc = await db.collection('users').doc(user.uid).get();
      expect(doc.data()?['displayName'], 'Alex');
      expect(doc.data()?['lastSeen'], isNotNull);
    });

    test('merges into an existing users/{uid} doc rather than replacing it', () async {
      // Known uid seeded via a fixed MockUser so the users/{uid} doc can be
      // pre-populated before signing in, same as a returning device whose
      // NotificationService already wrote an fcmToken for this uid.
      final fixedAuth = MockFirebaseAuth(
        signedIn: false,
        mockUser: MockUser(uid: 'known-uid', isAnonymous: true),
      );
      final fixedService = AuthService(auth: fixedAuth, firestore: db);
      await db.collection('users').doc('known-uid').set({'fcmToken': 'existing-token'});

      await fixedService.signInAnonymously('Alex');

      final doc = await db.collection('users').doc('known-uid').get();
      expect(doc.data()?['displayName'], 'Alex');
      // NotificationService's fcmToken write should survive sign-in.
      expect(doc.data()?['fcmToken'], 'existing-token');
    });
  });

  test('authStateChanges emits the signed-in user', () async {
    expect(service.authStateChanges, emitsInOrder([isNull, isNotNull]));
    await service.signInAnonymously('Alex');
  });

  test('signOut clears the current user', () async {
    await service.signInAnonymously('Alex');
    expect(service.uid, isNotNull);

    await service.signOut();

    expect(service.uid, isNull);
  });

  group('updateLastSeen', () {
    test('is a no-op when nobody is signed in', () async {
      await service.updateLastSeen();

      final docs = await db.collection('users').get();
      expect(docs.docs, isEmpty);
    });

    test('bumps lastSeen without touching other fields on the doc', () async {
      final user = await service.signInAnonymously('Alex');
      await db.collection('users').doc(user.uid).set(
        {'fcmToken': 'existing-token'},
        SetOptions(merge: true),
      );

      await service.updateLastSeen();

      final doc = await db.collection('users').doc(user.uid).get();
      expect(doc.data()?['displayName'], 'Alex');
      expect(doc.data()?['fcmToken'], 'existing-token');
      expect(doc.data()?['lastSeen'], isNotNull);
    });
  });
}
