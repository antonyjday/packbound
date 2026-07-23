import 'package:cloud_firestore/cloud_firestore.dart';

/// One quick-message sent to the group (see quick_messages.dart for the
/// fixed preset list users pick from) - a fire-and-forget broadcast, not a
/// persistent chat thread: there's no read/edit/delete beyond the group's
/// own lifecycle (see GroupService.messagesStream, cleanupEndedGroupData).
/// Also doubles as a voice clip (push-to-talk) when [audioUrl] is set - see
/// VoiceMessageService - sharing the same feed/rules/alert-dialog/push
/// pipeline rather than a separate one.
class GroupMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String text;
  final Timestamp sentAt;
  final String? audioUrl;
  final int? audioDurationSeconds;

  bool get isVoice => audioUrl != null;

  GroupMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.sentAt,
    this.audioUrl,
    this.audioDurationSeconds,
  });

  factory GroupMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return GroupMessage(
      id: doc.id,
      senderId: data['senderId'] ?? '',
      senderName: data['senderName'] ?? 'Someone',
      text: data['text'] ?? '',
      sentAt: data['sentAt'] ?? Timestamp.now(),
      audioUrl: data['audioUrl'] as String?,
      audioDurationSeconds: (data['audioDurationSeconds'] as num?)?.toInt(),
    );
  }
}
