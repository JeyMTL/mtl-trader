import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/compile_attachments.dart';
import '../services/backtest_api.dart';
import '../services/voice_clip_recorder.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// Timeframes the compiler and the engine both understand.
const List<String> _timeframes = ['M1', 'M5', 'M15', 'M30', 'H1', 'H4', 'D1', 'W1'];

int? _minutes(String timeframe) {
  final match = RegExp(r'^(M|H|D|W)(\d+)$').firstMatch(timeframe);
  if (match == null) return null;
  final width = int.tryParse(match.group(2)!) ?? 0;
  switch (match.group(1)) {
    case 'M':
      return width;
    case 'H':
      return width * 60;
    case 'D':
      return width * 1440;
    default:
      return width * 10080;
  }
}

/// A higher timeframe is built by grouping whole primary bars, so only ratios
/// that divide evenly (and are at least two bars) are offered.
bool _groupsWholeBars(String primary, String candidate) {
  final fast = _minutes(primary);
  final slow = _minutes(candidate);
  if (fast == null || slow == null || slow <= fast) return false;
  final ratio = slow / fast;
  return ratio == ratio.roundToDouble() && ratio >= 2 && ratio <= 2000;
}

List<String> _higherTimeframesFor(String primary) => [
      for (final candidate in _timeframes)
        if (_groupsWholeBars(primary, candidate)) candidate,
    ];

/// The phone's "Custom backtest": describe a setup, attach the chart it came
/// from, let the server compile it into rules, check those rules in plain
/// English, then run them in the workbench.
///
/// Charts and the written description go to the model together, the same way the
/// web workbench sends them. A voice note is different: it is transcribed into
/// the description as text the trader can correct, so a misheard "break of
/// structure" is fixable before a single rule is compiled, and the recording
/// itself is never stored.
class CustomBacktestScreen extends StatefulWidget {
  const CustomBacktestScreen({super.key, this.api, this.symbol, this.timeframe});

  final BacktestApi? api;
  final String? symbol;
  final String? timeframe;

  @override
  State<CustomBacktestScreen> createState() => _CustomBacktestScreenState();
}

class _CustomBacktestScreenState extends State<CustomBacktestScreen> {
  late final BacktestApi _api = widget.api ?? BacktestApi();

  late final TextEditingController _description = TextEditingController();
  late final TextEditingController _symbol =
      TextEditingController(text: widget.symbol ?? '');
  late final TextEditingController _stop = TextEditingController();
  late final TextEditingController _criteria = TextEditingController();

  final ImagePicker _picker = ImagePicker();
  final VoiceClipRecorder _voice = VoiceClipRecorder();
  final List<CompileChart> _charts = [];
  Timer? _recordTimer;
  int _recordSeconds = 0;
  bool _recording = false;
  bool _transcribing = false;
  int _sentCharts = 0;

  late String _timeframe = _timeframes.contains(widget.timeframe)
      ? widget.timeframe!
      : 'M15';
  String _higher = '';

  bool _busy = false;
  String? _error;
  CompiledBacktest? _compiled;

  @override
  void dispose() {
    _recordTimer?.cancel();
    unawaited(_voice.dispose());
    _description.dispose();
    _symbol.dispose();
    _stop.dispose();
    _criteria.dispose();
    super.dispose();
  }

  String _mimeFor(XFile file) {
    final reported =
        (file.mimeType ?? '').split(';').first.trim().toLowerCase();
    if (reported == 'image/jpg') return 'image/jpeg';
    if (reported.startsWith('image/')) return reported;
    final name = file.name.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    if (name.endsWith('.heic')) return 'image/heic';
    if (name.endsWith('.heif')) return 'image/heif';
    return 'image/jpeg';
  }

