import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../models/models.dart';
import 'journal_api.dart';

const int maxImageBytes = 8 * 1024 * 1024;
const int maxAudioBytes = 25 * 1024 * 1024;

class MediaService {
  MediaService(this.api);

  final JournalApi api;
  final ImagePicker _picker = ImagePicker();
  AudioRecorder? _recorder;
  DateTime? _startedAt;
  String? _recordPath;

  bool get isRecording => _startedAt != null;

  Future<List<PendingAttachment>> pickImages({
    required String userId,
    String? tradeId,
  }) async {
    final files = await _picker.pickMultiImage(imageQuality: 85);
    if (files.isEmpty) return const [];

    // Validate every file before uploading any of them. Uploading as we go
    // leaves the earlier files in storage when a later one is rejected.
    final bytesList = <Uint8List>[];
    final mimeList = <String>[];
    for (final file in files) {
      final bytes = await file.readAsBytes();
      if (bytes.length > maxImageBytes) {
        throw Exception('${file.name} is larger than 8 MB.');
      }
      var mime = (file.mimeType ?? _imageMime(file.name))
          .split(';')
          .first
          .trim()
          .toLowerCase();
      // Some Android pickers report `image/jpg`; the bucket uses the
      // canonical `image/jpeg` name.
      if (mime == 'image/jpg') mime = 'image/jpeg';
      if (!_allowedImageMimes.contains(mime)) {
        throw Exception('${file.name} is not a JPEG, PNG, WebP or HEIC image.');
      }
      bytesList.add(bytes);
      mimeList.add(mime);
    }

    final uploaded = <PendingAttachment>[];
    try {
      for (var index = 0; index < files.length; index++) {
        uploaded.add(
          await api.uploadAttachment(
            userId: userId,
            tradeId: tradeId,
            bytes: bytesList[index],
            kind: 'image',
            fileName: files[index].name,
            mimeType: mimeList[index],
            previewBytes: bytesList[index],
          ),
        );
      }
    } catch (_) {
      // Do not leave a half-finished batch behind.
      for (final item in uploaded) {
        await api.removePending(item).catchError((_) {});
      }
      rethrow;
    }
    return uploaded;
  }

  static const _allowedImageMimes = {
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/heic',
    'image/heif',
  };

  Future<PendingAttachment?> takePhoto({
    required String userId,
    String? tradeId,
  }) async {
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (file == null) return null;

    final bytes = await file.readAsBytes();
    if (bytes.length > maxImageBytes) {
      throw Exception('That photo is larger than 8 MB.');
    }
    return api.uploadAttachment(
      userId: userId,
      tradeId: tradeId,
      bytes: bytes,
      kind: 'image',
      fileName: file.name,
      mimeType: _imageMime(file.name),
      previewBytes: bytes,
    );
  }

  Future<PendingAttachment?> pickAudioFile({
    required String userId,
    String? tradeId,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;

    final file = result.files.single;
    Uint8List? bytes = file.bytes;
    if (bytes == null && file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    }
    if (bytes == null) throw Exception('Could not read that audio file.');
    if (bytes.length > maxAudioBytes) {
      throw Exception('Audio files must be under 25 MB.');
    }

    return api.uploadAttachment(
      userId: userId,
      tradeId: tradeId,
      bytes: bytes,
      kind: 'audio',
      fileName: file.name,
      mimeType: _audioMime(file.name),
      durationSeconds: await _audioDuration(file.path),
    );
  }

  /// Reads a picked file's duration without uploading it. Returns null when
  /// the platform cannot decode the codec; the UI then shows `—`.
  Future<double?> _audioDuration(String? path) async {
    if (path == null) return null;
    final player = AudioPlayer();
    try {
      final duration = await player.setFilePath(path);
      if (duration == null) return null;
      return duration.inMilliseconds / Duration.millisecondsPerSecond;
    } catch (_) {
      return null;
    } finally {
      await player.dispose();
    }
  }

  Future<void> startRecording() async {
    _recorder ??= AudioRecorder();
    final granted = await _recorder!.hasPermission();
    if (!granted) {
      throw Exception(
        'Microphone access is required. Allow it in system settings and try again.',
      );
    }

    final directory = await getTemporaryDirectory();
    _recordPath =
        '${directory.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder!.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: _recordPath!,
    );
    _startedAt = DateTime.now();
  }

  Future<PendingAttachment> stopRecording({
    required String userId,
    String? tradeId,
  }) async {
    final startedAt = _startedAt;
    final path = await _recorder?.stop();
    _startedAt = null;

    if (path == null || startedAt == null) {
      throw Exception('Nothing was recorded.');
    }

    final file = File(path);
    final bytes = await file.readAsBytes();
    final duration = DateTime.now().difference(startedAt).inSeconds.toDouble();
    if (bytes.length > maxAudioBytes) {
      await file.delete().catchError((_) => file);
      throw Exception(
        'That recording is over 25 MB. Keep voice notes shorter.',
      );
    }

    try {
      return await api.uploadAttachment(
        userId: userId,
        tradeId: tradeId,
        bytes: bytes,
        kind: 'audio',
        fileName: path.split(Platform.pathSeparator).last,
        mimeType: 'audio/mp4',
        durationSeconds: duration,
      );
    } finally {
      // Do not leave the local recording behind when the upload fails.
      await file.delete().catchError((_) => file);
    }
  }

  Future<void> cancelRecording() async {
    try {
      await _recorder?.stop();
    } catch (_) {
      // Nothing was recording.
    }
    _startedAt = null;
    final path = _recordPath;
    _recordPath = null;
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  Future<void> dispose() async {
    await cancelRecording();
    await _recorder?.dispose();
    _recorder = null;
  }

  String _imageMime(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic')) return 'image/heic';
    if (lower.endsWith('.heif')) return 'image/heif';
    return 'image/jpeg';
  }

  String _audioMime(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.ogg')) return 'audio/ogg';
    if (lower.endsWith('.webm')) return 'audio/webm';
    if (lower.endsWith('.aac')) return 'audio/aac';
    return 'audio/mp4';
  }
}
