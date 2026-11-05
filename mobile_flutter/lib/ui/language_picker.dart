import 'dart:async';

import 'package:flutter/material.dart';

import '../core/language_packs.dart';
import '../core/locale.dart';
import '../l10n/gen/app_localizations.dart';
import 'theme.dart';
import 'widgets.dart';

/// Language selection: follow the device, or pick one of the shipped
/// translations.
///
/// The catalogue is far too long for a row of chips, so the card shows the
/// active choice and opens a searchable sheet. English is compiled in; the other
/// languages download from the published packs, and a language with no pack yet
/// still selects, showing English until it is translated.
class LanguagePicker extends StatelessWidget {
  const LanguagePicker({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final active = LocaleController.languageFor(LocaleController.instance.code);

    return FlatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            title: l10n.language,
            subtitle: l10n.languageSubtitle,
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => _openSheet(context),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Text(
                    active?.flag ?? '🌐',
                    style: const TextStyle(fontSize: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      active?.nativeName ?? l10n.languageSystem,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(Icons.expand_more, size: 18, color: AppColors.faint),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (_) => const _LanguageSheet(),
    );
  }
}

/// The searchable list. Flag and native name on every row, with the English name
/// underneath so someone who cannot read the script can still find it.
class _LanguageSheet extends StatefulWidget {
  const _LanguageSheet();

  @override
  State<_LanguageSheet> createState() => _LanguageSheetState();
}

class _LanguageSheetState extends State<_LanguageSheet> {
  final TextEditingController _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Sizes come from the published manifest. If it cannot be reached the sheet
    // still works: downloaded languages keep their state and every language
    // stays selectable.
    unawaited(LanguagePacks.instance.refreshManifest());
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// English, and anything with a published or installed pack, counts as
  /// translated: choosing it gives a localized interface rather than English
  /// words in a foreign date format.
  bool _translated(String code) {
    final packs = LanguagePacks.instance;
    return packs.isBuiltIn(code) ||
        packs.isInstalled(code) ||
        packs.infoFor(code) != null;
  }

  /// Translated languages first, then the long tail alphabetically. Someone who
  /// opens the sheet to change language sees the ones that will actually speak
  /// back before the ones that still fall back to English.
  List<AppLanguage> _matches() {
    final needle = _query.text.trim().toLowerCase();
    final entries = [...LocaleController.languages]
      ..sort((a, b) {
        final aTranslated = _translated(a.code);
        if (aTranslated != _translated(b.code)) return aTranslated ? -1 : 1;
        return a.nativeName.toLowerCase().compareTo(
              b.nativeName.toLowerCase(),
            );
      });
    if (needle.isEmpty) return entries;
    return entries
        .where(
          (entry) =>
              entry.nativeName.toLowerCase().contains(needle) ||
              entry.englishName.toLowerCase().contains(needle) ||
              entry.code.toLowerCase().contains(needle),
        )
        .toList();
  }

  Future<void> _choose(String? code) async {
    final l10n = AppLocalizations.of(context);

    if (code == null) {
      await LocaleController.instance.setLanguage(null);
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final packs = LanguagePacks.instance;
    final downloadable = !packs.isBuiltIn(code) &&
        !packs.isInstalled(code) &&
        packs.infoFor(code) != null;

    if (downloadable) {
      final installed = await packs.install(code);
      if (!installed) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.languagePackFailed)),
          );
        }
        return;
      }
    }

    await LocaleController.instance.setLanguage(code);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _remove(String code) async {
    await LanguagePacks.instance.remove(code);
    // A language whose pack just left the phone cannot stay active: the strings
    // would silently become English.
    if (LocaleController.instance.code == code) {
      await LocaleController.instance.setLanguage(null);
    }
  }

  String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    return '${kb < 10 ? kb.toStringAsFixed(1) : kb.round()} KB';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final height = MediaQuery.sizeOf(context).height * 0.75;

    return SizedBox(
      height: height,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.borderStrong,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.language,
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: l10n.cancel,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _query,
              autofocus: false,
              onChanged: (_) => setState(() {}),
              style: TextStyle(color: AppColors.text, fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText: l10n.searchLanguages,
                prefixIcon: Icon(
                  Icons.search,
                  size: 18,
                  color: AppColors.faint,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListenableBuilder(
              listenable: LanguagePacks.instance,
              builder: (context, _) {
                final matches = _matches();
                return ListView(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                  children: [
                    _LanguageRow(
                      flag: '🌐',
                      title: l10n.languageSystem,
                      subtitle: l10n.languageSystemSubtitle,
                      active: LocaleController.instance.code == null,
                      onTap: () => _choose(null),
                    ),
                    for (final entry in matches) _rowFor(l10n, entry),
                    if (matches.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(18),
                        child: Text(
                          l10n.noLanguageMatches,
                          style: TextStyle(
                            color: AppColors.faint,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _rowFor(AppLocalizations l10n, AppLanguage entry) {
    final packs = LanguagePacks.instance;
    final active = LocaleController.instance.code == entry.code;

    if (packs.isInstalling(entry.code)) {
      return _LanguageRow(
        flag: entry.flag,
        title: entry.nativeName,
        subtitle: entry.englishName,
        active: active,
        trailing: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (packs.isBuiltIn(entry.code)) {
      return _LanguageRow(
        flag: entry.flag,
        title: entry.nativeName,
        subtitle: entry.englishName,
        active: active,
        onTap: () => _choose(entry.code),
        trailing: _LanguageBadge(l10n.languageBuiltIn),
      );
    }

    if (packs.isInstalled(entry.code)) {
      return _LanguageRow(
        flag: entry.flag,
        title: entry.nativeName,
        subtitle: entry.englishName,
        active: active,
        onTap: () => _choose(entry.code),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _LanguageBadge(l10n.languageDownloaded),
            IconButton(
              tooltip: l10n.languageRemove,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () => _remove(entry.code),
            ),
          ],
        ),
      );
    }

    final info = packs.infoFor(entry.code);
    if (info == null) {
      return _LanguageRow(
        flag: entry.flag,
        title: entry.nativeName,
        subtitle: entry.englishName,
        active: active,
        onTap: () => _choose(entry.code),
        trailing: _LanguageBadge(l10n.languageEnglishFallback),
      );
    }

    return _LanguageRow(
      flag: entry.flag,
      title: entry.nativeName,
      subtitle: entry.englishName,
      active: active,
      onTap: () => _choose(entry.code),
      trailing: _LanguageBadge(
        info.bytes > 0
            ? '${l10n.languageDownload} · ${_size(info.bytes)}'
            : l10n.languageDownload,
        highlight: true,
      ),
    );
  }
}

/// The state of one language, as a pill: built in, a size to download,
/// downloaded, or still English. Tapping the row is the action, so the badge
/// only has to say where the language stands.
class _LanguageBadge extends StatelessWidget {
  const _LanguageBadge(this.label, {this.highlight = false});

  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 132),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: highlight
              ? AppColors.primary.withValues(alpha: 0.12)
              : AppColors.surfaceAlt,
          border: Border.all(
            color: highlight ? AppColors.primary : AppColors.border,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: highlight ? AppColors.primary : AppColors.faint,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    required this.flag,
    required this.title,
    required this.subtitle,
    required this.active,
    this.onTap,
    this.trailing,
  });

  final String flag;
  final String title;
  final String subtitle;
  final bool active;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              Text(flag, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: active ? AppColors.primary : AppColors.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.faint,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (active)
                Icon(Icons.check, size: 16, color: AppColors.primary),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}
