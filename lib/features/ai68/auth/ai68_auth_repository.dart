import 'package:fl_clash/features/ai68/api/ai68_api_client.dart';
import 'package:fl_clash/features/ai68/api/ai68_api_exception.dart';
import 'package:fl_clash/features/ai68/api/ai68_api_models.dart';
import 'package:fl_clash/features/ai68/auth/ai68_session.dart';
import 'package:fl_clash/features/ai68/auth/ai68_token_store.dart';

final class Ai68AuthenticatedSession {
  const Ai68AuthenticatedSession({required this.session, required this.user});

  final Ai68Session session;
  final Ai68User user;
}

final class Ai68AuthRepository {
  const Ai68AuthRepository({
    required Ai68Api api,
    required Ai68TokenStore tokenStore,
  }) : _api = api,
       _tokenStore = tokenStore;

  final Ai68Api _api;
  final Ai68TokenStore _tokenStore;

  Future<Ai68AuthenticatedSession> login({
    required String email,
    required String password,
  }) async {
    final session = await _api.login(email: email, password: password);
    return _activate(session);
  }

  Future<Ai68AuthenticatedSession> register(Ai68RegisterRequest request) async {
    final session = await _api.register(request);
    return _activate(session);
  }

  Future<Ai68AuthenticatedSession?> restoreSession() async {
    final session = await _tokenStore.readSession();
    if (session == null) return null;
    try {
      final user = await _api.fetchUserInfo();
      return Ai68AuthenticatedSession(session: session, user: user);
    } on Ai68ApiException catch (error) {
      if (!error.isAuthenticationFailure) rethrow;
      await _tokenStore.clear();
      return null;
    }
  }

  Future<Ai68Subscription> refreshSubscription() async {
    final session = await _tokenStore.readSession();
    if (session == null) {
      throw const Ai68ApiException(
        message: 'AI68 authentication is required',
        statusCode: 401,
      );
    }
    final subscription = await _api.fetchSubscription();
    if (subscription.subscriptionToken != session.subscriptionToken) {
      await _tokenStore.writeSession(
        Ai68Session(
          apiAuthorization: session.apiAuthorization,
          subscriptionToken: subscription.subscriptionToken,
          isAdmin: session.isAdmin,
        ),
      );
    }
    return subscription;
  }

  Future<void> logout() {
    return _tokenStore.clear();
  }

  Future<Ai68AuthenticatedSession> _activate(Ai68Session session) async {
    await _tokenStore.writeSession(session);
    try {
      final user = await _api.fetchUserInfo();
      return Ai68AuthenticatedSession(session: session, user: user);
    } on Ai68ApiException catch (error) {
      if (error.isAuthenticationFailure) {
        await _tokenStore.clear();
      }
      rethrow;
    }
  }
}
