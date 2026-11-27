import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config.dart';
import '../l10n/gen/app_localizations.dart';
import '../ui/brand.dart';
import '../ui/password_reset_sheet.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// The first screen of the app, and the only one a new account sees before it
/// has any data.
///
/// Order is the design: the brand lockup and the promise first, then the
/// intent switch, then the fields, then one gold action, and only after that
/// the third-party route. Signing in with Google used to sit *above* the
/// Sign in / Create account tabs, which read as if the tabs belonged to the
/// Google button; the tab is now what a tap lands on first.
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

  /// `GoogleSignIn.initialize` must run exactly once per process, and a retry
  /// after a cancelled sheet reuses the same instance.
  static bool _googleReady = false;

  /// Android's native account sheet returns an ID token without leaving the
  /// app. That matters beyond convenience: the browser flow redirects through
  /// the Supabase project URL, so Google's chooser announces
  /// `<project-ref>.supabase.co` to the user.
  ///
  /// Returns null when this build cannot produce a token — iOS has no OAuth
  /// client of its own configured yet, and a build without `GOOGLE_CLIENT_ID`
  /// has nothing to validate against — in which case the caller keeps the
  /// browser deep-link flow.
  Future<String?> _nativeGoogleIdToken() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    final clientId = AppConfig.googleClientId;
    if (clientId.isEmpty) return null;

    final google = GoogleSignIn.instance;
    if (!_googleReady) {
      await google.initialize(serverClientId: clientId);
      _googleReady = true;
    }
    if (!google.supportsAuthenticate()) return null;

    final account = await google.authenticate();
    return account.authentication.idToken;
  }

  Future<void> _google() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });
    try {
      final idToken = await _nativeGoogleIdToken();
      if (idToken != null) {
        // AuthGate reacts to the auth state change and swaps this screen out.
        await Supabase.instance.client.auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: idToken,
        );
        return;
      }

      // Fallback: opens Google in the system browser and returns through the
      // app's deep link, so the password never passes through this screen.
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
    } on GoogleSignInException catch (error) {
      // A dismissed sheet is not a failure: leave the form as the user left
      // it. Credential Manager reports a configuration error (a package/SHA-1
      // Google does not recognise) the same way, and the plugin cannot tell
      // them apart — the only evidence is logcat, so nothing shows here.
      if (mounted && error.code != GoogleSignInExceptionCode.canceled) {
        setState(
          () => _error =
              error.description ??
              AppLocalizations.of(context).googleStartFailed,
        );
      }
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

  /// Switching tabs is the one moment the form changes shape under the finger,
  /// so it ticks. The error belongs to the mode that produced it and goes with
  /// it.
  void _setMode(bool signUp) {
    if (signUp == _signUp) return;
    HapticFeedback.selectionClick();
    setState(() {
      _signUp = signUp;
      _error = null;
      _notice = null;
    });
  }

  Future<void> _openLegal(String path) async {
    final base = AppConfig.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    await launchUrl(
      Uri.parse('$base$path'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // The hero's visual evidence, drawn rather than boxed: a
                      // rising equity line fading into an audio waveform, at the
                      // opacity of a watermark. It says "trades, screenshots,
                      // voice notes" without spending a single pixel of layout.
                      Positioned(
                        top: -26,
                        left: -40,
                        right: -40,
                        height: 210,
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _AuthMotifPainter(
                              color: AppColors.primary,
                              isLight: AppColors.palette.isLight,
                            ),
                          ),
                        ),
                      ),
                      _Hero(l10n: l10n),
                    ],
                  ),
                  const SizedBox(height: 22),
                  FlatCard(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _ModeSwitch(signUp: _signUp, onChanged: _setMode),
                          const SizedBox(height: 18),
                          AutofillGroup(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextFormField(
                                  controller: _email,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  // `username` is the hint password managers
                                  // key a saved login on; sign-up asks for a new
                                  // address instead.
                                  autofillHints: [
                                    _signUp
                                        ? AutofillHints.email
                                        : AutofillHints.username,
                                  ],
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  decoration: InputDecoration(
                                    labelText: l10n.emailLabel,
                                    hintText: l10n.emailHint,
                                    prefixIcon: Icon(
                                      Icons.alternate_email,
                                      size: 18,
                                      color: AppColors.faint,
                                    ),
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
                                  autofillHints: [
                                    _signUp
                                        ? AutofillHints.newPassword
                                        : AutofillHints.password,
                                  ],
                                  decoration: InputDecoration(
                                    labelText: l10n.passwordLabel,
                                    prefixIcon: Icon(
                                      Icons.lock_outline,
                                      size: 18,
                                      color: AppColors.faint,
                                    ),
                                    suffixIcon: IconButton(
                                      tooltip: _obscure
                                          ? l10n.showPassword
                                          : l10n.hidePassword,
                                      onPressed: () => setState(
                                        () => _obscure = !_obscure,
                                      ),
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
                              ],
                            ),
                          ),
                          // Recovery sits under the field it recovers, not in a
                          // menu or on the website: the moment a sign-in fails,
                          // this is the next thing the trader needs.
                          if (!_signUp)
                            Align(
                              alignment: Alignment.centerRight,
                              child: _ForgotLink(
                                label: l10n.forgotPassword,
                                onTap: () => showPasswordResetSheet(
                                  context,
                                  initialEmail: _email.text.trim(),
                                ),
                              ),
                            ),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
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
                          if (_notice != null) ...[
                            const SizedBox(height: 12),
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                _notice!,
                                style: TextStyle(
                                  color: AppColors.success,
                                  fontSize: 12,
                                  height: 1.4,
                                ),
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
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              const Expanded(child: _Rule()),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                child: Text(
                                  l10n.orSeparator,
                                  style: TextStyle(
                                    color: AppColors.faint,
                                    fontSize: kMinLabelSize,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ),
                              const Expanded(child: _Rule()),
                            ],
                          ),
                          const SizedBox(height: 14),
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
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_signUp)
                    Text(
                      l10n.loginFootnote,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.faint,
                        fontSize: kMinLabelSize,
                        height: 1.45,
                      ),
                    )
                  else
                    _SignInFooter(
                      onTerms: () => _openLegal('/terms'),
                      onPrivacy: () => _openLegal('/privacy'),
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

/// Brand, promise, and the two lines that carry the product story.
class _Hero extends StatelessWidget {
  const _Hero({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _BrandBadge(),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                l10n.brandName.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.primaryLight,
                  fontSize: kMinLabelSize,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.8,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          l10n.loginHeadline,
          style: TextStyle(
            color: AppColors.text,
            fontSize: 30,
            height: 1.12,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.loginTagline,
          style: TextStyle(
            color: AppColors.muted,
            fontSize: 13.5,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

/// The mark at 34px — the same icon the launcher shows, with the gold rim the
/// old 168px hero spent a third of the screen on.
class _BrandBadge extends StatelessWidget {
  const _BrandBadge();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: 34,
        height: 34,
        padding: const EdgeInsets.all(1.3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: kRimGradient,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withAlpha(46),
              blurRadius: 12,
              spreadRadius: 0.5,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8.7),
          child: Image.asset(
            kBrandIconAsset,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    );
  }
}

/// Sign in / Create account, as one control with a sliding gold edge.
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.signUp, required this.onChanged});

  final bool signUp;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 220);

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.field),
        border: Border.all(color: AppColors.border),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedAlign(
              alignment: signUp ? Alignment.centerRight : Alignment.centerLeft,
              duration: duration,
              curve: Curves.easeOutCubic,
              child: FractionallySizedBox(
                widthFactor: 0.5,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.primary.withAlpha(
                      AppColors.palette.isLight ? 34 : 26,
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.field - 3),
                    border: Border.all(
                      color: AppColors.primary.withAlpha(96),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _ModeTab(
                  label: l10n.signIn,
                  active: !signUp,
                  onTap: () => onChanged(false),
                ),
              ),
              Expanded(
                child: _ModeTab(
                  label: l10n.createAccount,
                  active: signUp,
                  onTap: () => onChanged(true),
                ),
              ),
            ],
          ),
        ],
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
    return Semantics(
      button: true,
      selected: active,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.field - 3),
        // 44dp tall plus the switch's 3dp padding clears the 48dp target.
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          child: Text(
            label,
            textAlign: TextAlign.center,
            // Two lines, not an ellipsis: "Créer un compte" at 2x text is wider
            // than half the card and must not lose its last word.
            maxLines: 2,
            style: TextStyle(
              color: active ? AppColors.primaryLight : AppColors.muted,
              fontSize: 12,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _ForgotLink extends StatelessWidget {
  const _ForgotLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Text(
          label,
          style: TextStyle(
            color: AppColors.primaryLight,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: AppColors.border);
  }
}

class _SignInFooter extends StatelessWidget {
  const _SignInFooter({required this.onTerms, required this.onPrivacy});

  final VoidCallback onTerms;
  final VoidCallback onPrivacy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final base = TextStyle(
      color: AppColors.faint,
      fontSize: kMinLabelSize,
      height: 1.45,
    );
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        Text(l10n.loginFooterEncrypted, style: base, textAlign: TextAlign.center),
        Text('·', style: base),
        _LegalLink(label: l10n.termsLabel, onTap: onTerms),
        Text('·', style: base),
        _LegalLink(label: l10n.privacyLabel, onTap: onPrivacy),
      ],
    );
  }
}

