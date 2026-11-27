import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config.dart';
import '../l10n/gen/app_localizations.dart';
import 'theme.dart';

/// Password recovery, asked for where the password is typed.
///
/// The app had no recovery path at all: a trader who forgot the password had to
/// find the website, and the sign-in card offered nothing but "try again". This
/// sheet sends the same Supabase recovery mail the web's `/auth/forgot` page
/// sends, with the link pointing at the web reset form, so a phone user and a
/// web user finish in the same place.
///
/// The confirmation is deliberately the same sentence whether or not the address
/// has an account: the form must not become a way to discover which emails are
/// registered.
Future<void> showPasswordResetSheet(
  BuildContext context, {
  String initialEmail = '',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PasswordResetSheet(initialEmail: initialEmail),
  );
}

class _PasswordResetSheet extends StatefulWidget {
  const _PasswordResetSheet({required this.initialEmail});

  final String initialEmail;

  @override
  State<_PasswordResetSheet> createState() => _PasswordResetSheetState();
}

class _PasswordResetSheetState extends State<_PasswordResetSheet> {
  late final TextEditingController _email = TextEditingController(
    text: widget.initialEmail,
  );

  bool _loading = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_loading) return;
    final l10n = AppLocalizations.of(context);
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = l10n.emailInvalid);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });

    final base = AppConfig.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: '$base/auth/reset',
      );
      if (mounted) setState(() => _sent = true);
    } on AuthException {
      // The server's own sentence is about rate limits or the mail provider,
      // never about whether the address exists, so it is safe to show.
      if (mounted) setState(() => _error = l10n.resetFailed);
    } catch (_) {
      if (mounted) setState(() => _error = l10n.resetFailed);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final radius = BorderRadius.circular(AppRadius.sheet);

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Material(
        color: AppColors.surface,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // A short gold rule above the title: the sheet opens over the
                // login card, and the line separates it from the form behind.
                Container(
                  width: 34,
                  height: 3,
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.resetTitle,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.resetBody,
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 16),
                if (_sent)
                  Semantics(
                    liveRegion: true,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.mark_email_read_outlined,
                          size: 18,
                          color: AppColors.success,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.resetSent(_email.text.trim()),
                            style: TextStyle(
                              color: AppColors.success,
                              fontSize: 13,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.email],
                    autocorrect: false,
                    enableSuggestions: false,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      labelText: l10n.emailLabel,
                      hintText: l10n.emailHint,
                      prefixIcon: Icon(
                        Icons.alternate_email,
                        size: 18,
                        color: AppColors.faint,
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: AppColors.danger,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  ElevatedButton(
                    onPressed: _loading ? null : _send,
                    child: _loading
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.ink,
                            ),
                          )
                        : Text(l10n.resetSend),
                  ),
                ],
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: Text(_sent ? l10n.closeLabel : l10n.cancel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
