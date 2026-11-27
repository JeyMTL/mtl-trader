import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/import_history.dart';
import '../core/import_parser.dart';
import '../l10n/gen/app_localizations.dart';
import '../services/journal_api.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'package:mtl_trader_mobile/core/friendly_error.dart';

/// Refuse absurd uploads before reading the whole file into memory.
const int _maxImportBytes = 20 * 1024 * 1024;

/// Import MT5 or broker trade history from the phone.
///
/// Same flow as the web desk: read the export on the device, show what was
/// found, then insert it. MT5's XML report, CSV/TSV text and `.xlsx` workbooks
/// are read here; legacy `.xls` is read by the same parser the web desk uses.
/// Past imports can be listed and removed again, and a journal can be cleared.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key, required this.api, this.onImported});

  final JournalApi api;

  /// Lets the shell reload the desk, journal and analytics after new rows land.
  final VoidCallback? onImported;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  AppLocalizations get _l10n => AppLocalizations.of(context);

  String? _fileName;
  List<ParsedTrade>? _trades;
  List<ImportRecord> _history = const [];
  bool _busy = false;
  String? _error;
  ImportOutcome? _outcome;

  int get _wins => _trades?.where((trade) => trade.pnl > 0).length ?? 0;
  int get _losses => _trades?.where((trade) => trade.pnl < 0).length ?? 0;
  double get _netPnl =>
      _trades?.fold<double>(0, (sum, trade) => sum + trade.pnl) ?? 0;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final history = await ImportHistoryStore.load();
    if (!mounted) return;
    setState(() => _history = history);
  }

  Future<void> _pickFile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'tsv', 'txt', 'xml', 'xlsx', 'xls'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;

    setState(() {
      _error = null;
      _outcome = null;
    });

    Uint8List? bytes = file.bytes;
    if (bytes == null && file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    }
    if (bytes == null) {
      setState(() => _error = _l10n.importUnreadableFile);
      return;
    }
    if (bytes.length > _maxImportBytes) {
      final size = (bytes.length / (1024 * 1024)).toStringAsFixed(1);
      setState(() => _error = _l10n.importFileTooLarge(size));
      return;
    }

    setState(() => _busy = true);
    try {
      var trades = <ParsedTrade>[];
      var read = false;
      try {
        final rows = parseFileRows(file.name, bytes);
        if (rows.isNotEmpty) {
          trades = extractTrades(rows);
          read = true;
        }
      } catch (_) {
        // Legacy .xls is an OLE container the phone's workbook reader cannot
        // open, so it goes to the server below.
      }
      if (!read) {
        // The route runs the web desk's own importer, so the file is read
        // exactly as it would be in the browser.
        trades = await widget.api.parseImportFile(
          fileName: file.name,
          bytes: bytes,
        );
      }
      setState(() {
        _busy = false;
        _fileName = file.name;
        _trades = trades;
        if (trades.isEmpty) _error = _l10n.importNoClosedTrades;
      });
    } catch (error) {
      setState(() {
        _busy = false;
        _error = _friendly(error, _l10n);
      });
    }
  }

  /// Parser exceptions read like stack traces; everything else here is a
  /// message written for the trader.
  String _friendly(Object error, AppLocalizations l10n) {
    final text = friendlyError(error);
    return text.startsWith('FormatException') ||
            text.startsWith('RangeError') ||
            text.startsWith('UnsupportedError')
        ? l10n.importNoReadableData
        : text;
  }

  Future<void> _import() async {
    final trades = _trades;
    if (trades == null || trades.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final outcome = await widget.api.importTrades(trades);
      final importId = outcome.importId;
      var history = _history;
      if (importId != null && outcome.imported > 0) {
        history = await ImportHistoryStore.add(
          ImportRecord(
            id: importId,
            filename: _fileName ?? _l10n.importUnknownFile,
            tradeCount: outcome.imported,
            timestamp: DateTime.now(),
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _outcome = outcome;
        _history = history;
      });
      if (outcome.imported > 0) widget.onImported?.call();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = friendlyError(error);
      });
    }
  }

  Future<void> _deleteImport(ImportRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_l10n.importDeleteTitle),
        content: Text(
          _l10n.importDeleteBody(record.tradeCount, record.filename),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(_l10n.keepAction),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(_l10n.deleteAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await widget.api.deleteImport(record.id);
      final history = await ImportHistoryStore.remove(record.id);
      if (!mounted) return;
      setState(() => _history = history);
      widget.onImported?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_l10n.importDeleted(record.tradeCount)),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = friendlyError(error),
      );
    }
  }

  void _reset() {
    setState(() {
      _fileName = null;
      _trades = null;
      _error = null;
      _outcome = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final outcome = _outcome;
    final trades = _trades;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(_l10n.importTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 32),
        children: [
          if (_error != null) ...[
            FlatCard(
              borderColor: AppColors.danger.withAlpha(80),
              child: Text(
                _error!,
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (outcome != null)
            _resultCard(outcome)
          else if (trades == null)
            _pickCard()
          else ...[
            _fileCard(trades),
            if (trades.isNotEmpty) ...[
              const SizedBox(height: 10),
              _previewCard(trades),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _busy ? null : _import,
                child: Text(
                  _busy ? _l10n.importImporting : _l10n.importAction(trades.length),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy ? null : _reset,
                child: Text(_l10n.cancel),
              ),
            ] else ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy ? null : _reset,
                child: Text(_l10n.importChooseAnother),
              ),
            ],
          ],
          const SizedBox(height: 16),
          _howToCard(),
          const SizedBox(height: 16),
          _historyCard(),
        ],
      ),
    );
  }

  Widget _pickCard() {
    return FlatCard(
      onTap: _busy ? null : _pickFile,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
      child: Column(
        children: [
          Icon(
            Icons.upload_file,
            size: 40,
            color: _busy ? AppColors.faint : AppColors.primary,
          ),
          const SizedBox(height: 12),
          Text(
            _busy ? _l10n.importReadingFile : _l10n.importChooseFile,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.text,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _l10n.importFileTypes,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.45),
          ),
          const SizedBox(height: 12),
          Text(
            _l10n.importSkippedNote,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.faint, fontSize: 11, height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _fileCard(List<ParsedTrade> trades) {
    return FlatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            title: _fileName ?? _l10n.importSelectedFile,
            subtitle: trades.isEmpty
                ? _l10n.importNoTradesFound
                : _l10n.importFileStats(trades.length, _wins, _losses),
            trailing: IconButton(
              tooltip: _l10n.importRemoveFile,
              onPressed: _busy ? null : _reset,
              icon: const Icon(Icons.close, size: 18),
            ),
          ),
          if (trades.isNotEmpty) ...[
            const ListDivider(),
            LabelValue(label: _l10n.importNetPnl, value: signedMoney(_netPnl)),
            LabelValue(label: _l10n.importDateRange, value: _dateRange(trades)),
          ],
        ],
      ),
    );
  }

  String _dateRange(List<ParsedTrade> trades) {
    final dates = trades
        .map((trade) => trade.closeDate.isNotEmpty ? trade.closeDate : trade.date)
        .where((value) => value.isNotEmpty)
        .toList()
      ..sort();
    if (dates.isEmpty) return '—';
    final first = DateTime.tryParse(dates.first);
    final last = DateTime.tryParse(dates.last);
    if (first == null || last == null) return '—';
    return '${dayOf(first)} → ${dayOf(last)}';
  }

  Widget _previewCard(List<ParsedTrade> trades) {
    final preview = trades.take(5).toList();
    return FlatCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            title: _l10n.importPreview,
            subtitle: _l10n.importPreviewSub(preview.length, trades.length),
          ),
          const SizedBox(height: 4),
          for (final trade in preview) ...[
            const ListDivider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          trade.symbol,
                          style: TextStyle(
                            color: AppColors.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          _l10n.importPreviewLine(trade.type, '${trade.lot}'),
                          style: TextStyle(
                            color: AppColors.faint,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    signedMoney(trade.pnl),
                    style: tabular.copyWith(
                      color: trade.pnl >= 0
                          ? AppColors.success
                          : AppColors.danger,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _resultCard(ImportOutcome outcome) {
    final nothingNew = outcome.imported == 0;
    return FlatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                nothingNew ? Icons.info_outline : Icons.check_circle,
                size: 20,
                color: nothingNew ? AppColors.muted : AppColors.success,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  nothingNew ? _l10n.importNothingNew : _l10n.importComplete,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            nothingNew
                ? _l10n.importAlreadyInJournal(outcome.skipped)
                : [
                    _l10n.importAdded(outcome.imported),
                    if (outcome.skipped > 0)
                      _l10n.importDuplicatesSkipped(outcome.skipped),
                  ].join(' '),
            style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.45),
          ),
          if (outcome.notice != null) ...[
            const SizedBox(height: 8),
            Text(
              outcome.notice!,
              style:
                  TextStyle(color: AppColors.danger, fontSize: 11.5, height: 1.45),
            ),
          ],
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(outcome.imported > 0),
            child: Text(_l10n.doneAction),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _reset,
            child: Text(_l10n.importAnother),
          ),
        ],
      ),
    );
  }

  /// Clears every trade and the import list, like the web desk's Clear Journal.
  Future<void> _clearJournal() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_l10n.clearJournalTitle),
        content: Text(_l10n.importClearBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(_l10n.keepAction),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(_l10n.importClearAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final userId = widget.api.userId;
    if (userId == null) return;
    setState(() => _busy = true);
    try {
      await widget.api.clearTrades(userId);
      final history = await ImportHistoryStore.clear();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _history = history;
        _outcome = null;
      });
      widget.onImported?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_l10n.importJournalCleared)),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _friendly(error, _l10n);
      });
    }
  }

  String _timeOf(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  Widget _historyCard() {
    return FlatCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            title: _l10n.importHistoryTitle,
            subtitle: _l10n.importHistorySub,
            trailing: _history.isEmpty
                ? null
                : TextButton(
                    onPressed: _busy ? null : _clearJournal,
                    child: Text(_l10n.importClearAction),
                  ),
          ),
          if (_history.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _l10n.importHistoryEmpty,
                style: TextStyle(color: AppColors.faint, fontSize: 12),
              ),
            ),
          const SizedBox(height: 2),
          for (final record in _history) ...[
            const ListDivider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.history, size: 16, color: AppColors.faint),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          record.filename,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.text,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          _l10n.importHistoryLine(
                            record.tradeCount,
                            '${dayOf(record.timestamp)} '
                                '${_timeOf(record.timestamp)}',
                          ),
                          style: TextStyle(
                            color: AppColors.faint,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: _l10n.importDeleteTooltip,
                    onPressed: _busy ? null : () => _deleteImport(record),
                    icon: const Icon(Icons.delete_outline, size: 18),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _howToCard() {
    return FlatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(title: _l10n.importHowToTitle),
          const SizedBox(height: 10),
          Text(
            _l10n.importHowToSteps,
            style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.6),
          ),
          const SizedBox(height: 12),
          Text(
            _l10n.importNetNote,
            style: TextStyle(color: AppColors.faint, fontSize: 11, height: 1.5),
          ),
        ],
      ),
    );
  }
}
