import 'package:fl_clash/features/ai68/auth/ai68_session.dart';
import 'package:fl_clash/features/ai68/storage/ai68_secure_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class Ai68TokenStore {
  Future<String?> readApiAuthorization();

  Future<String?> readSubscriptionToken();

  Future<Ai68Session?> readSession();

  Future<void> writeSession(Ai68Session session);

  Future<void> clear();
}

final class FlutterSecureAi68TokenStore implements Ai68TokenStore {
  FlutterSecureAi68TokenStore({FlutterSecureStorage? storage})
    : _storage = storage ?? ai68SecureStorage;

  static const _apiAuthorizationKey = 'ai68.api.authorization';
  static const _subscriptionTokenKey = 'ai68.subscription.token';
  static const _isAdminKey = 'ai68.session.is_admin';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readApiAuthorization() {
    return _storage.read(key: _apiAuthorizationKey);
  }

  @override
  Future<String?> readSubscriptionToken() {
    return _storage.read(key: _subscriptionTokenKey);
  }

  @override
  Future<Ai68Session?> readSession() async {
    final apiAuthorization = await readApiAuthorization();
    final subscriptionToken = await readSubscriptionToken();
    if (apiAuthorization == null || subscriptionToken == null) {
      if (apiAuthorization != null || subscriptionToken != null) {
        await clear();
      }
      return null;
    }
    final isAdmin = await _storage.read(key: _isAdminKey);
    return Ai68Session(
      apiAuthorization: apiAuthorization,
      subscriptionToken: subscriptionToken,
      isAdmin: isAdmin == 'true',
    );
  }

  @override
  Future<void> writeSession(Ai68Session session) async {
    try {
      await _storage.write(
        key: _apiAuthorizationKey,
        value: session.apiAuthorization,
      );
      await _storage.write(
        key: _subscriptionTokenKey,
        value: session.subscriptionToken,
      );
      await _storage.write(key: _isAdminKey, value: session.isAdmin.toString());
    } catch (_) {
      await clear();
      rethrow;
    }
  }

  @override
  Future<void> clear() async {
    Object? firstError;
    StackTrace? firstStackTrace;
    for (final key in const [
      _apiAuthorizationKey,
      _subscriptionTokenKey,
      _isAdminKey,
    ]) {
      try {
        await _storage.delete(key: key);
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }
}

final class SharedPreferencesAi68TokenStore implements Ai68TokenStore {
  static const _apiAuthorizationKey = 'ai68.test.api.authorization';
  static const _subscriptionTokenKey = 'ai68.test.subscription.token';
  static const _isAdminKey = 'ai68.test.session.is_admin';

  Future<SharedPreferences> get _preferences {
    return SharedPreferences.getInstance();
  }

  @override
  Future<String?> readApiAuthorization() async {
    return (await _preferences).getString(_apiAuthorizationKey);
  }

  @override
  Future<String?> readSubscriptionToken() async {
    return (await _preferences).getString(_subscriptionTokenKey);
  }

  @override
  Future<Ai68Session?> readSession() async {
    final preferences = await _preferences;
    final apiAuthorization = preferences.getString(_apiAuthorizationKey);
    final subscriptionToken = preferences.getString(_subscriptionTokenKey);
    if (apiAuthorization == null || subscriptionToken == null) {
      if (apiAuthorization != null || subscriptionToken != null) {
        await clear();
      }
      return null;
    }
    return Ai68Session(
      apiAuthorization: apiAuthorization,
      subscriptionToken: subscriptionToken,
      isAdmin: preferences.getBool(_isAdminKey) ?? false,
    );
  }

  @override
  Future<void> writeSession(Ai68Session session) async {
    final preferences = await _preferences;
    try {
      await preferences.setString(
        _apiAuthorizationKey,
        session.apiAuthorization,
      );
      await preferences.setString(
        _subscriptionTokenKey,
        session.subscriptionToken,
      );
      await preferences.setBool(_isAdminKey, session.isAdmin);
    } catch (_) {
      await clear();
      rethrow;
    }
  }

  @override
  Future<void> clear() async {
    final preferences = await _preferences;
    await Future.wait([
      preferences.remove(_apiAuthorizationKey),
      preferences.remove(_subscriptionTokenKey),
      preferences.remove(_isAdminKey),
    ]);
  }
}
