import 'package:flutter/material.dart';

import '../core/locale.dart';
import '../l10n/gen/app_localizations.dart';
import 'theme.dart';
import 'widgets.dart';

/// Language selection: follow the device, or pick one of the shipped
/// translations.
///
/// Public rather than private to the account screen so it can be tested on its
/// own — the account screen needs a signed-in API client to build.
class LanguagePicker extends StatelessWidget {
  const LanguagePicker({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final options = <({String? code, String label})>[
      (code: null, label: l10n.languageSystem),
      for (final locale in LocaleController.supported)
        (
          code: locale.languageCode,
          label: LocaleController.nativeNames[locale.languageCode] ??
              locale.languageCode,
        ),
    ];

    return FlatCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            title: l10n.language,
            subtitle: l10n.languageSubtitle,
          ),
          const SizedBox(height: 12),
          // Wrapped rather than three equal columns: "Système" and "English"
          // are not the same width, and at a 2x text scale three fixed columns
          // would either clip or scramble the labels.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in options)
                _LanguageChoice(code: option.code, label: option.label),
            ],
          ),
        ],
      ),
    );
  }
}

/// One language option. The root rebuilds the tree when the language changes,
/// so this needs no local state and cannot drift from the active language.
class _LanguageChoice extends StatelessWidget {
  const _LanguageChoice({required this.code, required this.label});

  /// Null means follow the device, which is also how the saved preference reads
  /// back — so the right tile is highlighted on first launch too.
  final String? code;
  final String label;

  @override
  Widget build(BuildContext context) {
    final active = LocaleController.instance.code == code;
    return Semantics(
      button: true,
      selected: active,
      child: InkWell(
        onTap: () => LocaleController.instance.setLanguage(code),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color:
                active ? AppColors.primary.withAlpha(20) : AppColors.surfaceAlt,
            border: Border.all(
              color: active ? AppColors.primary : AppColors.border,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? AppColors.primary : AppColors.muted,
              fontSize: kMinLabelSize,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
