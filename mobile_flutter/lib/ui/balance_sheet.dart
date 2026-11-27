import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/gen/app_localizations.dart';
import '../services/journal_api.dart';
import 'theme.dart';

/// The one place the account balance is set from the phone.
///
/// The desk reads the balance as the logged deposits plus the journal's profit
/// and loss, so a balance that can be topped up whenever a month goes badly
/// stops measuring anything: every losing run can be reset with another
/// deposit. The database accepts one change a calendar month, and the sheet
/// says so before a number is typed — with the date the next one opens — rather
/// than failing the save afterwards with a policy error.
///
/// Returns true when a change was stored, so the caller can refresh the desk.
Future<bool?> showBalanceSheet(BuildContext context, JournalApi api) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
    ),
    builder: (_) => _BalanceSheet(api: api),
  );
}

class _BalanceSheet extends StatefulWidget {
  const _BalanceSheet({required this.api});

  final JournalApi api;

  @override
  State<_BalanceSheet> createState() => _BalanceSheetState();
}

class _BalanceSheetState extends State<_BalanceSheet> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _note = TextEditingController();

  DateTime? _lastChange;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final last = await widget.api.lastBalanceChange();
      if (!mounted) return;
      setState(() {
        _lastChange = last;
        _loading = false;
      });
    } catch (_) {
      // A read that fails leaves the change available: the policy is still the
      // authority, and a customer with a working month should not be blocked by
      // one failed query.
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  /// The month the policy compares against, in UTC.
  ///
  /// `created_at` is stored against the database clock and the rule is a UTC
  /// calendar month, so a phone in UTC+13 must not be told a change is
  /// available while the insert is refused.
  DateTime get _thisMonth {
    final now = DateTime.now().toUtc();
    return DateTime.utc(now.year, now.month);
  }

  DateTime get _nextChange =>
      DateTime.utc(_thisMonth.year, _thisMonth.month + 1);

  bool get _usedThisMonth =>
      _lastChange != null && !_lastChange!.isBefore(_thisMonth);

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final amount = double.tryParse(_amount.text.trim().replaceAll(',', '.'));
    if (amount == null || amount <= 0) {
      setState(() => _error = l10n.balanceAmountInvalid);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.addBalance(amount, note: _note.text);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      // The month check above reads the last row; a change stored between that
      // read and this insert is refused by the policy itself. Saying "this
      // month is used" is the same answer, where a raw policy error reads as a
      // broken app.
      final refused = '$error'.toLowerCase().contains('row-level security');
      final nextDate = MaterialLocalizations.of(
        context,
      ).formatMediumDate(_nextChange.toLocal());
      setState(() {
        _saving = false;
        _error = refused
            ? l10n.balanceUsed(nextDate)
            : l10n.balanceFailed('$error');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nextDate = MaterialLocalizations.of(
      context,
    ).formatMediumDate(_nextChange.toLocal());

    return Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        10,
        18,
        18 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.balanceTitle,
            style: TextStyle(
              color: AppColors.text,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.balanceBody,
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _amount,
            enabled: !_usedThisMonth && !_loading && !_saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            style: TextStyle(
              color: AppColors.text,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              labelText: l10n.balanceAmount,
              labelStyle: TextStyle(color: AppColors.faint, fontSize: 12.5),
              filled: true,
              fillColor: AppColors.surfaceAlt,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.field),
                borderSide: BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.field),
                borderSide: BorderSide(color: AppColors.border),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _note,
            enabled: !_usedThisMonth && !_loading && !_saving,
            style: TextStyle(color: AppColors.text, fontSize: 13.5),
            decoration: InputDecoration(
              labelText: l10n.balanceNote,
              hintText: l10n.balanceNoteHint,
              labelStyle: TextStyle(color: AppColors.faint, fontSize: 12.5),
              hintStyle: TextStyle(color: AppColors.faint, fontSize: 12.5),
              filled: true,
              fillColor: AppColors.surfaceAlt,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.field),
                borderSide: BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.field),
                borderSide: BorderSide(color: AppColors.border),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _usedThisMonth ? l10n.balanceUsed(nextDate) : l10n.balanceAvailable,
            style: TextStyle(
              color: AppColors.primaryLight,
              fontSize: 11.5,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: TextStyle(color: AppColors.danger, fontSize: 11.5),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton(
              onPressed: _saving || _loading || _usedThisMonth ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.ink,
                disabledBackgroundColor: AppColors.surfaceAlt,
                disabledForegroundColor: AppColors.faint,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.button),
                ),
              ),
              child: Text(
                l10n.balanceSave,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
