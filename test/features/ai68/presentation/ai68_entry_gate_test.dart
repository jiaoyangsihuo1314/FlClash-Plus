import 'package:fl_clash/features/ai68/api/ai68_api_client.dart';
import 'package:fl_clash/features/ai68/api/ai68_api_exception.dart';
import 'package:fl_clash/features/ai68/api/ai68_api_models.dart';
import 'package:fl_clash/features/ai68/auth/ai68_auth_providers.dart';
import 'package:fl_clash/features/ai68/commercial/ai68_commercial_controller.dart';
import 'package:fl_clash/features/ai68/presentation/ai68_entry_gate.dart';
import 'package:fl_clash/features/ai68/subscription/ai68_managed_profile.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../support/fakes.dart';

void main() {
  setUpAll(() {
    registerFallbackValue(
      const Ai68RegisterRequest(email: 'fallback@example.com', password: 'x'),
    );
    registerFallbackValue(const Ai68CaptchaTokens());
  });

  testWidgets('signed-out entry shows the guided AI68 setup flow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _MockAi68Api();
    when(api.fetchGuestConfig).thenAnswer(
      (_) async => const Ai68GuestConfig(
        isEmailVerify: false,
        isInviteForce: false,
        isCaptcha: false,
        captchaType: 'recaptcha',
        emailWhitelistSuffixes: [],
      ),
    );
    final container = ProviderContainer(
      overrides: [
        ai68ApiProvider.overrideWithValue(api),
        ai68TokenStoreProvider.overrideWithValue(MemoryAi68TokenStore()),
        ai68ManagedProfileStoreProvider.overrideWithValue(
          _EmptyManagedProfileStore(),
        ),
        setupActionProvider.overrideWith(_EntryGateSetupAction.new),
      ],
    );
    addTearDown(container.dispose);
    await container.read(ai68CommercialProvider.notifier).bootstrap();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _TestApp(
          child: Ai68EntryGate(child: SizedBox(key: Key('home'))),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Welcome to FlClash Plus'), findsOneWidget);
    expect(find.text('Finish setup in one minute'), findsOneWidget);
    expect(find.text('Detect network automatically'), findsOneWidget);
    expect(find.text('Select the best node automatically'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Sign in to AI68'), findsOneWidget);
    expect(find.byKey(const Key('home')), findsNothing);
    expect(tester.takeException(), null);

    await tester.tap(find.text('Sign in to AI68'));
    await tester.pump();

    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('Create AI68 account'), findsOneWidget);
    expect(tester.takeException(), null);
  });

  testWidgets('registration follows XBoard email verification settings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _MockAi68Api();
    when(api.fetchGuestConfig).thenAnswer(
      (_) async => const Ai68GuestConfig(
        isEmailVerify: true,
        isInviteForce: false,
        isCaptcha: false,
        captchaType: 'recaptcha',
        emailWhitelistSuffixes: ['example.com'],
      ),
    );
    when(
      () => api.sendEmailVerification(
        email: 'user@example.com',
        captchaTokens: any(named: 'captchaTokens'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => api.register(any()),
    ).thenThrow(const Ai68ApiException(message: 'Registration captured'));
    final container = ProviderContainer(
      overrides: [
        ai68ApiProvider.overrideWithValue(api),
        ai68TokenStoreProvider.overrideWithValue(MemoryAi68TokenStore()),
        ai68ManagedProfileStoreProvider.overrideWithValue(
          _EmptyManagedProfileStore(),
        ),
        setupActionProvider.overrideWith(_EntryGateSetupAction.new),
      ],
    );
    addTearDown(container.dispose);
    await container.read(ai68CommercialProvider.notifier).bootstrap();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _TestApp(
          child: Ai68EntryGate(child: SizedBox(key: Key('home'))),
        ),
      ),
    );
    await tester.tap(find.text('Sign in to AI68'));
    await tester.pump();
    await tester.tap(find.text('Create AI68 account'));
    await tester.pump();

    expect(find.byType(TextFormField), findsNWidgets(5));
    expect(find.text('Email verification code'), findsOneWidget);
    expect(find.text('Confirm password'), findsOneWidget);
    expect(find.text('Invite code (optional)'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'user@invalid.test',
    );
    await tester.tap(find.text('Send code'));
    await tester.pump();
    expect(find.text('Allowed email domains: example.com'), findsOneWidget);
    verifyNever(
      () => api.sendEmailVerification(
        email: any(named: 'email'),
        captchaTokens: any(named: 'captchaTokens'),
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'user@example.com',
    );
    await tester.tap(find.text('Send code'));
    await tester.pump();
    verify(
      () => api.sendEmailVerification(
        email: 'user@example.com',
        captchaTokens: any(named: 'captchaTokens'),
      ),
    ).called(1);
    expect(find.text('Verification code sent'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email verification code'),
      '123456',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'password123',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirm password'),
      'different123',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Invite code (optional)'),
      'INVITE',
    );
    await tester.ensureVisible(find.text('Register'));
    await tester.tap(find.text('Register'));
    await tester.pump();
    expect(find.text('The passwords do not match'), findsOneWidget);
    verifyNever(() => api.register(any()));

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirm password'),
      'password123',
    );
    await tester.tap(find.text('Register'));
    await tester.pump();

    final request =
        verify(() => api.register(captureAny())).captured.single
            as Ai68RegisterRequest;
    expect(request.email, 'user@example.com');
    expect(request.password, 'password123');
    expect(request.emailCode, '123456');
    expect(request.inviteCode, 'INVITE');
    expect(tester.takeException(), null);
  });

  testWidgets('email code stays hidden when XBoard disables verification', (
    tester,
  ) async {
    final api = _MockAi68Api();
    when(api.fetchGuestConfig).thenAnswer(
      (_) async => const Ai68GuestConfig(
        isEmailVerify: false,
        isInviteForce: false,
        isCaptcha: false,
        captchaType: 'recaptcha',
        emailWhitelistSuffixes: [],
      ),
    );
    final container = ProviderContainer(
      overrides: [
        ai68ApiProvider.overrideWithValue(api),
        ai68TokenStoreProvider.overrideWithValue(MemoryAi68TokenStore()),
        ai68ManagedProfileStoreProvider.overrideWithValue(
          _EmptyManagedProfileStore(),
        ),
        setupActionProvider.overrideWith(_EntryGateSetupAction.new),
      ],
    );
    addTearDown(container.dispose);
    await container.read(ai68CommercialProvider.notifier).bootstrap();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _TestApp(child: Ai68RegisterPage(onBack: _noop)),
      ),
    );
    await tester.pump();

    expect(find.byType(TextFormField), findsNWidgets(4));
    expect(find.text('Email verification code'), findsNothing);
    expect(find.text('Confirm password'), findsOneWidget);
    expect(find.text('Invite code (optional)'), findsOneWidget);
    expect(tester.takeException(), null);
  });
}

void _noop() {}

final class _MockAi68Api extends Mock implements Ai68Api {}

final class _EmptyManagedProfileStore implements Ai68ManagedProfileStore {
  @override
  Future<void> clear() async {}

  @override
  Future<int?> readProfileId() async => null;

  @override
  Future<void> writeProfileId(int profileId) async {}
}

final class _EntryGateSetupAction extends SetupAction {
  @override
  Future<void> setRunning(
    bool running, {
    bool initialize = false,
    bool requireSuccess = false,
  }) async {}
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.delegate.supportedLocales,
      home: child,
    );
  }
}
