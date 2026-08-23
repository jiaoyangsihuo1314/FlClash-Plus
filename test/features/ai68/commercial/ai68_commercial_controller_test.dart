import 'dart:async';

import 'package:fl_clash/features/ai68/api/ai68_api_client.dart';
import 'package:fl_clash/features/ai68/api/ai68_api_exception.dart';
import 'package:fl_clash/features/ai68/api/ai68_api_models.dart';
import 'package:fl_clash/features/ai68/auth/ai68_auth_providers.dart';
import 'package:fl_clash/features/ai68/auth/ai68_session.dart';
import 'package:fl_clash/features/ai68/commercial/ai68_commercial_controller.dart';
import 'package:fl_clash/features/ai68/subscription/ai68_managed_profile.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../support/fakes.dart';

void main() {
  setUpAll(() {
    registerFallbackValue(const Ai68CaptchaTokens());
  });

  late _MockAi68Api api;
  late MemoryAi68TokenStore tokenStore;
  late _ControllableSetupAction setupAction;
  late _ControllableProfilesAction profilesAction;
  late _MemoryManagedProfileStore profileStore;
  late _RecordingProfileSynchronizer profileSynchronizer;
  late ProviderContainer container;
  late Ai68CommercialController controller;
  late int userFetchCount;
  late Future<Ai68User> Function(int callCount) userResponder;

  const session = Ai68Session(
    apiAuthorization: 'Bearer api-secret',
    subscriptionToken: 'subscription-secret',
    isAdmin: false,
  );
  const user = Ai68User(
    email: 'user@example.com',
    transferEnableBytes: 100,
    banned: false,
    remindExpire: true,
    remindTraffic: true,
    balanceCents: 0,
    commissionBalanceCents: 0,
  );

  setUp(() async {
    api = _MockAi68Api();
    tokenStore = MemoryAi68TokenStore();
    setupAction = _ControllableSetupAction();
    profilesAction = _ControllableProfilesAction();
    profileStore = _MemoryManagedProfileStore();
    profileSynchronizer = _RecordingProfileSynchronizer();
    userFetchCount = 0;
    userResponder = (_) async => user;

    final subscription = Ai68Subscription(
      subscriptionToken: session.subscriptionToken,
      subscribeUrl: Uri.parse('https://mingjie-panel.ai68ai.cn/s/test'),
      uploadBytes: 50,
      downloadBytes: 50,
      transferEnableBytes: 100,
    );

    when(
      () => api.login(email: 'user@example.com', password: 'password123'),
    ).thenAnswer((_) async => session);
    when(api.fetchUserInfo).thenAnswer((_) {
      userFetchCount += 1;
      return userResponder(userFetchCount);
    });
    when(api.fetchSubscription).thenAnswer((_) async => subscription);
    when(() => api.fetchPlans()).thenAnswer((_) async => const []);
    when(() => api.fetchOrders()).thenAnswer((_) async => const []);
    when(
      () => api.fetchNotices(page: any(named: 'page')),
    ).thenAnswer((_) async => const Ai68NoticePage(items: [], total: 0));
    when(api.fetchServers).thenAnswer((_) async => const []);

    container = ProviderContainer(
      overrides: [
        ai68ApiProvider.overrideWithValue(api),
        ai68TokenStoreProvider.overrideWithValue(tokenStore),
        setupActionProvider.overrideWith(() => setupAction),
        profilesActionProvider.overrideWith(() => profilesAction),
        ai68ManagedProfileStoreProvider.overrideWithValue(profileStore),
        ai68ProfileSynchronizerProvider.overrideWithValue(profileSynchronizer),
      ],
    );
    addTearDown(container.dispose);
    controller = container.read(ai68CommercialProvider.notifier);
    await controller.login(email: 'user@example.com', password: 'password123');
    expect(container.read(ai68CommercialProvider).isAuthenticated, isTrue);
    expect(tokenStore.session, isNotNull);
  });

  test(
    'logout clears tokens when proxy stop and profile deletion fail',
    () async {
      setupAction.failStop = true;
      profilesAction.failDelete = true;
      profileStore.profileId = 42;

      await controller.logout();

      final state = container.read(ai68CommercialProvider);
      expect(state.phase, Ai68CommercialPhase.signedOut);
      expect(state.user, isNull);
      expect(state.errorMessage, contains('stop failed'));
      expect(tokenStore.session, isNull);
      expect(tokenStore.clearCount, 1);
      expect(profilesAction.deletedProfileIds, [42]);
      expect(profileSynchronizer.clearCount, 1);
    },
  );

  test(
    'refresh and logout are serialized without reviving the session',
    () async {
      final refreshStarted = Completer<void>();
      final releaseRefresh = Completer<void>();
      userResponder = (callCount) async {
        if (callCount >= 3) {
          if (!refreshStarted.isCompleted) refreshStarted.complete();
          await releaseRefresh.future;
        }
        return user;
      };

      final refreshFuture = controller.refresh();
      await refreshStarted.future;
      var logoutCompleted = false;
      final logoutFuture = controller.logout().whenComplete(() {
        logoutCompleted = true;
      });
      await Future<void>.delayed(Duration.zero);

      expect(logoutCompleted, isFalse);
      expect(tokenStore.session, isNotNull);

      releaseRefresh.complete();
      await Future.wait([refreshFuture, logoutFuture]);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(ai68CommercialProvider);
      expect(state.phase, Ai68CommercialPhase.signedOut);
      expect(state.user, isNull);
      expect(tokenStore.session, isNull);
      expect(tokenStore.clearCount, 1);
    },
  );

  test('missing restored session still removes managed profile', () async {
    await tokenStore.clear();
    setupAction.failStop = true;
    profileStore.profileId = 42;

    await controller.bootstrap();

    final state = container.read(ai68CommercialProvider);
    expect(state.phase, Ai68CommercialPhase.signedOut);
    expect(state.user, isNull);
    expect(profilesAction.deletedProfileIds, [42]);
    expect(profileSynchronizer.clearCount, 1);
  });

  test('authentication failure during refresh signs the user out', () async {
    userResponder = (callCount) async {
      if (callCount >= 3) {
        throw const Ai68ApiException(
          message: 'Session expired',
          statusCode: 401,
        );
      }
      return user;
    };

    await controller.refresh();

    final state = container.read(ai68CommercialProvider);
    expect(state.phase, Ai68CommercialPhase.signedOut);
    expect(state.user, isNull);
    expect(state.subscription, isNull);
    expect(state.errorMessage, 'Session expired');
    expect(tokenStore.session, isNull);
    expect(tokenStore.clearCount, 1);
  });

  test(
    'email verification errors remain visible on the registration form',
    () async {
      when(
        () => api.sendEmailVerification(
          email: 'user@example.com',
          captchaTokens: any(named: 'captchaTokens'),
        ),
      ).thenThrow(const Ai68ApiException(message: 'Email delivery failed'));

      await expectLater(
        controller.sendEmailVerification('user@example.com'),
        throwsA(isA<Ai68ApiException>()),
      );

      expect(
        container.read(ai68CommercialProvider).errorMessage,
        'Email delivery failed',
      );
    },
  );

  test(
    'authentication failure during restore removes managed profile',
    () async {
      profileStore.profileId = 42;
      userResponder = (callCount) async {
        if (callCount >= 3) {
          throw const Ai68ApiException(
            message: 'Session expired',
            statusCode: 401,
          );
        }
        return user;
      };

      await controller.bootstrap();

      final state = container.read(ai68CommercialProvider);
      expect(state.phase, Ai68CommercialPhase.signedOut);
      expect(state.user, isNull);
      expect(tokenStore.session, isNull);
      expect(profilesAction.deletedProfileIds, [42]);
      expect(profileSynchronizer.clearCount, 1);
    },
  );
}

