import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// One finished voice note, ready to be sent as a data URL.
class VoiceClip {
  const VoiceClip({
    required this.bytes,
    required this.mimeType,
    required this.seconds,
  });

  final Uint8List bytes;

  /// `audio/mp4` — the transcribe route accepts AAC in an MP4 container.
  final String mimeType;

  final double seconds;
}

/// Records a short voice note for the custom backtest compiler.
///
/// Unlike the journal's recorder this one keeps the clip in memory and deletes
/// the temporary file: the recording is never stored, it is transcribed into the
/// description and thrown away.
class VoiceClipRecorder {
  final AudioRecorder _recorder = AudioRecorder();

  DateTime? _startedAt;
  String? _path;

  bool get isRecording => _startedAt != null;

  /// Starts an AAC recording. Throws a sentence meant for the trader when the
  /// microphone is denied or the recorder cannot open a file.
  Future<void> start() async {
    if (_startedAt != null) return;
    final granted = await _recorder.hasPermission();
    if (!granted) {
      throw Exception(
        'Microphone access was blocked. Allow it in system settings, or type '
        'the explanation instead.',
      );
    }
    final directory = await getTemporaryDirectory();
    final path =
        '${directory.path}/backtest_clip_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: path,
    );
    _path = path;
    _startedAt = DateTime.now();
  }

  /// Stops and returns the clip, or null when nothing was recorded.
  Future<VoiceClip?> stop() async {
    final startedAt = _startedAt;
    final path = _path;
    _startedAt = null;
    _path = null;
    if (startedAt == null) return null;

    String? stopped;
    try {
      stopped = await _recorder.stop();
    } catch (_) {
      stopped = path;
    }
    final filePath = stopped ?? path;
    if (filePath == null) return null;

    final file = File(filePath);
    try {
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      return VoiceClip(
        bytes: bytes,
        mimeType: 'audio/mp4',
        seconds: DateTime.now().difference(startedAt).inMilliseconds / 1000,
      );
    } finally {
      await file.delete().catchError((_) => file);
    }
  }

  /// Stops without returning anything and removes the temporary file.
  Future<void> cancel() async {
    _startedAt = null;
    final path = _path;
    _path = null;
    try {
      await _recorder.stop();
    } catch (_) {
      // Nothing was recording.
    }
    if (path != null) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> dispose() async {
    await cancel();
    try {
      await _recorder.dispose();
    } catch (_) {
      // The plugin is absent in widget tests; there is nothing to release.
    }
  }
}
