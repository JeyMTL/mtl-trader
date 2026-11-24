import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/gen/app_localizations.dart';
import '../services/daily_stop_bus.dart';
import '../services/session_reminders.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// The Rules tab, on the phone.
///
/// It edits the same `playbooks` row as the web app does, under RLS, so a rule
/// written on the desk is the rule the phone reminds about and the rule the
/// daily stop measures. Nothing is computed here: the stop itself is decided by
/// `/api/day-state`, and this screen only stores what the trader committed to.
///
/// The order follows the way a session runs: the checklist first, then the days
/// and sessions it applies to, then the daily stop, then the reminder lead time.
class RulesScreen extends StatefulWidget {
  const RulesScreen({super.key});

  @override
  State<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends State<RulesScreen> {
  /// Read through the State's own context: the cards are built in helper
  /// methods, not inside `build`.
  AppLocalizations get _l10n => AppLocalizations.of(context);

  static const int _maxRules = 20;
  static const int _maxSessions = 6;
  static const List<int> _reminderChoices = [15, 30, 45, 60, 90, 120];

  final List<TextEditingController> _rules = [];
  final TextEditingController _notes = TextEditingController();
  final TextEditingController _lossLimit = TextEditingController();
  final TextEditingController _maxTrades = TextEditingController();
  final List<_Session> _sessions = [];

  Set<int> _days = {1, 2, 3, 4, 5};
  int _reminderMinutes = 60;
  bool _remindersEnabled = true;
  String _lockMode = 'off';

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final rule in _rules) {
      rule.dispose();
    }
    _notes.dispose();
    _lossLimit.dispose();
    _maxTrades.dispose();
    for (final session in _sessions) {
      session.dispose();
    }
    super.dispose();
  }

  String? get _userId => Supabase.instance.client.auth.currentUser?.id;

  Future<void> _load() async {
    final uid = _userId;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final row = await Supabase.instance.client
          .from('playbooks')
          .select()
          .eq('user_id', uid)
          .maybeSingle();
      if (!mounted) return;

      final rules = <TextEditingController>[];
      final rawRules = row?['rules'];
      if (rawRules is List) {
        for (final rule in rawRules) {
          final text = rule?.toString().trim() ?? '';
          if (text.isNotEmpty) rules.add(TextEditingController(text: text));
        }
      }

      final sessions = <_Session>[];
      final rawSessions = row?['sessions'];
      if (rawSessions is List) {
        for (final raw in rawSessions) {
          if (raw is! Map) continue;
          final start = raw['start']?.toString() ?? '';
          final end = raw['end']?.toString() ?? '';
          if (!_validTime(start) || !_validTime(end)) continue;
          sessions.add(
            _Session(
              // Kept across saves: the reminder's "already shown" key is built
              // from this id, and a new one would re-fire the same reminder.
              id: raw['id']?.toString(),
              label: raw['label']?.toString() ?? _l10n.rulesSessionFallback,
              start: start,
              end: end,
            ),
          );
        }
      }

      final days = <int>{};
      final rawDays = row?['days'];
      if (rawDays is List) {
        for (final day in rawDays) {
          final value = day is num ? day.toInt() : int.tryParse('$day');
          if (value != null && value >= 0 && value <= 6) days.add(value);
        }
      }

      final limit = row?['daily_loss_limit'];
      final cap = row?['max_trades_per_day'];

      setState(() {
        _rules
          ..clear()
          ..addAll(rules);
        _sessions
          ..clear()
          ..addAll(sessions);
        _days = rawDays is List ? days : {1, 2, 3, 4, 5};
        _notes.text = row?['notes']?.toString() ?? '';
        _reminderMinutes = row?['reminder_minutes'] is num
            ? (row!['reminder_minutes'] as num).toInt()
            : 60;
        _remindersEnabled = row?['reminders_enabled'] != false;
        _lockMode = switch (row?['lock_mode']) {
          'soft' => 'soft',
          'hard' => 'hard',
          _ => 'off',
        };
        _lossLimit.text = limit is num && limit > 0
            ? _trimNumber(limit.toDouble())
            : '';
        _maxTrades.text = cap is num && cap > 0 ? cap.toInt().toString() : '';
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _l10n.rulesLoadError('$error');
        _loading = false;
      });
    }
  }

  static bool _validTime(String value) =>
      RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(value.trim());

  static String _trimNumber(double value) =>
      value == value.roundToDouble() ? value.round().toString() : value.toStringAsFixed(2);

  Future<void> _save() async {
    final uid = _userId;
    if (uid == null || _saving) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    final rules = _rules
        .map((controller) => controller.text.trim())
        .where((text) => text.isNotEmpty)
        .map((text) => text.length > 280 ? text.substring(0, 280) : text)
        .toList();
    final lossLimit = double.tryParse(_lossLimit.text.trim()) ?? 0;
    final maxTrades = int.tryParse(_maxTrades.text.trim()) ?? 0;

    try {
      await Supabase.instance.client.from('playbooks').upsert(
        {
          'user_id': uid,
          'rules': rules,
          'days': _days.toList()..sort(),
          'sessions': _sessions
              .map(
                (session) => {
                  'id': session.id,
                  'label': session.label.text.trim().isEmpty
                      ? _l10n.rulesSessionFallback
                      : session.label.text.trim(),
                  'start': session.start,
                  'end': session.end,
                },
              )
              .toList(),
          'reminder_minutes': _reminderMinutes,
          'reminders_enabled': _remindersEnabled,
          'notes': _notes.text.trim(),
          'daily_loss_limit': lossLimit > 0 ? lossLimit : 0,
          'max_trades_per_day': maxTrades > 0 ? maxTrades : 0,
          'lock_mode': _lockMode,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id',
      );
      // The lock mode lives on this row, so the gate and the account tab have
      // to re-read instead of waiting for their own timers.
      DailyStopBus.refresh();
      // The lead time and the session times just changed, so the alarms have to
      // follow the save rather than wait for the next launch.
      unawaited(SessionReminders.sync());
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_l10n.rulesSaved)),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _l10n.rulesSaveError('$error');
      });
    }
  }

  void _addRule() {
    if (_rules.length >= _maxRules) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_l10n.rulesMaxReached)),
      );
      return;
    }
    setState(() => _rules.add(TextEditingController()));
  }

  void _removeRule(int index) {
    setState(() {
      _rules.removeAt(index).dispose();
    });
  }

  void _addSession() {
    if (_sessions.length >= _maxSessions) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_l10n.rulesSessionsMax)),
      );
      return;
    }
    setState(() => _sessions
        .add(_Session(label: _l10n.rulesNewSession, start: '09:00', end: '12:00')));
  }

  void _removeSession(int index) {
    setState(() {
      _sessions.removeAt(index).dispose();
    });
  }

  Future<void> _pickTime(_Session session, {required bool start}) async {
    final current = start ? session.start : session.end;
    final parts = current.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(parts.first) ?? 9,
        minute: int.tryParse(parts.last) ?? 0,
      ),
    );
    if (picked == null) return;
    final value =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() {
      if (start) {
        session.start = value;
      } else {
        session.end = value;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(_l10n.rules)),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 40),
              children: [
                Text(
                  _l10n.rulesIntro,
                  style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.5),
                ),
                const SizedBox(height: 12),
                if (_error != null) ...[
                  FlatCard(
                    borderColor: AppColors.danger.withAlpha(80),
                    child: Text(
                      _error!,
                      style: TextStyle(color: AppColors.danger, fontSize: 11.5, height: 1.45),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                _rulesCard(),
                const SizedBox(height: 10),
                _daysCard(),
                const SizedBox(height: 10),
                _dailyStopCard(),
                const SizedBox(height: 10),
                _sessionsCard(),
                const SizedBox(height: 10),
                _remindersCard(),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined, size: 18),
                  label: Text(_saving ? _l10n.rulesSaving : _l10n.rulesSave),
                ),
              ],
            ),
    );
  }

  Widget _rulesCard() {
    return FlatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            title: _l10n.rulesYourRules,
            subtitle: _l10n.rulesYourRulesBody,
            trailing: Text(
              '${_rules.length}/$_maxRules',
              style: TextStyle(color: AppColors.faint, fontSize: 11),
            ),
          ),
          const SizedBox(height: 10),
          if (_rules.isEmpty)
            Text(
              _l10n.rulesEmpty,
              style: TextStyle(color: AppColors.faint, fontSize: 11.5, height: 1.5),
            ),
          for (var index = 0; index < _rules.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 12, right: 6),
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(color: AppColors.faint, fontSize: 11),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _rules[index],
                      minLines: 1,
                      maxLines: 3,
                      maxLength: 280,
                      style: TextStyle(color: AppColors.text, fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'e.g. Only take the setup after a London open sweep.',
                        counterText: '',
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _removeRule(index),
                    tooltip: _l10n.rulesRemove,
                    icon: Icon(Icons.close, size: 16, color: AppColors.faint),
                  ),
                ],
              ),
            ),
          TextButton.icon(
            onPressed: _addRule,
            icon: const Icon(Icons.add, size: 16),
            label: Text(_l10n.rulesAdd),
          ),
        ],
      ),
    );
  }

  Widget _daysCard() {
    return FlatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            title: _l10n.rulesDays,
            subtitle: _l10n.rulesDaysBody,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var day = 0; day < 7; day++)
                _Choice(
                  // Weekday initials follow the language: Mon, Mo, Lun, Пн.
                  label: DateFormat('EEE', Localizations.localeOf(context).toLanguageTag())
                      .format(DateTime(2024, 1, 7 + day)),
                  selected: _days.contains(day),
                  onTap: () => setState(() {
                    if (!_days.remove(day)) _days.add(day);
                  }),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dailyStopCard() {
    return FlatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            title: _l10n.rulesDailyStop,
            subtitle: _l10n.rulesDailyStopBody,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _NumberField(
                  label: _l10n.rulesLossBudget,
                  controller: _lossLimit,
                  hint: 'e.g. 250',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NumberField(
                  label: _l10n.rulesMaxEntries,
                  controller: _maxTrades,
                  hint: 'e.g. 3',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _l10n.rulesWhenReached,
            style: TextStyle(color: AppColors.faint, fontSize: 10.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          _LockOption(
            label: _l10n.lockJournalOnly,
            blurb: _l10n.rulesJournalOnlyBlurb,
            selected: _lockMode == 'off',
            onTap: () => setState(() => _lockMode = 'off'),
          ),
          const SizedBox(height: 6),
          _LockOption(
            label: _l10n.lockSoft,
            blurb: _l10n.rulesSoftBlurb,
            selected: _lockMode == 'soft',
            onTap: () => setState(() => _lockMode = 'soft'),
          ),
          const SizedBox(height: 6),
          _LockOption(
            label: _l10n.lockHard,
            blurb: _l10n.rulesHardBlurb,
            selected: _lockMode == 'hard',
            onTap: () => setState(() => _lockMode = 'hard'),
          ),
        ],
      ),
    );
  }

  Widget _sessionsCard() {
    return FlatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            title: _l10n.rulesSessions,
            subtitle: _l10n.rulesSessionsBody,
          ),
          const SizedBox(height: 10),
          if (_sessions.isEmpty)
            Text(
              _l10n.rulesNoSessions,
              style: TextStyle(color: AppColors.faint, fontSize: 11.5),
            ),
          for (var index = 0; index < _sessions.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _sessions[index].label,
                      style: TextStyle(color: AppColors.text, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: _l10n.rulesSessionName,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _TimeChip(
                    value: _sessions[index].start,
                    onTap: () => _pickTime(_sessions[index], start: true),
                  ),
                  const SizedBox(width: 4),
                  _TimeChip(
                    value: _sessions[index].end,
                    onTap: () => _pickTime(_sessions[index], start: false),
                  ),
                  IconButton(
                    onPressed: () => _removeSession(index),
                    tooltip: _l10n.rulesRemoveSession,
                    icon: Icon(Icons.close, size: 16, color: AppColors.faint),
                  ),
                ],
              ),
            ),
          TextButton.icon(
            onPressed: _addSession,
            icon: const Icon(Icons.add, size: 16),
            label: Text(_l10n.rulesAddSession),
          ),
        ],
      ),
    );
  }

  Widget _remindersCard() {
    return FlatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            title: _l10n.rulesReminders,
            subtitle: _l10n.rulesRemindersBody,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _remindersEnabled,
            onChanged: (value) => setState(() => _remindersEnabled = value),
            title: Text(
              _remindersEnabled ? _l10n.rulesRemindersOn : _l10n.rulesRemindersOff,
              style: TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          Row(
            children: [
              Text(
                _l10n.rulesReminderLead,
                style: TextStyle(color: AppColors.muted, fontSize: 11.5),
              ),
              const Spacer(),
              DropdownButton<int>(
                value: _reminderChoices.contains(_reminderMinutes) ? _reminderMinutes : 60,
                dropdownColor: AppColors.surface,
                underline: const SizedBox.shrink(),
                items: [
                  for (final minutes in _reminderChoices)
                    DropdownMenuItem(
                      value: minutes,
                      child: Text(
                        _l10n.rulesReminderMinutes('$minutes'),
                        style: TextStyle(color: AppColors.text, fontSize: 12),
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _reminderMinutes = value);
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _notes,
            minLines: 2,
            maxLines: 4,
            maxLength: 2000,
            style: TextStyle(color: AppColors.text, fontSize: 13),
            decoration: InputDecoration(
              labelText: _l10n.rulesNotes,
              hintText: _l10n.rulesNotesHint,
              counterText: '',
            ),
          ),
        ],
      ),
    );
  }
}

class _Session {
  _Session({
    String? id,
    required String label,
    required this.start,
    required this.end,
  })  : id = (id == null || id.isEmpty)
            ? 'session-${DateTime.now().microsecondsSinceEpoch}'
            : id,
        label = TextEditingController(text: label);

  final String id;
  final TextEditingController label;
  String start;
  String end;

  void dispose() => label.dispose();
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.label,
    required this.controller,
    required this.hint,
  });

  final String label;
  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: AppColors.faint, fontSize: 10.5)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: TextStyle(color: AppColors.text, fontSize: 13),
          decoration: InputDecoration(hintText: hint),
        ),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.12) : AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? AppColors.primary : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.primary : AppColors.muted,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _LockOption extends StatelessWidget {
  const _LockOption({
    required this.label,
    required this.blurb,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String blurb;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.10) : AppColors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? AppColors.primary : AppColors.border),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 15,
              color: selected ? AppColors.primary : AppColors.faint,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: selected ? AppColors.primary : AppColors.text,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    blurb,
                    style: TextStyle(color: AppColors.faint, fontSize: 10.5, height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({required this.value, required this.onTap});

  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          value,
          style: TextStyle(color: AppColors.text, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