class _LegalLink extends StatelessWidget {
  const _LegalLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Text(
          label,
          style: TextStyle(
            color: AppColors.primaryLight,
            fontSize: kMinLabelSize,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

/// Watermark behind the hero: an equity curve climbing out of a waveform.
///
/// Purely decorative — no semantics, no hit testing, and drawn at the alpha of
/// a paper watermark so the headline keeps its contrast on every palette.
class _AuthMotifPainter extends CustomPainter {
  const _AuthMotifPainter({required this.color, required this.isLight});

  final Color color;
  final bool isLight;

  /// Alpha for the theme, doubled on the dark ground where a low-opacity gold
  /// would disappear entirely.
  int _alpha(double dark, double light) =>
      (isLight ? light : dark).round().clamp(0, 255);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    // Ambient glow, top-left, the light the old rim used to cast.
    final centre = Offset(size.width * 0.22, size.height * 0.42);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: [color.withAlpha(_alpha(30, 18)), color.withAlpha(0)],
        ).createShader(
          Rect.fromCircle(center: centre, radius: size.width * 0.62),
        ),
    );

    // Equity line: eleven points, the shape of a good month rather than a
    // straight line, because a straight line is a logo and this is a journal.
    final samples = <double>[
      0.78, 0.72, 0.8, 0.62, 0.66, 0.52, 0.46, 0.55, 0.36, 0.3, 0.18,
    ];
    final left = size.width * 0.3;
    final width = size.width * 0.66;
    final top = size.height * 0.16;
    final height = size.height * 0.5;

    final line = Path();
    for (var i = 0; i < samples.length; i++) {
      final x = left + width * (i / (samples.length - 1));
      final y = top + height * samples[i];
      if (i == 0) {
        line.moveTo(x, y);
      } else {
        line.lineTo(x, y);
      }
    }

    final fill = Path.from(line)
      ..lineTo(left + width, top + height)
      ..lineTo(left, top + height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withAlpha(_alpha(24, 14)), color.withAlpha(0)],
        ).createShader(Rect.fromLTWH(left, top, width, height)),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color.withAlpha(_alpha(70, 44))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // The end of the line becomes a waveform: the voice notes the tagline
    // promises, at the same muted strength as the curve.
    final barPaint = Paint()
      ..color = color.withAlpha(_alpha(58, 38))
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.2;
    const bars = <double>[0.34, 0.62, 0.44, 0.86, 0.5, 0.7, 0.3];
    final barLeft = left + width * 0.72;
    final barTop = top + height * 0.18;
    for (var i = 0; i < bars.length; i++) {
      final x = barLeft + i * 5.4;
      final half = height * 0.09 * bars[i];
      canvas.drawLine(Offset(x, barTop - half * 2), Offset(x, barTop + half), barPaint);
    }
  }

  @override
  bool shouldRepaint(_AuthMotifPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.isLight != isLight;
}