  /// Picks screenshots from the gallery, validating every one before adding it.
  ///
  /// The limits are the server's: four charts, 4 MB each, and a 3 MB budget for
  /// the set once decoded. Stopping at the first problem (instead of silently
  /// dropping a chart) means the rules are never compiled from less than the
  /// trader attached.
  Future<void> _addCharts() async {
    if (_busy || _transcribing) return;
    setState(() => _error = null);

    List<XFile> files;
    try {
      files = await _picker.pickMultiImage(imageQuality: 70, maxWidth: 1600);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not open the gallery. Check the photo '
              'permission and try again.',
        );
      }
      return;
    }
    if (files.isEmpty) return;

    final next = [..._charts];
    var used = next.fold<int>(0, (sum, chart) => sum + chart.size);
    String? problem;

    for (final file in files) {
      int bytesLength;
      try {
        final bytes = await file.readAsBytes();
        bytesLength = bytes.length;
        final mime = _mimeFor(file);
        final rejection = chartRejection(
          count: next.length,
          usedBytes: used,
          candidateBytes: bytesLength,
          mimeType: mime,
        );
        if (rejection != null) {
          problem = rejection;
          break;
        }
        final dataUrl = chartDataUrl(mime, bytes);
        if (dataUrl == null) {
          problem = 'Use a PNG, JPEG or WebP screenshot.';
          break;
        }
        next.add(
          CompileChart(
            name: file.name,
            mimeType: mime,
            bytes: bytes,
            dataUrl: dataUrl,
          ),
        );
        used += bytes.length;
      } catch (_) {
        problem = 'Could not read ${file.name}. Try picking it again.';
        break;
      }
    }

    if (!mounted) return;
    setState(() {
      _charts
        ..clear()
        ..addAll(next);
      if (problem != null) _error = problem;
    });
  }

  void _removeChart(int index) {
    setState(() => _charts.removeAt(index));
  }

  /// Starts or stops the voice note. A recording is capped at a minute, the same
  /// ceiling the web recorder and the transcribe route use.
  Future<void> _toggleRecording() async {
    if (_busy || _transcribing) return;
    if (_recording) {
      await _stopRecording();
      return;
    }

    setState(() {
      _error = null;
      _recording = true;
      _recordSeconds = 0;
    });
    try {
      await _voice.start();
      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() => _recordSeconds++);
        if (_recordSeconds >= 60) unawaited(_stopRecording());
      });
    } catch (error) {
      _recordTimer?.cancel();
      _recordTimer = null;
      if (!mounted) return;
      setState(() {
        _recording = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
      await _voice.cancel();
    }
  }

  Future<void> _stopRecording() async {
    _recordTimer?.cancel();
    _recordTimer = null;
    if (!_recording) return;
    setState(() {
      _recording = false;
      _transcribing = true;
      _error = null;
    });

    try {
      final clip = await _voice.stop();
      if (clip == null) {
        if (mounted) {
          setState(
            () => _error = 'Nothing was recorded. Hold on, speak, then stop.',
          );
        }
        return;
      }
      final transcript = await _api.transcribe(
        audioDataUrl(clip.mimeType, clip.bytes),
      );
      if (!mounted) return;

      // The transcript joins the description as editable text, not as a hidden
      // attachment: a misheard term has to be fixable before compiling.
      final existing = _description.text.trim();
      final combined =
          existing.isEmpty ? transcript : '$existing\n\n$transcript';
      final capped =
          combined.length > 4000 ? combined.substring(0, 4000) : combined;
      _description.value = TextEditingValue(
        text: capped,
        selection: TextSelection.collapsed(offset: capped.length),
      );
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voice note added to the description.')),
      );
    } on BacktestApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not use that recording. Type the explanation '
              'instead.',
        );
      }
    } finally {
      if (mounted) setState(() => _transcribing = false);
    }
  }

  Future<void> _compile() async {
    if (_busy) return;
    final description = _description.text.trim();
    if (description.length < 20) {
      setState(
        () => _error =
            'Describe the setup in at least a sentence — what has to happen '
            'before you take the trade?',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _compiled = null;
    });
    try {
      final compiled = await _api.compile(
        description: description,
        timeframe: _timeframe,
        higherTimeframe: _higher,
        stopLoss: _stop.text,
        symbol: _symbol.text,
        criteria: _criteria.text,
        images: [for (final chart in _charts) chart.dataUrl],
      );
      if (!mounted) return;
      setState(() {
        _compiled = compiled;
        // Remember what was sent, so removing a chart afterwards does not
        // rewrite the history of this result.
        _sentCharts = _charts.length;
      });
    } on BacktestApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'The description could not be compiled. Check your '
              'connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final compiled = _compiled;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Custom backtest')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 28),
        children: [
          Text(
            'Write the setup in your own words. The server turns it into a '
            'rule set, shows you the rules in plain English, and only then can '
            'you run them over your bar data.',
            style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 12),
          FlatCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '1. The setup',
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _description,
                  minLines: 4,
                  maxLines: 8,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText:
                        'e.g. Wait for the London open, then buy when price '
                        'closes above the previous 20-bar high and the 200 EMA '
                        'is rising. Exit at 2R or when the 20 high is lost.',
                  ),
                ),
                _attachmentsBlock(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _timeframeField()),
                    const SizedBox(width: 8),
                    Expanded(child: _higherField()),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _plainField('Symbol (optional)', _symbol)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _plainField('Stop rule (optional)', _stop),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _plainField(
                  'Your definition of a valid setup (optional)',
                  _criteria,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: AppColors.danger,
                      fontSize: 11.5,
                      height: 1.45,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _busy ? null : _compile,
                    icon: _busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_fix_high, size: 17),
                    label: Text(
                      _busy ? 'Compiling rules…' : 'Compile rules',
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (compiled != null) ...[
            const SizedBox(height: 12),
            FlatCard(
              borderColor: AppColors.primary.withAlpha(80),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    compiled.name,
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${compiled.timeframe} · '
                    '${_sentCharts == 0 ? 'no charts sent' : '$_sentCharts chart${_sentCharts == 1 ? '' : 's'} sent'}'
                    ' · check every line before you run it',
                    style: TextStyle(
                      color: AppColors.faint,
                      fontSize: kMinLabelSize,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final rule in compiled.rules)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Icon(
                              Icons.chevron_right,
                              size: 14,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              rule,
                              style: TextStyle(
                                color: AppColors.muted,
                                fontSize: 11.5,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (compiled.disclaimer.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      compiled.disclaimer,
                      style: TextStyle(
                        color: AppColors.faint,
                        fontSize: kMinLabelSize,
                        height: 1.45,
                      ),
                    ),
                  ],
                  if (compiled.model != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Compiled with ${compiled.model}',
                      style: TextStyle(
                        color: AppColors.faint,
                        fontSize: kMinLabelSize,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, compiled),
                      child: const Text('Use these rules'),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: _busy ? null : _compile,
                    child: const Text('Compile again'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Charts and the voice note, directly under the description they explain.
  Widget _attachmentsBlock() {
    final busy = _busy || _transcribing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            OutlinedButton.icon(
              onPressed: busy ? null : _addCharts,
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 15),
              label: Text(
                _charts.isEmpty
                    ? 'Add chart'
                    : 'Add chart (${_charts.length}/$maxCompileCharts)',
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 38),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
            ),
            OutlinedButton.icon(
              onPressed: busy && !_recording ? null : _toggleRecording,
              icon: Icon(
                _recording ? Icons.stop : Icons.mic_none,
                size: 15,
                color: _recording ? AppColors.danger : null,
              ),
              label: Text(
                _recording
                    ? 'Stop · ${_recordSeconds}s'
                    : _transcribing
                        ? 'Transcribing…'
                        : 'Voice note',
                style: TextStyle(
                  color: _recording ? AppColors.danger : null,
                ),
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 38),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                side: BorderSide(
                  color: _recording ? AppColors.danger : AppColors.borderStrong,
                ),
              ),
            ),
          ],
        ),
        if (_charts.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var index = 0; index < _charts.length; index++)
                _chartThumb(index),
            ],
          ),
        ],
        const SizedBox(height: 4),
        Text(
          'Up to $maxCompileCharts chart screenshots and a 60-second voice '
          'note. The charts are sent to the model with the description; the '
          'note is transcribed into the description and never stored.',
          style: TextStyle(
            color: AppColors.faint,
            fontSize: kMinLabelSize,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _chartThumb(int index) {
    final chart = _charts[index];
    return SizedBox(
      width: 76,
      height: 64,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.memory(
              chart.bytes,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: AppColors.surfaceAlt,
                alignment: Alignment.center,
                child: Icon(
                  Icons.broken_image_outlined,
                  size: 16,
                  color: AppColors.faint,
                ),
              ),
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: InkWell(
              onTap: _busy ? null : () => _removeChart(index),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: AppColors.background.withAlpha(200),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Icon(Icons.close, size: 11, color: AppColors.text),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timeframeField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Timeframe',
          style: TextStyle(color: AppColors.faint, fontSize: 11),
        ),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: _timeframe,
          isExpanded: true,
          dropdownColor: AppColors.surfaceAlt,
          style: TextStyle(color: AppColors.text, fontSize: 13),
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          ),
          items: [
            for (final value in _timeframes)
              DropdownMenuItem(value: value, child: Text(value)),
          ],
          onChanged: _busy
              ? null
              : (value) {
                  if (value == null) return;
                  setState(() {
                    _timeframe = value;
                    // The old confirmation may no longer divide the new bars.
                    if (!_higherTimeframesFor(value).contains(_higher)) {
                      _higher = '';
                    }
                  });
                },
        ),
      ],
    );
  }

  Widget _higherField() {
    final options = _higherTimeframesFor(_timeframe);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Confirmation (optional)',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AppColors.faint, fontSize: 11),
        ),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: _higher.isEmpty ? '' : _higher,
          isExpanded: true,
          dropdownColor: AppColors.surfaceAlt,
          style: TextStyle(color: AppColors.text, fontSize: 13),
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          ),
          items: [
            const DropdownMenuItem(value: '', child: Text('None')),
            for (final value in options)
              DropdownMenuItem(value: value, child: Text(value)),
          ],
          onChanged: _busy
              ? null
              : (value) => setState(() => _higher = value ?? ''),
        ),
      ],
    );
  }

  Widget _plainField(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AppColors.faint, fontSize: 11),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          style: TextStyle(color: AppColors.text, fontSize: 12.5),
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          ),
        ),
      ],
    );
  }
}
