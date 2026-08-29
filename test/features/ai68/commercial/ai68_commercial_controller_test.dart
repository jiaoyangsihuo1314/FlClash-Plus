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
    when(api.fetchUserConfig).thenAnswer(
      (_) async => const Ai68UserConfig(
        withdrawMethods: ['Alipay'],
        withdrawClosed: false,
        currency: 'CNY',
        currencySymbol: '¥',
        commissionDistributionEnabled: false,
        commissionDistributionRates: [0, 0, 0],
      ),
    );
    when(api.fetchInviteOverview).thenAnswer(
      (_) async => const Ai68InviteOverview(
        codes: [],
        stats: Ai68InviteStats(
          registeredUsers: 0,
          cumulativeCommissionCents: 0,
          pendingCommissionCents: 0,
          commissionRate: 10,
          availableCommissionCents: 0,
        ),
      ),
    );
    when(
      () => api.fetchCommissionLogs(
        page: any(named: 'page'),
        pageSize: any(named: 'pageSize'),
      ),
    ).thenAnswer((_) async => const Ai68CommissionPage(items: [], total: 0));

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
      expect(state.errorMessage, '操作失败，请稍后重试');
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
    expect(state.errorMessage, '登录状态已过期，请重新登录');
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
        '邮件发送失败，请稍后重试',
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

  test('generates invitation codes and transfers commission', () async {
    var overview = const Ai68InviteOverview(
      codes: [],
      stats: Ai68InviteStats(
        registeredUsers: 1,
        cumulativeCommissionCents: 500,
        pendingCommissionCents: 100,
        commissionRate: 10,
        availableCommissionCents: 500,
      ),
    );
    when(api.generateInviteCode).thenAnswer((_) async {
      overview = Ai68InviteOverview(
        codes: const [Ai68InviteCode(code: 'INVITE68', views: 0, used: false)],
        stats: overview.stats,
      );
    });
    when(api.fetchInviteOverview).thenAnswer((_) async => overview);
    when(() => api.transferCommission(200)).thenAnswer((_) async {
      overview = const Ai68InviteOverview(
        codes: [Ai68InviteCode(code: 'INVITE68', views: 0, used: false)],
        stats: Ai68InviteStats(
          registeredUsers: 1,
          cumulativeCommissionCents: 500,
          pendingCommissionCents: 100,
          commissionRate: 10,
          availableCommissionCents: 300,
        ),
      );
    });

    expect(await controller.generateInviteCode(), isTrue);
    expect(
      container.read(ai68CommercialProvider).inviteOverview?.codes.single.code,
      'INVITE68',
    );
    expect(await controller.transferCommission(200), isTrue);
    expect(
      container
          .read(ai68CommercialProvider)
          .inviteOverview
          ?.stats
          .availableCommissionCents,
      300,
    );
    verify(api.generateInviteCode).called(1);
    verify(() => api.transferCommission(200)).called(1);
  });

  test('changes password while preserving the active session', () async {
    when(
      () => api.changePassword(
        oldPassword: 'password123',
        newPassword: 'new-password123',
      ),
    ).thenAnswer((_) async {});

    final changed = await controller.changePassword(
      oldPassword: 'password123',
      newPassword: 'new-password123',
    );

    final state = container.read(ai68CommercialProvider);
    expect(changed, isTrue);
    expect(state.isAuthenticated, isTrue);
    expect(state.isChangingPassword, isFalse);
    expect(state.errorMessage, isNull);
    expect(tokenStore.session, session);
    verify(
      () => api.changePassword(
        oldPassword: 'password123',
        newPassword: 'new-password123',
      ),
    ).called(1);
  });

  test('reports password change failures without ending the session', () async {
    when(
      () => api.changePassword(
        oldPassword: 'wrong-password',
        newPassword: 'new-password123',
      ),
    ).thenThrow(const Ai68ApiException(message: 'Old password is wrong'));

    final changed = await controller.changePassword(
      oldPassword: 'wrong-password',
      newPassword: 'new-password123',
    );

    final state = container.read(ai68CommercialProvider);
    expect(changed, isFalse);
    expect(state.isAuthenticated, isTrue);
    expect(state.isChangingPassword, isFalse);
    expect(state.errorMessage, '旧密码错误');
    expect(tokenStore.session, session);
  });
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
