import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

/// Recording and upload half of push-to-talk voice messages - the Firestore
/// doc itself (senderId/audioUrl/audioDurationSeconds) is written by
/// GroupService.sendVoiceMessage once [stopAndUpload] returns, sharing the
/// same `messages` feed/rules/alert-dialog/push pipeline quick messages
/// already use (see GroupMessage.isVoice).
class VoiceMessageService {
  final _recorder = AudioRecorder();
  final _storage = FirebaseStorage.instance;
  DateTime? _recordingStartedAt;
  String? _recordingPath;

  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Caps how long a single clip can run - a push-to-talk clip is meant to
  /// be a short burst, not a recording app; also keeps Storage/bandwidth
  /// use trivially small (see storage.rules' 5MB cap on top of this).
  static const maxDuration = Duration(seconds: 30);

  Future<void> startRecording() async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/${const Uuid().v4()}.m4a';
    await _recorder.start(const RecordConfig(), path: path);
    _recordingStartedAt = DateTime.now();
    _recordingPath = path;
  }

  /// Stops the in-progress recording, uploads it to
  /// `groups/{groupId}/voice/`, and returns the download URL plus the
  /// clip's actual duration - or null if the recording was too short to be
  /// a real message (e.g. an accidental tap-and-release).
  Future<({String url, int durationSeconds})?> stopAndUpload(String groupId) async {
    final path = await _recorder.stop();
    final startedAt = _recordingStartedAt;
    _recordingStartedAt = null;
    _recordingPath = null;
    if (path == null || startedAt == null) return null;

    final duration = DateTime.now().difference(startedAt);
    if (duration.inMilliseconds < 500) {
      await _deleteQuietly(path);
      return null;
    }

    final durationSeconds = duration.inSeconds.clamp(1, maxDuration.inSeconds);
    final ref = _storage.ref('groups/$groupId/voice/${const Uuid().v4()}.m4a');
    // Timeouts as a safety net - a stuck upload should surface as an error
    // the sender can retry, not hang the push-to-talk button forever.
    await ref
        .putFile(File(path), SettableMetadata(contentType: 'audio/mp4'))
        .timeout(const Duration(seconds: 20));
    final url = await ref.getDownloadURL().timeout(const Duration(seconds: 20));
    await _deleteQuietly(path);
    return (url: url, durationSeconds: durationSeconds);
  }

  /// Discards an in-progress recording without uploading - e.g. the user
  /// dragged off the button to cancel, same gesture WhatsApp/Telegram use.
  Future<void> cancelRecording() async {
    final path = await _recorder.stop();
    _recordingStartedAt = null;
    _recordingPath = null;
    if (path != null) await _deleteQuietly(path);
  }

  Future<void> _deleteQuietly(String path) async {
    try {
      await File(path).delete();
    } catch (_) {
      // Best-effort cleanup of a temp file - a leftover recording in the
      // temp dir is harmless, not worth surfacing.
    }
  }

  bool get isRecording => _recordingPath != null;

  void dispose() {
    _recorder.dispose();
  }
}
