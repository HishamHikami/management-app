import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../api.dart';
import '../state.dart';
import '../ui.dart';

/// Sign in with email/phone + password, or join with an invite code from an admin.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.startWithInvite = false});
  final bool startWithInvite;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late bool _invite = widget.startWithInvite;

  Future<void> _changeServer() async {
    final app = AppScope.read(context);
    final c = TextEditingController(text: app.server.replaceFirst('https://', ''));
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Server'),
        content: TextField(
          controller: c,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(hintText: 'ksa-riyadh.halacreative.com'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('Default')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Save')),
        ],
      ),
    );
    if (r != null) await app.setServer(r);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: Navigator.of(context).canPop() ? AppBar(backgroundColor: Colors.transparent) : null,
      body: Stack(
        children: [
          // Soft brand glow behind the form.
          Positioned(
            top: -140,
            left: -80,
            right: -80,
            child: Container(
              height: 380,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [cs.primary.withValues(alpha: .22), cs.primary.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: GestureDetector(
                          onLongPress: () {
                            HapticFeedback.heavyImpact();
                            _changeServer();
                          },
                          child: const Appear(index: 0, child: BrandMark(size: 132)),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Appear(
                        index: 1,
                        child: Text(
                          app.shortName,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -.3),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Appear(
                        index: 2,
                        child: Text(
                          app.orgName,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ),
                      const SizedBox(height: 30),
                      Appear(
                        index: 3,
                        child: AnimatedSize(
                          duration: const Duration(milliseconds: 320),
                          curve: Curves.easeOutCubic,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 280),
                            transitionBuilder: (child, a) => FadeTransition(
                              opacity: a,
                              child: SlideTransition(
                                position: Tween(begin: const Offset(0, .04), end: Offset.zero).animate(a),
                                child: child,
                              ),
                            ),
                            child: _invite
                                ? _InviteForm(key: const ValueKey('invite'), onBack: () => setState(() => _invite = false))
                                : _SignInForm(key: const ValueKey('signin'), onInvite: () => setState(() => _invite = true)),
                          ),
                        ),
                      ),
                      if (app.server != kServer) ...[
                        const SizedBox(height: 20),
                        Text(
                          'Server: ${app.server.replaceFirst('https://', '')}',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignInForm extends StatefulWidget {
  const _SignInForm({super.key, required this.onInvite});
  final VoidCallback onInvite;
  @override
  State<_SignInForm> createState() => _SignInFormState();
}

class _SignInFormState extends State<_SignInForm> {
  final _id = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  String? _error;

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_id.text.trim().isEmpty || _pass.text.isEmpty) {
      setState(() => _error = 'Enter your email or phone and your password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final nav = Navigator.of(context);
      await AppScope.read(context).login(_id.text.trim(), _pass.text);
      HapticFeedback.mediumImpact();
      nav.popUntil((r) => r.isFirst);
    } on ApiException catch (e) {
      HapticFeedback.heavyImpact();
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Couldn\'t sign in: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _id,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.username, AutofillHints.email, AutofillHints.telephoneNumber],
            autocorrect: false,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Mobile number or email', prefixIcon: Icon(Icons.person_outline_rounded)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pass,
            obscureText: _hide,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _hide = !_hide),
              ),
            ),
          ),
          _ErrorText(_error),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Text('Sign in'),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('New here?', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
              const Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: widget.onInvite,
            icon: const Icon(Icons.vpn_key_outlined),
            label: const Text('Members: I have an invite code'),
          ),
          const SizedBox(height: 10),
          Text(
            'Forgot your password? Use "Forgot password" on the Me page.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _InviteForm extends StatefulWidget {
  const _InviteForm({super.key, required this.onBack});
  final VoidCallback onBack;
  @override
  State<_InviteForm> createState() => _InviteFormState();
}

class _InviteFormState extends State<_InviteForm> {
  final _code = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  Json? _who; // set once the code is checked
  bool _busy = false;
  bool _hide = true;
  String? _error;

  Future<void> _run(Future<void> Function() f) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await f();
    } on ApiException catch (e) {
      HapticFeedback.heavyImpact();
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _check() => _run(() async {
    if (_code.text.trim().length < 8) throw ApiException('Enter the 8-character code.');
    final r = await AppScope.read(context).checkInvite(_code.text.trim());
    HapticFeedback.mediumImpact();
    setState(() => _who = r);
  });

  Future<void> _join() => _run(() async {
    if (_pass.text != _pass2.text) throw ApiException('The two passwords don\'t match.');
    final nav = Navigator.of(context);
    await AppScope.read(context).acceptInvite(_code.text.trim(), _pass.text);
    nav.popUntil((r) => r.isFirst);
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final who = _who;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          child: who == null
              ? TextField(
                  key: const ValueKey('code'),
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  onSubmitted: (_) => _check(),
                  style: const TextStyle(fontSize: 20, letterSpacing: 4, fontWeight: FontWeight.w700),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]')),
                    LengthLimitingTextInputFormatter(9),
                  ],
                  decoration: const InputDecoration(labelText: 'Invite code', hintText: 'ABCD-1234', prefixIcon: Icon(Icons.vpn_key_outlined)),
                )
              : Card(
                  key: const ValueKey('who'),
                  color: cs.primaryContainer.withValues(alpha: .5),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Initials(who['name'] as String, radius: 22),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Assalamu alaikum,', style: TextStyle(color: cs.onSurfaceVariant)),
                              Text(who['name'] as String, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 2),
                              Text('You\'ll sign in with ${who['login']}', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          child: who == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        who['reset'] == true ? 'Choose a new password' : 'Choose your password',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _pass,
                        obscureText: _hide,
                        autofillHints: const [AutofillHints.newPassword],
                        decoration: InputDecoration(
                          labelText: 'Password (8+ characters)',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            onPressed: () => setState(() => _hide = !_hide),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _pass2,
                        obscureText: _hide,
                        onSubmitted: (_) => _join(),
                        decoration: const InputDecoration(labelText: 'Repeat password', prefixIcon: Icon(Icons.lock_outline_rounded)),
                      ),
                    ],
                  ),
                ),
        ),
        _ErrorText(_error),
        FilledButton(
          onPressed: _busy ? null : (who == null ? _check : _join),
          child: _busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
              : Text(who == null ? 'Continue' : 'Join ${AppScope.of(context).shortName}'),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: widget.onBack, child: const Text('Back to sign in')),
      ],
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.error);
  final String? error;
  @override
  Widget build(BuildContext context) => AnimatedSize(
    duration: const Duration(milliseconds: 200),
    child: error == null
        ? const SizedBox(height: 20, width: double.infinity)
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Icon(Icons.error_outline_rounded, size: 18, color: Tones.red(context)),
                const SizedBox(width: 8),
                Expanded(child: Text(error!, style: TextStyle(color: Tones.red(context)))),
              ],
            ),
          ),
  );
}
