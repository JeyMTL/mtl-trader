import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../ui/theme.dart';
import '../ui/widgets.dart';
import '../services/telemetry.dart';
import 'app_shell.dart';
import 'login_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final StreamSubscription<AuthState> _subscription;
  Session? _session;

  @override
  void initState() {
    super.initState();
    _session = Supabase.instance.client.auth.currentSession;
    if (_session != null) Telemetry.event('session_resumed');
    _subscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      state,
    ) {
      if (!mounted) return;
      // Only a fresh sign-in, not a token refresh: a refresh every hour would
      // swamp the funnel with events that say nothing about activation.
      if (state.event == AuthChangeEvent.signedIn) {
        Telemetry.event('sign_in');
      }
      setState(() => _session = state.session);
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session == null) return const LoginScreen();
    if (session.user.emailConfirmedAt == null) {
      return _VerifyEmailScreen(email: session.user.email ?? '');
    }
    return const AppShell();
  }
}

class _VerifyEmailScreen extends StatefulWidget {
  const _VerifyEmailScreen({required this.email});

  final String email;

  @override
  State<_VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<_VerifyEmailScreen> {
  bool _sending = false;
  bool _checking = false;
  String? _message;

  Future<void> _checkAgain() async {
    setState(() {
      _checking = true;
      _message = null;
    });
    try {
      await Supabase.instance.client.auth.refreshSession();
      if (!mounted) return;
      // The AuthGate listens to auth changes; a confirmed user is routed in.
      setState(
        () => _message =
            'Checked. If the journal did not open, sign out and back in.',
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Could not check yet. Try again in a moment.',
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _sending = true;
      _message = null;
    });
    try {
      await Supabase.instance.client.auth.resend(
        email: widget.email,
        type: OtpType.signup,
      );
      if (mounted) {
        setState(
          () => _message =
              'Confirmation link sent. Check your inbox and spam folder.',
        );
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Could not resend the email. Try again in a minute.',
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: FlatCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.mark_email_unread_outlined,
                      color: AppColors.primary,
                      size: 26,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Confirm your email',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'The journal opens once ${widget.email} is confirmed. Open the link Supabase emailed you, then return here.',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 12.5,
                        height: 1.5,
                      ),
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _message!,
                        style: TextStyle(
                          color: AppColors.primaryLight,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    ElevatedButton(
                      onPressed: _checking ? null : _checkAgain,
                      child: _checking
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.ink,
                              ),
                            )
                          : const Text('I have confirmed'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _sending ? null : _resend,
                      child: _sending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Resend confirmation'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () => Supabase.instance.client.auth.signOut(),
                      child: const Text('Use another account'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
