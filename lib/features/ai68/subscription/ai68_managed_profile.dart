import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_clash/features/ai68/api/ai68_api_exception.dart';
import 'package:fl_clash/features/ai68/api/ai68_api_models.dart';
import 'package:fl_clash/features/ai68/api/ai68_http_client_adapter.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const ai68MaximumSubscriptionBytes = 16 * 1024 * 1024;

final ai68ManagedProfileStoreProvider = Provider<Ai68ManagedProfileStore>((
  ref,
) {
  return FlutterSecureAi68ManagedProfileStore();
});

final ai68SubscriptionDownloaderProvider = Provider<Ai68SubscriptionDownloader>(
  (ref) {
    final downloader = DioAi68SubscriptionDownloader();
    ref.onDispose(downloader.close);
    return downloader;
  },
);

final ai68ProfileSynchronizerProvider = Provider<Ai68ProfileSynchronizer>((
  ref,
) {
  return DefaultAi68ProfileSynchronizer(
    downloader: ref.watch(ai68SubscriptionDownloaderProvider),
    profileStore: ref.watch(ai68ManagedProfileStoreProvider),
  );
});

abstract interface class Ai68ManagedProfileStore {
  Future<int?> readProfileId();

  Future<void> writeProfileId(int profileId);

  Future<void> clear();
}

final class FlutterSecureAi68ManagedProfileStore
    implements Ai68ManagedProfileStore {
  FlutterSecureAi68ManagedProfileStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _profileIdKey = 'ai68.managed_profile.id';

  final FlutterSecureStorage _storage;

  @override
  Future<void> clear() {
    return _storage.delete(key: _profileIdKey);
  }

  @override
  Future<int?> readProfileId() async {
    final value = await _storage.read(key: _profileIdKey);
    return value == null ? null : int.tryParse(value);
  }

  @override
  Future<void> writeProfileId(int profileId) {
    return _storage.write(key: _profileIdKey, value: profileId.toString());
  }
}

final class Ai68DownloadedSubscription {
  const Ai68DownloadedSubscription({required this.bytes});

  final Uint8List bytes;
}

abstract interface class Ai68SubscriptionDownloader {
  Future<Ai68DownloadedSubscription> download({
    required Uri uri,
    required String userAgent,
  });

  void close({bool force = false});
}

