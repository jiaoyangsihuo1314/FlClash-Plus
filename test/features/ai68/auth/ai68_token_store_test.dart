import 'package:fl_clash/features/ai68/auth/ai68_session.dart';
import 'package:fl_clash/features/ai68/auth/ai68_token_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  test('stores credentials only in secure storage and clears them', () async {
    final store = FlutterSecureAi68TokenStore();
    const session = Ai68Session(
      apiAuthorization: 'Bearer api-secret',
      subscriptionToken: 'subscription-secret',
      isAdmin: true,
    );

    await store.writeSession(session);

    final restored = await store.readSession();
    expect(restored?.apiAuthorization, session.apiAuthorization);
    expect(restored?.subscriptionToken, session.subscriptionToken);
    expect(restored?.isAdmin, isTrue);

    await store.clear();
    expect(await store.readSession(), isNull);
  });

  test('removes a partial session instead of accepting it', () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{
      'ai68.api.authorization': 'Bearer api-secret',
    });
    final store = FlutterSecureAi68TokenStore();

    expect(await store.readSession(), isNull);
    expect(await store.readApiAuthorization(), isNull);
  });

  test('attempts every credential deletion after one key fails', () async {
    final storage = _DeleteRecordingStorage();
    final store = FlutterSecureAi68TokenStore(storage: storage);

    await expectLater(store.clear(), throwsStateError);

    expect(storage.deletedKeys, [
      'ai68.api.authorization',
      'ai68.subscription.token',
      'ai68.session.is_admin',
    ]);
  });
}

final class _DeleteRecordingStorage extends FlutterSecureStorage {
  final deletedKeys = <String>[];

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    deletedKeys.add(key);
    if (deletedKeys.length == 1) throw StateError('delete failed');
  }
}
