import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_clash/features/ai68/api/ai68_api_exception.dart';
import 'package:fl_clash/features/ai68/api/ai68_api_models.dart';
import 'package:fl_clash/features/ai68/subscription/ai68_managed_profile.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DioAi68SubscriptionDownloader', () {
    test('rejects non-HTTPS and unrelated hosts before transport', () async {
      final adapter = _QueueBytesAdapter();
      final downloader = DioAi68SubscriptionDownloader(
        dio: Dio()..httpClientAdapter = adapter,
      );
      addTearDown(() => downloader.close(force: true));

      await expectLater(
        downloader.download(
          uri: Uri.parse('http://mingjie-panel.ai68ai.cn/sub'),
          userAgent: 'FlClash Plus',
        ),
        throwsA(isA<Ai68ApiException>()),
      );
      await expectLater(
        downloader.download(
          uri: Uri.parse('https://example.com/sub'),
          userAgent: 'FlClash Plus',
        ),
        throwsA(isA<Ai68ApiException>()),
      );

      expect(adapter.requests, isEmpty);
    });

    test('downloads bytes from the panel and trusted subdomains', () async {
      final adapter = _QueueBytesAdapter()
        ..enqueue(
          Uint8List.fromList([1, 2, 3]),
          headers: const {
            Headers.contentLengthHeader: ['3'],
          },
        )
        ..enqueue(Uint8List.fromList([4, 5]));
      final downloader = DioAi68SubscriptionDownloader(
        dio: Dio()..httpClientAdapter = adapter,
      );
      addTearDown(() => downloader.close(force: true));

      final panelResult = await downloader.download(
        uri: Uri.parse('https://mingjie-panel.ai68ai.cn/sub/one'),
        userAgent: 'FlClash Plus/1',
      );
      final subdomainResult = await downloader.download(
        uri: Uri.parse('https://edge.ai68ai.cn/sub/two'),
        userAgent: 'FlClash Plus/2',
      );

      expect(panelResult.bytes, Uint8List.fromList([1, 2, 3]));
      expect(subdomainResult.bytes, Uint8List.fromList([4, 5]));
      expect(adapter.requests[0].headers['User-Agent'], 'FlClash Plus/1');
      expect(adapter.requests[1].headers['User-Agent'], 'FlClash Plus/2');
    });

    test('rejects a declared subscription length over the limit', () async {
      final adapter = _QueueBytesAdapter()
        ..enqueue(
          Uint8List.fromList([1]),
          headers: const {
            Headers.contentLengthHeader: ['5'],
          },
        );
      final downloader = DioAi68SubscriptionDownloader(
        dio: Dio()..httpClientAdapter = adapter,
        maximumBytes: 4,
      );
      addTearDown(() => downloader.close(force: true));

      await expectLater(
        downloader.download(
          uri: Uri.parse('https://mingjie-panel.ai68ai.cn/sub'),
          userAgent: 'FlClash Plus',
        ),
        throwsA(
          isA<Ai68ApiException>().having(
            (error) => error.message,
            'message',
            'AI68 订阅超过大小限制',
          ),
        ),
      );
    });

    test('rejects actual bytes over a forged content length', () async {
      final adapter = _QueueBytesAdapter()
        ..enqueue(
          Uint8List.fromList([1, 2, 3, 4, 5]),
          headers: const {
            Headers.contentLengthHeader: ['1'],
          },
        );
      final downloader = DioAi68SubscriptionDownloader(
        dio: Dio()..httpClientAdapter = adapter,
        maximumBytes: 4,
      );
      addTearDown(() => downloader.close(force: true));

      await expectLater(
        downloader.download(
          uri: Uri.parse('https://mingjie-panel.ai68ai.cn/sub'),
          userAgent: 'FlClash Plus',
        ),
        throwsA(
          isA<Ai68ApiException>().having(
            (error) => error.message,
            'message',
            'AI68 订阅超过大小限制',
          ),
        ),
      );
    });

    test('validates every subscription redirect before following it', () async {
      final rejectedAdapter = _QueueBytesAdapter()
        ..enqueue(
          Uint8List(0),
          statusCode: 302,
          headers: const {
            'location': ['https://example.com/sub'],
          },
        );
      final rejectedDownloader = DioAi68SubscriptionDownloader(
        dio: Dio()..httpClientAdapter = rejectedAdapter,
      );
      addTearDown(() => rejectedDownloader.close(force: true));

      await expectLater(
        rejectedDownloader.download(
          uri: Uri.parse('https://mingjie-panel.ai68ai.cn/sub'),
          userAgent: 'FlClash Plus',
        ),
        throwsA(isA<Ai68ApiException>()),
      );
      expect(rejectedAdapter.requests, hasLength(1));

      final allowedAdapter = _QueueBytesAdapter()
        ..enqueue(
          Uint8List(0),
          statusCode: 302,
          headers: const {
            'location': ['https://edge.ai68ai.cn/sub'],
          },
        )
        ..enqueue(Uint8List.fromList([7, 8, 9]));
      final allowedDownloader = DioAi68SubscriptionDownloader(
        dio: Dio()..httpClientAdapter = allowedAdapter,
      );
      addTearDown(() => allowedDownloader.close(force: true));

      final result = await allowedDownloader.download(
        uri: Uri.parse('https://mingjie-panel.ai68ai.cn/sub'),
        userAgent: 'FlClash Plus',
      );

      expect(result.bytes, Uint8List.fromList([7, 8, 9]));
      expect(allowedAdapter.requests, hasLength(2));
    });

    test('rejects an empty subscription response', () async {
      final adapter = _QueueBytesAdapter()..enqueue(Uint8List(0));
      final downloader = DioAi68SubscriptionDownloader(
        dio: Dio()..httpClientAdapter = adapter,
      );
      addTearDown(() => downloader.close(force: true));

      await expectLater(
        downloader.download(
          uri: Uri.parse('https://mingjie-panel.ai68ai.cn/sub'),
          userAgent: 'FlClash Plus',
        ),
        throwsA(
          isA<Ai68ApiException>().having(
            (error) => error.message,
            'message',
            'AI68 订阅内容为空',
          ),
        ),
      );
    });

    test('maps transport failures without exposing response data', () async {
      final adapter = _QueueBytesAdapter()
        ..enqueue(Uint8List.fromList([9]), statusCode: 503);
      final downloader = DioAi68SubscriptionDownloader(
        dio: Dio()..httpClientAdapter = adapter,
      );
      addTearDown(() => downloader.close(force: true));

      await expectLater(
        downloader.download(
          uri: Uri.parse('https://mingjie-panel.ai68ai.cn/sub'),
          userAgent: 'FlClash Plus',
        ),
        throwsA(
          isA<Ai68ApiException>()
              .having((error) => error.message, 'message', '无法下载 AI68 订阅')
              .having((error) => error.statusCode, 'statusCode', 503),
        ),
      );
    });
  });

  group('DefaultAi68ProfileSynchronizer', () {
    test('clear removes the managed profile reference', () async {
      final store = _MemoryManagedProfileStore(initialProfileId: 42);
      final synchronizer = DefaultAi68ProfileSynchronizer(
        downloader: _ThrowingSubscriptionDownloader(StateError('unused')),
        profileStore: store,
      );

      await synchronizer.clear();

      expect(store.profileId, isNull);
      expect(store.clearCount, 1);
    });

    test('does not persist a profile id when download fails', () async {
      final store = _MemoryManagedProfileStore(initialProfileId: 42);
      final failure = StateError('download failed');
      final downloader = _ThrowingSubscriptionDownloader(failure);
      final synchronizer = DefaultAi68ProfileSynchronizer(
        downloader: downloader,
        profileStore: store,
      );
      const profile = Profile(
        id: 42,
        label: 'Existing AI68',
        autoUpdateDuration: Duration(hours: 24),
      );
      final subscription = _subscription();

      await expectLater(
        synchronizer.synchronize(
          subscription: subscription,
          profiles: const [profile],
          userAgent: 'FlClash Plus',
        ),
        throwsA(same(failure)),
      );

      expect(store.readCount, 1);
      expect(store.writtenProfileIds, isEmpty);
      expect(store.profileId, 42);
      expect(downloader.requestedUri, subscription.subscribeUrl);
      expect(downloader.requestedUserAgent, 'FlClash Plus');
    });
  });
}