final class DioAi68SubscriptionDownloader
    implements Ai68SubscriptionDownloader {
  DioAi68SubscriptionDownloader({
    Dio? dio,
    int maximumBytes = ai68MaximumSubscriptionBytes,
  }) : _dio = dio ?? _createDio(),
       _maximumBytes = maximumBytes {
    if (maximumBytes <= 0) {
      throw ArgumentError.value(maximumBytes, 'maximumBytes');
    }
  }

  final Dio _dio;
  final int _maximumBytes;

  static Dio _createDio() {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 45),
      ),
    );
    dio.httpClientAdapter = createAi68HttpClientAdapter();
    return dio;
  }

  @override
  Future<Ai68DownloadedSubscription> download({
    required Uri uri,
    required String userAgent,
  }) async {
    try {
      var currentUri = uri;
      for (var redirect = 0; redirect <= 5; redirect++) {
        _validateUri(currentUri);
        final response = await _dio.get<ResponseBody>(
          currentUri.toString(),
          options: Options(
            responseType: ResponseType.stream,
            followRedirects: false,
            validateStatus: (status) {
              return status != null && status >= 200 && status < 400;
            },
            headers: <String, dynamic>{'User-Agent': userAgent},
          ),
        );
        final statusCode = response.statusCode ?? 0;
        if (statusCode >= 300) {
          await _cancelBody(response.data);
          final location = response.headers.value('location');
          if (location == null || redirect == 5) {
            throw const Ai68ApiException(
              message: 'AI68 subscription redirect is invalid',
            );
          }
          currentUri = currentUri.resolve(location);
          continue;
        }
        final body = response.data;
        try {
          _validateUri(response.realUri);
          _validateContentLength(response.headers);
        } on Ai68ApiException {
          await _cancelBody(body);
          rethrow;
        }
        if (body == null) {
          throw const Ai68ApiException(message: 'AI68 subscription is empty');
        }
        final bytes = await _readBytes(body.stream);
        if (bytes.isEmpty) {
          throw const Ai68ApiException(message: 'AI68 subscription is empty');
        }
        return Ai68DownloadedSubscription(bytes: bytes);
      }
      throw const Ai68ApiException(
        message: 'AI68 subscription redirect is invalid',
      );
    } on Ai68ApiException {
      rethrow;
    } on DioException catch (error) {
      throw Ai68ApiException(
        message: 'Unable to download AI68 subscription',
        statusCode: error.response?.statusCode,
        cause: error,
      );
    } catch (error) {
      throw Ai68ApiException(
        message: 'Unable to download AI68 subscription',
        cause: error,
      );
    }
  }

  Future<Uint8List> _readBytes(Stream<Uint8List> stream) async {
    final builder = BytesBuilder(copy: false);
    var length = 0;
    await for (final chunk in stream) {
      length += chunk.length;
      if (length > _maximumBytes) {
        throw const Ai68ApiException(
          message: 'AI68 subscription exceeds the size limit',
        );
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  void _validateContentLength(Headers headers) {
    final rawValues = headers[Headers.contentLengthHeader];
    if (rawValues == null) return;
    final values = rawValues
        .expand((value) => value.split(','))
        .map((value) => int.tryParse(value.trim()))
        .toList();
    if (values.isEmpty ||
        values.any((value) => value == null || value < 0) ||
        values.toSet().length != 1) {
      throw const Ai68ApiException(
        message: 'AI68 subscription has an invalid content length',
      );
    }
    if (values.first! > _maximumBytes) {
      throw const Ai68ApiException(
        message: 'AI68 subscription exceeds the size limit',
      );
    }
  }

  Future<void> _cancelBody(ResponseBody? body) async {
    if (body == null) return;
    final subscription = body.stream.listen((_) {});
    await subscription.cancel();
  }

  static void _validateUri(Uri uri) {
    if (uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443 ||
        !_isAllowedHost(uri.host)) {
      throw const Ai68ApiException(
        message: 'AI68 returned an untrusted subscription address',
      );
    }
  }

  static bool _isAllowedHost(String host) {
    return host == 'mingjie-panel.ai68ai.cn' || host.endsWith('.ai68ai.cn');
  }

  @override
  void close({bool force = false}) {
    _dio.close(force: force);
  }
}

abstract interface class Ai68ProfileSynchronizer {
  Future<Profile> synchronize({
    required Ai68Subscription subscription,
    required List<Profile> profiles,
    required String userAgent,
  });

  Future<void> clear();
}

final class DefaultAi68ProfileSynchronizer implements Ai68ProfileSynchronizer {
  const DefaultAi68ProfileSynchronizer({
    required Ai68SubscriptionDownloader downloader,
    required Ai68ManagedProfileStore profileStore,
  }) : _downloader = downloader,
       _profileStore = profileStore;

  final Ai68SubscriptionDownloader _downloader;
  final Ai68ManagedProfileStore _profileStore;

  @override
  Future<void> clear() {
    return _profileStore.clear();
  }

  @override
  Future<Profile> synchronize({
    required Ai68Subscription subscription,
    required List<Profile> profiles,
    required String userAgent,
  }) async {
    final profileId = await _profileStore.readProfileId();
    final existing = profiles.getProfile(profileId);
    final profile = existing ?? Profile.normal(label: 'AI68');
    final downloaded = await _downloader.download(
      uri: subscription.subscribeUrl,
      userAgent: userAgent,
    );
    final updated = await profile
        .copyWith(
          label: 'AI68',
          url: '',
          autoUpdate: false,
          subscriptionInfo: SubscriptionInfo(
            upload: subscription.uploadBytes,
            download: subscription.downloadBytes,
            total: subscription.transferEnableBytes,
            expire: subscription.expiredAt ?? 0,
          ),
        )
        .saveFile(downloaded.bytes);
    await _profileStore.writeProfileId(updated.id);
    return updated;
  }
}