final class _MockAi68Api extends Mock implements Ai68Api {}

final class _ControllableSetupAction extends SetupAction {
  bool failStop = false;
  int stopCount = 0;

  @override
  Future<void> setRunning(
    bool running, {
    bool initialize = false,
    bool requireSuccess = false,
  }) async {
    if (running) return;
    stopCount += 1;
    if (failStop) throw StateError('stop failed');
  }
}

final class _ControllableProfilesAction extends ProfilesAction {
  bool failDelete = false;
  final deletedProfileIds = <int>[];

  @override
  Future<void> deleteProfile(int id) async {
    deletedProfileIds.add(id);
    if (failDelete) throw StateError('delete failed');
  }
}

final class _MemoryManagedProfileStore implements Ai68ManagedProfileStore {
  int? profileId;

  @override
  Future<void> clear() async {
    profileId = null;
  }

  @override
  Future<int?> readProfileId() async {
    return profileId;
  }

  @override
  Future<void> writeProfileId(int profileId) async {
    this.profileId = profileId;
  }
}

final class _RecordingProfileSynchronizer implements Ai68ProfileSynchronizer {
  int clearCount = 0;

  @override
  Future<void> clear() async {
    clearCount += 1;
  }

  @override
  Future<Profile> synchronize({
    required Ai68Subscription subscription,
    required List<Profile> profiles,
    required String userAgent,
  }) {
    throw StateError('unexpected profile synchronization');
  }
}
