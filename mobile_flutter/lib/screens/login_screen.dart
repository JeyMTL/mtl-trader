import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config.dart';
import '../l10n/gen/app_localizations.dart';
import '../ui/brand.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _signUp = false;
  bool _loading = false;
  bool _obscure = true;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _google() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });
    try {
      // Opens Google in the system browser and returns through the app's deep
      // link, so the password never passes through this screen.
      final launched = await Supabase.instance.client.auth
          .signInWithOAuth(
            OAuthProvider.google,
            redirectTo: AppConfig.oauthRedirect,
            authScreenLaunchMode: LaunchMode.externalApplication,
          )
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      if (!launched) {
        setState(
          () => _error = AppLocalizations.of(context).googleOpenFailed,
        );
        return;
      }
      // Nothing returns from the browser here: the deep link carries the
      // session back and AuthGate swaps this screen out on the auth change.
      // Without this line the form looks idle and the user assumes it failed.
      setState(
        () => _notice = AppLocalizations.of(context).googleFinishNotice,
      );
    } on TimeoutException {
      if (mounted) {
        setState(
          () => _error = AppLocalizations.of(context).googleTimedOut,
        );
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = AppLocalizations.of(context).googleStartFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });

    final auth = Supabase.instance.client.auth;
    try {
      if (_signUp) {
        final response = await auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
        );
        if (!mounted) return;
        if (response.session == null) {
          setState(() {
            _notice = AppLocalizations.of(
              context,
            ).confirmEmailNotice(_email.text.trim());
            _signUp = false;
          });
        }
      } else {
        await auth.signInWithPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = AppLocalizations.of(context).signInUnreachable,
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // A minimum height, not a fixed one: at a 2x text scale the
                  // wordmark is twice as tall and a fixed box would clip it.
                  Container(
                    constraints: const BoxConstraints(minHeight: 148),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 20,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.surface, AppColors.background],
                      ),
                      border: Border.all(color: AppColors.border),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withAlpha(30),
                          blurRadius: 34,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        Positioned(
                          right: -34,
                          top: -54,
                          child: Container(
                            width: 150,
                            height: 150,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  AppColors.primary.withAlpha(62),
                                  AppColors.primary.withAlpha(0),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const BrandMark(fontSize: 30, showDate: false),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    l10n.loginHeadline,
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 30,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.loginTagline,
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FlatCard(
                    padding: const EdgeInsets.all(16),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _loading ? null : _google,
                            icon: const Text(
                              'G',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            label: Text(l10n.continueWithGoogle),
                          ),
                          const SizedBox(height: 12),
                          // Each tab takes half the width and wraps onto a
                          // second line instead of pushing the other one off
                          // the card: "Créer un compte" at 2x is wider than
                          // the space two side-by-side tabs used to have.
                          // IntrinsicHeight, not a bare stretch: the Row sits
                          // in a Column with unbounded height, so stretching
                          // without a bounded box throws. This keeps the two
                          // tabs the same height even when one wraps.
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: _ModeTab(
                                    label: l10n.signIn,
                                    active: !_signUp,
                                    onTap: () => setState(() {
                                      _signUp = false;
                                      _error = null;
                                    }),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _ModeTab(
                                    label: l10n.createAccount,
                                    active: _signUp,
                                    onTap: () => setState(() {
                                      _signUp = true;
                                      _error = null;
                                    }),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            decoration: InputDecoration(
                              labelText: l10n.emailLabel,
                              hintText: l10n.emailHint,
                            ),
                            validator: (value) {
                              final text = value?.trim() ?? '';
                              if (text.isEmpty || !text.contains('@')) {
                                return l10n.emailInvalid;
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _password,
                            obscureText: _obscure,
                            autofillHints: const [AutofillHints.password],
                            decoration: InputDecoration(
                              labelText: l10n.passwordLabel,
                              suffixIcon: IconButton(
                                tooltip: _obscure
                                    ? l10n.showPassword
                                    : l10n.hidePassword,
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  size: 18,
                                  color: AppColors.faint,
                                ),
                              ),
                            ),
                            validator: (value) {
                              if ((value ?? '').length < 6) {
                                return l10n.passwordTooShort;
                              }
                              return null;
                            },
                            onFieldSubmitted: (_) => _submit(),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              style: TextStyle(
                                color: AppColors.danger,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ],
                          if (_notice != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _notice!,
                              style: TextStyle(
                                color: AppColors.success,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _loading ? null : _submit,
                            child: _loading
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.ink,
                                    ),
                                  )
                                : Text(
                                    _signUp ? l10n.createAccount : l10n.signIn,
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    l10n.loginFootnote,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.faint,
                      fontSize: kMinLabelSize,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.primary.withAlpha(26) : Colors.transparent,
          border: Border.all(
            color: active ? AppColors.primary.withAlpha(90) : AppColors.border,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: active ? AppColors.primaryLight : AppColors.muted,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
