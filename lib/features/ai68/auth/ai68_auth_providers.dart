import 'package:fl_clash/features/ai68/api/ai68_api_client.dart';
import 'package:fl_clash/features/ai68/auth/ai68_auth_repository.dart';
import 'package:fl_clash/features/ai68/auth/ai68_token_store.dart';
import 'package:fl_clash/features/ai68/storage/ai68_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final ai68TokenStoreProvider = Provider<Ai68TokenStore>((ref) {
  if (useAi68MacOsTestStorage) {
    return SharedPreferencesAi68TokenStore();
  }
  return FlutterSecureAi68TokenStore();
});

final ai68ApiProvider = Provider<Ai68Api>((ref) {
  final api = Ai68ApiClient(tokenStore: ref.watch(ai68TokenStoreProvider));
  ref.onDispose(api.close);
  return api;
});

final ai68AuthRepositoryProvider = Provider<Ai68AuthRepository>((ref) {
  return Ai68AuthRepository(
    api: ref.watch(ai68ApiProvider),
    tokenStore: ref.watch(ai68TokenStoreProvider),
  );
});
