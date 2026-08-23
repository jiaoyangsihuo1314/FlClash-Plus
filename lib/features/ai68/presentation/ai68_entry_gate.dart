import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/features/ai68/api/ai68_api_models.dart';
import 'package:fl_clash/features/ai68/commercial/ai68_commercial_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _Ai68EntryPage { welcome, login, register }

class Ai68EntryGate extends ConsumerStatefulWidget {
  const Ai68EntryGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<Ai68EntryGate> createState() => _Ai68EntryGateState();
}

class _Ai68EntryGateState extends ConsumerState<Ai68EntryGate>
    with WidgetsBindingObserver {
  _Ai68EntryPage _page = _Ai68EntryPage.welcome;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.listenManual(ai68CommercialProvider, (previous, next) {
      if (previous?.phase != Ai68CommercialPhase.signedOut &&
          next.phase == Ai68CommercialPhase.signedOut) {
        setState(() => _page = _Ai68EntryPage.welcome);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ref.read(ai68CommercialProvider).isAuthenticated) {
      ref.read(ai68CommercialProvider.notifier).refresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ai68CommercialProvider);
    return switch (state.phase) {
      Ai68CommercialPhase.booting => const _Ai68LoadingPage(),
      Ai68CommercialPhase.failure => _Ai68FailurePage(
        message: state.errorMessage,
      ),
      Ai68CommercialPhase.localMode ||
      Ai68CommercialPhase.ready => widget.child,
      Ai68CommercialPhase.signedOut => switch (_page) {
        _Ai68EntryPage.welcome => Ai68WelcomePage(
          onLogin: () => setState(() => _page = _Ai68EntryPage.login),
        ),
        _Ai68EntryPage.login => Ai68LoginPage(
          onBack: () => setState(() => _page = _Ai68EntryPage.welcome),
          onRegister: () => setState(() => _page = _Ai68EntryPage.register),
        ),
        _Ai68EntryPage.register => Ai68RegisterPage(
          onBack: () => setState(() => _page = _Ai68EntryPage.login),
        ),
      },
    };
  }
}

class Ai68WelcomePage extends ConsumerWidget {
  const Ai68WelcomePage({super.key, required this.onLogin});

  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.appLocalizations;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                children: [
                  Image.asset(
                    'assets/images/icon.png',
                    width: 112,
                    height: 112,
                  ),
                  const SizedBox(height: 28),
                  Text(
                    l10n.ai68WelcomeTitle,
                    textAlign: TextAlign.center,
                    style: context.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l10n.ai68WelcomeSubtitle,
                    textAlign: TextAlign.center,
                    style: context.textTheme.titleMedium?.copyWith(
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 36),
                  _Ai68SetupStep(
                    icon: Icons.wifi_find,
                    label: l10n.ai68AutoDetectNetwork,
                  ),
                  const _Ai68StepDivider(),
                  _Ai68SetupStep(
                    icon: Icons.speed,
                    label: l10n.ai68AutoSelectNode,
                  ),
                  const _Ai68StepDivider(),
                  _Ai68SetupStep(
                    icon: Icons.check_circle,
                    label: l10n.ai68Complete,
                  ),
                  const SizedBox(height: 36),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton.icon(
                      onPressed: onLogin,
                      icon: const Icon(Icons.login),
                      label: Text(l10n.ai68LoginAccount),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () {
                      ref
                          .read(ai68CommercialProvider.notifier)
                          .continueLocalMode();
                    },
                    icon: const Icon(Icons.tune),
                    label: Text(l10n.ai68OpenManualMode),
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

class _Ai68SetupStep extends StatelessWidget {
  const _Ai68SetupStep({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, color: context.colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: context.textTheme.bodyLarge)),
        ],
      ),
    );
  }
}

class _Ai68StepDivider extends StatelessWidget {
  const _Ai68StepDivider();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: 2,
        height: 20,
        margin: const EdgeInsets.only(left: 21),
        color: context.colorScheme.outlineVariant,
      ),
    );
  }
}

class Ai68LoginPage extends ConsumerStatefulWidget {
  const Ai68LoginPage({
    super.key,
    required this.onBack,
    required this.onRegister,
  });

  final VoidCallback onBack;
  final VoidCallback onRegister;

  @override
  ConsumerState<Ai68LoginPage> createState() => _Ai68LoginPageState();
}