Ai68Subscription _subscription() {
  return Ai68Subscription(
    subscriptionToken: 'subscription-token',
    subscribeUrl: Uri.parse('https://mingjie-panel.ai68ai.cn/sub'),
    uploadBytes: 10,
    downloadBytes: 20,
    transferEnableBytes: 100,
    expiredAt: 1800000000,
  );
}

final class _QueueBytesAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  final List<_QueuedBytesResponse> _responses = [];

  void enqueue(
    Uint8List bytes, {
    int statusCode = 200,
    Map<String, List<String>> headers = const {},
  }) {
    _responses.add(
      _QueuedBytesResponse(
        bytes: bytes,
        statusCode: statusCode,
        headers: headers,
      ),
    );
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (_responses.isEmpty) {
      throw StateError('No response queued for ${options.uri}');
    }
    final response = _responses.removeAt(0);
    return ResponseBody.fromBytes(
      response.bytes,
      response.statusCode,
      headers: response.headers,
    );
  }

  @override
  void close({bool force = false}) {}
}

final class _QueuedBytesResponse {
  const _QueuedBytesResponse({
    required this.bytes,
    required this.statusCode,
    required this.headers,
  });

  final Uint8List bytes;
  final int statusCode;
  final Map<String, List<String>> headers;
}

final class _MemoryManagedProfileStore implements Ai68ManagedProfileStore {
  _MemoryManagedProfileStore({int? initialProfileId})
    : profileId = initialProfileId;

  int? profileId;
  int clearCount = 0;
  int readCount = 0;
  final List<int> writtenProfileIds = [];

  @override
  Future<void> clear() async {
    clearCount += 1;
    profileId = null;
  }

  @override
  Future<int?> readProfileId() async {
    readCount += 1;
    return profileId;
  }

  @override
  Future<void> writeProfileId(int profileId) async {
    writtenProfileIds.add(profileId);
    this.profileId = profileId;
  }
}

final class _ThrowingSubscriptionDownloader
    implements Ai68SubscriptionDownloader {
  _ThrowingSubscriptionDownloader(this.failure);

  final Object failure;
  Uri? requestedUri;
  String? requestedUserAgent;

  @override
  Future<Ai68DownloadedSubscription> download({
    required Uri uri,
    required String userAgent,
  }) async {
    requestedUri = uri;
    requestedUserAgent = userAgent;
    throw failure;
  }

  @override
  void close({bool force = false}) {}
}
