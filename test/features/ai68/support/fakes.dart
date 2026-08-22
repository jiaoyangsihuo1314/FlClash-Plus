import 'package:fl_clash/features/ai68/auth/ai68_session.dart';
import 'package:fl_clash/features/ai68/auth/ai68_token_store.dart';

final class MemoryAi68TokenStore implements Ai68TokenStore {
  Ai68Session? session;
  int clearCount = 0;
  int writeCount = 0;

  @override
  Future<void> clear() async {
    clearCount += 1;
    session = null;
  }

  @override
  Future<String?> readApiAuthorization() async {
    return session?.apiAuthorization;
  }

  @override
  Future<Ai68Session?> readSession() async {
    return session;
  }

  @override
  Future<String?> readSubscriptionToken() async {
    return session?.subscriptionToken;
  }

  @override
  Future<void> writeSession(Ai68Session value) async {
    writeCount += 1;
    session = value;
  }
}
