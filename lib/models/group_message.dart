import 'package:cloud_firestore/cloud_firestore.dart';

/// One quick-message sent to the group (see quick_messages.dart for the
/// fixed preset list users pick from) - a fire-and-forget broadcast, not a
/// persistent chat thread: there's no read/edit/delete beyond the group's
/// own lifecycle (see GroupService.messagesStream, cleanupEndedGroupData).
class GroupMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String text;
  final Timestamp sentAt;

  GroupMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.sentAt,
  });

  factory GroupMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return GroupMessage(
      id: doc.id,
      senderId: data['senderId'] ?? '',
      senderName: data['senderName'] ?? 'Someone',
      text: data['text'] ?? '',
      sentAt: data['sentAt'] ?? Timestamp.now(),
    );
  }
}