class _Ai68LoginPageState extends ConsumerState<Ai68LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_formKey.currentState?.validate() != true) return;
    FocusScope.of(context).unfocus();
    try {
      await ref
          .read(ai68CommercialProvider.notifier)
          .login(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final state = ref.watch(ai68CommercialProvider);
    return _Ai68AuthScaffold(
      title: l10n.ai68LoginAccount,
      onBack: widget.onBack,
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _emailController,
                autofillHints: const [AutofillHints.email],
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: l10n.ai68Email,
                  prefixIcon: const Icon(Icons.alternate_email),
                ),
                validator: (value) {
                  if (value == null || !value.contains('@')) {
                    return l10n.ai68Email;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                autofillHints: const [AutofillHints.password],
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: l10n.ai68Password,
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.length < 8) {
                    return l10n.ai68Password;
                  }
                  return null;
                },
              ),
              if (state.errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  state.errorMessage!,
                  style: TextStyle(color: context.colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: state.isAuthenticating ? null : _submit,
                  icon: state.isAuthenticating
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login),
                  label: Text(l10n.ai68Login),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: state.isAuthenticating ? null : widget.onRegister,
                child: Text(l10n.ai68CreateAccount),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class Ai68RegisterPage extends ConsumerStatefulWidget {
  const Ai68RegisterPage({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  ConsumerState<Ai68RegisterPage> createState() => _Ai68RegisterPageState();
}

class _Ai68RegisterPageState extends ConsumerState<Ai68RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailFieldKey = GlobalKey<FormFieldState<String>>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _inviteController = TextEditingController();
  final _emailCodeController = TextEditingController();
  final _captchaController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _sendingCode = false;
  bool _loadingGuestConfig = false;
  int _codeCooldown = 0;
  Timer? _codeTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshGuestConfig();
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _inviteController.dispose();
    _emailCodeController.dispose();
    _captchaController.dispose();
    _codeTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshGuestConfig() async {
    if (_loadingGuestConfig) return;
    setState(() => _loadingGuestConfig = true);
    await ref.read(ai68CommercialProvider.notifier).refreshGuestConfig();
    if (mounted) setState(() => _loadingGuestConfig = false);
  }

  Future<void> _sendCode() async {
    if (_emailFieldKey.currentState?.validate() != true) return;
    final config = ref.read(ai68CommercialProvider).guestConfig;
    if (config?.isEmailVerify != true || _codeCooldown > 0) return;
    final captchaTokens = _captchaTokens(config);
    if (config?.isCaptcha == true && _captchaController.text.trim().isEmpty) {
      return;
    }
    setState(() => _sendingCode = true);
    try {
      await ref
          .read(ai68CommercialProvider.notifier)
          .sendEmailVerification(
            _emailController.text.trim(),
            captchaTokens: captchaTokens,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.appLocalizations.ai68EmailCodeSent)),
      );
      _startCodeCooldown();
    } catch (_) {
      return;
    } finally {
      if (mounted) setState(() => _sendingCode = false);
    }
  }

  void _startCodeCooldown() {
    _codeTimer?.cancel();
    setState(() => _codeCooldown = 60);
    _codeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _codeCooldown <= 1) {
        timer.cancel();
        if (mounted) setState(() => _codeCooldown = 0);
        return;
      }
      setState(() => _codeCooldown -= 1);
    });
  }

  Future<void> _submit() async {
    if (_formKey.currentState?.validate() != true) return;
    FocusScope.of(context).unfocus();
    final config = ref.read(ai68CommercialProvider).guestConfig;
    if (config == null) return;
    final captchaTokens = _captchaTokens(config);
    try {
      await ref
          .read(ai68CommercialProvider.notifier)
          .register(
            Ai68RegisterRequest(
              email: _emailController.text.trim(),
              password: _passwordController.text,
              inviteCode: _emptyToNull(_inviteController.text),
              emailCode: _emptyToNull(_emailCodeController.text),
              recaptchaData: captchaTokens.recaptchaData,
              recaptchaV3Token: captchaTokens.recaptchaV3Token,
              turnstileToken: captchaTokens.turnstileToken,
            ),
          );
    } catch (_) {}
  }

  String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Ai68CaptchaTokens _captchaTokens(Ai68GuestConfig? config) {
    final token = _emptyToNull(_captchaController.text);
    final type = config?.captchaType.replaceAll('-', '_');
    return Ai68CaptchaTokens(
      recaptchaData: type == 'recaptcha' ? token : null,
      recaptchaV3Token: type == 'recaptcha_v3' ? token : null,
      turnstileToken: type == 'turnstile' ? token : null,
    );
  }

  String? _validateEmail(String? value, Ai68GuestConfig config) {
    final email = value?.trim() ?? '';
    final isValid = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
    if (!isValid) return context.appLocalizations.ai68EmailInvalid;
    final suffixes = config.emailWhitelistSuffixes
        .map(
          (suffix) =>
              suffix.trim().toLowerCase().replaceFirst(RegExp(r'^@'), ''),
        )
        .where((suffix) => suffix.isNotEmpty)
        .toSet();
    if (suffixes.isEmpty) return null;
    final domain = email.split('@').last.toLowerCase();
    if (!suffixes.contains(domain)) {
      return context.appLocalizations.ai68EmailDomainRestricted(
        suffixes.join(', '),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final state = ref.watch(ai68CommercialProvider);
    final config = state.guestConfig;
    return _Ai68AuthScaffold(
      title: l10n.ai68CreateAccount,
      onBack: widget.onBack,
      child: config == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_loadingGuestConfig) const LinearProgressIndicator(),
                if (state.errorMessage != null) ...[
                  Text(
                    state.errorMessage!,
                    style: TextStyle(color: context.colorScheme.error),
                  ),
                  const SizedBox(height: 16),
                ],
                OutlinedButton.icon(
                  onPressed: _loadingGuestConfig ? null : _refreshGuestConfig,
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.ai68LoadRegistrationSettings),
                ),
              ],
            )
          : AutofillGroup(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      key: _emailFieldKey,
                      controller: _emailController,
                      autofillHints: const [AutofillHints.email],
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: l10n.ai68Email,
                        prefixIcon: const Icon(Icons.alternate_email),
                      ),
                      validator: (value) => _validateEmail(value, config),
                    ),
                    if (config.isEmailVerify) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _emailCodeController,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: l10n.ai68EmailCode,
                          prefixIcon: const Icon(
                            Icons.mark_email_read_outlined,
                          ),
                          suffixIcon: TextButton(
                            onPressed: _sendingCode || _codeCooldown > 0
                                ? null
                                : _sendCode,
                            child: Text(
                              _codeCooldown > 0
                                  ? l10n.ai68ResendCode(_codeCooldown)
                                  : l10n.ai68SendCode,
                            ),
                          ),
                        ),
                        validator: (value) {
                          return value == null || value.trim().isEmpty
                              ? l10n.ai68EmailCode
                              : null;
                        },
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      autofillHints: const [AutofillHints.newPassword],
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: l10n.ai68Password,
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () {
                            setState(
                              () => _obscurePassword = !_obscurePassword,
                            );
                          },
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (value) {
                        return value != null && value.length >= 8
                            ? null
                            : l10n.ai68PasswordRequirement;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmPasswordController,
                      autofillHints: const [AutofillHints.newPassword],
                      obscureText: _obscureConfirmPassword,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: l10n.ai68ConfirmPassword,
                        prefixIcon: const Icon(Icons.lock_reset_outlined),
                        suffixIcon: IconButton(
                          onPressed: () {
                            setState(
                              () => _obscureConfirmPassword =
                                  !_obscureConfirmPassword,
                            );
                          },
                          icon: Icon(
                            _obscureConfirmPassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return l10n.ai68ConfirmPassword;
                        }
                        return value == _passwordController.text
                            ? null
                            : l10n.ai68PasswordMismatch;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _inviteController,
                      textInputAction: config.isCaptcha
                          ? TextInputAction.next
                          : TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: config.isInviteForce
                            ? l10n.ai68InviteCode
                            : '${l10n.ai68InviteCode} (${l10n.ai68Optional})',
                        prefixIcon: const Icon(Icons.card_giftcard),
                      ),
                      validator: (value) {
                        if (!config.isInviteForce) return null;
                        return value == null || value.trim().isEmpty
                            ? l10n.ai68InviteCode
                            : null;
                      },
                    ),
                    if (config.isCaptcha) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _captchaController,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: config.captchaType,
                          prefixIcon: const Icon(Icons.verified_user_outlined),
                        ),
                        validator: (value) {
                          return value == null || value.trim().isEmpty
                              ? config.captchaType
                              : null;
                        },
                      ),
                    ],
                    if (state.errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        state.errorMessage!,
                        style: TextStyle(color: context.colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: state.isAuthenticating ? null : _submit,
                        icon: state.isAuthenticating
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.person_add_alt_1),
                        label: Text(l10n.ai68Register),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: state.isAuthenticating ? null : widget.onBack,
                      child: Text(l10n.ai68BackToLogin),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _Ai68AuthScaffold extends StatelessWidget {
  const _Ai68AuthScaffold({
    required this.title,
    required this.onBack,
    required this.child,
  });

  final String title;
  final VoidCallback onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: onBack,
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(title),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(padding: const EdgeInsets.all(24), child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Ai68LoadingPage extends StatelessWidget {
  const _Ai68LoadingPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/icon.png', width: 80, height: 80),
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

class _Ai68FailurePage extends ConsumerWidget {
  const _Ai68FailurePage({this.message});

  final String? message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.appLocalizations;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_off,
                  size: 54,
                  color: context.colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  message ?? l10n.unknownNetworkError,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () {
                    ref.read(ai68CommercialProvider.notifier).retryBootstrap();
                  },
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.ai68Retry),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    ref
                        .read(ai68CommercialProvider.notifier)
                        .continueLocalMode();
                  },
                  child: Text(l10n.ai68OpenManualMode),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
