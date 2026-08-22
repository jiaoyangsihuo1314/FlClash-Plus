import 'package:fl_clash/features/ai68/api/ai68_api_client.dart';
import 'package:fl_clash/features/ai68/api/ai68_api_exception.dart';
import 'package:fl_clash/features/ai68/api/ai68_api_models.dart';
import 'package:fl_clash/features/ai68/auth/ai68_auth_repository.dart';
import 'package:fl_clash/features/ai68/auth/ai68_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../support/fakes.dart';

void main() {
  late MockAi68Api api;
  late MemoryAi68TokenStore tokenStore;
  late Ai68AuthRepository repository;

  const session = Ai68Session(
    apiAuthorization: 'Bearer api-secret',
    subscriptionToken: 'subscription-secret',
    isAdmin: false,
  );
  const user = Ai68User(
    email: 'user@example.com',
    transferEnableBytes: 10,
    banned: false,
    remindExpire: true,
    remindTraffic: true,
    balanceCents: 0,
    commissionBalanceCents: 0,
  );

  setUp(() {
    api = MockAi68Api();
    tokenStore = MemoryAi68TokenStore();
    repository = Ai68AuthRepository(api: api, tokenStore: tokenStore);
  });

  test('login persists secure session and loads the user', () async {
    when(
      () => api.login(email: 'user@example.com', password: 'password123'),
    ).thenAnswer((_) async => session);
    when(api.fetchUserInfo).thenAnswer((_) async => user);

    final result = await repository.login(
      email: 'user@example.com',
      password: 'password123',
    );

    expect(result.session, same(session));
    expect(result.user, same(user));
    expect(tokenStore.session, same(session));
    expect(tokenStore.writeCount, 1);
  });

  test('restore clears an expired session', () async {
    tokenStore.session = session;
    when(
      api.fetchUserInfo,
    ).thenThrow(const Ai68ApiException(message: 'Expired', statusCode: 403));

    final result = await repository.restoreSession();

    expect(result, isNull);
    expect(tokenStore.session, isNull);
    expect(tokenStore.clearCount, 1);
  });

  test('restore keeps session on temporary failures', () async {
    tokenStore.session = session;
    when(
      api.fetchUserInfo,
    ).thenThrow(const Ai68ApiException(message: 'Offline'));

    await expectLater(
      repository.restoreSession(),
      throwsA(isA<Ai68ApiException>()),
    );

    expect(tokenStore.session, same(session));
    expect(tokenStore.clearCount, 0);
  });

  test('subscription refresh rotates only subscription token', () async {
    tokenStore.session = session;
    final subscription = Ai68Subscription(
      subscriptionToken: 'rotated-subscription-secret',
      subscribeUrl: Uri.parse('https://example.com/s/new-token'),
      uploadBytes: 1,
      downloadBytes: 2,
      transferEnableBytes: 100,
    );
    when(api.fetchSubscription).thenAnswer((_) async => subscription);

    final result = await repository.refreshSubscription();

    expect(result, same(subscription));
    expect(tokenStore.session?.apiAuthorization, 'Bearer api-secret');
    expect(
      tokenStore.session?.subscriptionToken,
      'rotated-subscription-secret',
    );
  });
}

final class MockAi68Api extends Mock implements Ai68Api {}
