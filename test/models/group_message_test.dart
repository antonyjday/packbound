import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:convoy_app/models/group_message.dart';

void main() {
  Future<GroupMessage> writeAndRead(Map<String, dynamic> data) async {
    final db = FakeFirebaseFirestore();
    final ref = db.collection('messages').doc('msg1');
    await ref.set(data);
    return GroupMessage.fromDoc(await ref.get());
  }

  group('GroupMessage.isVoice', () {
    test('is false for a plain quick message with no audioUrl', () async {
      final message = await writeAndRead({
        'senderId': 'user1',
        'senderName': 'Alex',
        'text': 'Pulling over',
        'sentAt': Timestamp.now(),
      });
      expect(message.isVoice, false);
    });

    test('is true once audioUrl is set', () async {
      final message = await writeAndRead({
        'senderId': 'user1',
        'senderName': 'Alex',
        'text': '',
        'sentAt': Timestamp.now(),
        'audioUrl': 'https://example.com/clip.m4a',
        'audioDurationSeconds': 4,
      });
      expect(message.isVoice, true);
      expect(message.audioUrl, 'https://example.com/clip.m4a');
      expect(message.audioDurationSeconds, 4);
    });
  });

  group('GroupMessage.fromDoc', () {
    test('defaults senderName to "Someone" when missing', () async {
      final message = await writeAndRead({
        'senderId': 'user1',
        'text': 'All good',
        'sentAt': Timestamp.now(),
      });
      expect(message.senderName, 'Someone');
    });

    test('defaults text to empty string when missing', () async {
      final message = await writeAndRead({
        'senderId': 'user1',
        'senderName': 'Alex',
        'sentAt': Timestamp.now(),
      });
      expect(message.text, '');
    });
  });
}
