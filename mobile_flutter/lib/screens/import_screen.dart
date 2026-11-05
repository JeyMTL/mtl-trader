import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/import_history.dart';
import '../core/import_parser.dart';
import '../services/journal_api.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

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
      setState(() => _error = 'Could not read that file. Try picking it again.');
      return;
    }
    if (bytes.length > _maxImportBytes) {
      final size = (bytes.length / (1024 * 1024)).toStringAsFixed(1);
      setState(() {
        _error =
            'That file is $size MB. Imports are limited to 20 MB — split the '
            'report and import it in parts.';
      });
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
        if (trades.isEmpty) {
          _error =
              'No closed trades were found. Make sure the file is an MT5 or '
              'broker history export — open positions are skipped.';
        }
      });
    } catch (error) {
      setState(() {
        _busy = false;
        _error = _friendly(error);
      });
    }
  }

  /// Parser exceptions read like stack traces; everything else here is a
  /// message written for the trader.
  String _friendly(Object error) {
    final text = error.toString().replaceFirst('Exception: ', '');
    return text.startsWith('FormatException') ||
            text.startsWith('RangeError') ||
            text.startsWith('UnsupportedError')
        ? 'No readable data in this file. Export it as CSV from MT5 or your '
            'broker and try again.'
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
            filename: _fileName ?? 'Unknown',
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
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _deleteImport(ImportRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this import?'),
        content: Text(
          '${record.tradeCount} ${record.tradeCount == 1 ? 'trade' : 'trades'} '
          'from ${record.filename} will be removed from your journal. This '
          'cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
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
          content: Text(
            'Deleted ${record.tradeCount} imported '
            '${record.tradeCount == 1 ? 'trade' : 'trades'}.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error.toString().replaceFirst('Exception: ', ''),
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
      appBar: AppBar(title: const Text('Import trades')),
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
                  _busy ? 'Importing…' : 'Import ${trades.length} trades',
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy ? null : _reset,
                child: const Text('Cancel'),
              ),
            ] else ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy ? null : _reset,
                child: const Text('Choose another file'),
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
            _busy ? 'Reading file…' : 'Choose a trade history file',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.text,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'MT5 XML report, CSV, TSV, an Excel .xlsx/.xls export, or a broker '
            'CSV.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.45),
          ),
          const SizedBox(height: 12),
          Text(
            'Already-imported tickets are skipped, so importing the same '
            'statement twice does not double your journal.',
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
            title: _fileName ?? 'Selected file',
            subtitle: trades.isEmpty
                ? '0 closed trades found'
                : '${trades.length} trades · $_wins wins · $_losses losses',
            trailing: IconButton(
              tooltip: 'Remove file',
              onPressed: _busy ? null : _reset,
              icon: const Icon(Icons.close, size: 18),
            ),
          ),
          if (trades.isNotEmpty) ...[
            const ListDivider(),
            LabelValue(label: 'Net P&L', value: signedMoney(_netPnl)),
            LabelValue(label: 'Date range', value: _dateRange(trades)),
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
            title: 'Preview',
            subtitle: 'First ${preview.length} of ${trades.length}',
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
                          '${trade.type} · ${trade.lot} lots',
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
                  nothingNew ? 'Nothing new to import' : 'Import complete',
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
                ? '${outcome.skipped} ${outcome.skipped == 1 ? 'trade is' : 'trades are'} already in your journal.'
                : '${outcome.imported} ${outcome.imported == 1 ? 'trade' : 'trades'} added to your journal.'
                    '${outcome.skipped > 0 ? ' ${outcome.skipped} duplicate${outcome.skipped == 1 ? '' : 's'} skipped.' : ''}',
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
            child: const Text('Done'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _reset,
            child: const Text('Import another file'),
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
        title: const Text('Clear the journal?'),
        content: const Text(
          'Every trade — imported or logged by hand — will be deleted. This '
          'cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear journal'),
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
        const SnackBar(content: Text('Journal cleared.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _friendly(error);
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
            title: 'Import history',
            subtitle: 'Statements imported from this device.',
            trailing: _history.isEmpty
                ? null
                : TextButton(
                    onPressed: _busy ? null : _clearJournal,
                    child: const Text('Clear journal'),
                  ),
          ),
          if (_history.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'No imports yet.',
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
                          '${record.tradeCount} '
                          '${record.tradeCount == 1 ? 'trade' : 'trades'} · '
                          '${dayOf(record.timestamp)} '
                          '${_timeOf(record.timestamp)}',
                          style: TextStyle(
                            color: AppColors.faint,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Delete this import',
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
          const SectionTitle(title: 'How to export from MT5'),
          const SizedBox(height: 10),
          Text(
            '1. Open MetaTrader 5 → History tab.\n'
            '2. Right-click → All History, then select the trades.\n'
            '3. Right-click → Report / Export and save as CSV or the XML '
            'report (ReportHistory files).\n'
            '4. Pick that file above.',
            style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.6),
          ),
          const SizedBox(height: 12),
          Text(
            'P&L is stored net: MT5 profit plus commission and swap. Excel '
            '.xlsx and .xls exports work too — .xls up to 4 MB is read on our '
            'server, so larger ones should be saved as .xlsx or CSV.',
            style: TextStyle(color: AppColors.faint, fontSize: 11, height: 1.5),
          ),
        ],
      ),
    );
  }
}
