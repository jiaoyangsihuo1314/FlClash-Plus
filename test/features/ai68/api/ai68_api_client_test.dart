import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_clash/features/ai68/api/ai68_api_client.dart';
import 'package:fl_clash/features/ai68/api/ai68_api_exception.dart';
import 'package:fl_clash/features/ai68/api/ai68_api_models.dart';
import 'package:fl_clash/features/ai68/auth/ai68_session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late MemoryAi68TokenStore tokenStore;
  late QueueHttpClientAdapter adapter;
  late Ai68ApiClient api;

  setUp(() {
    tokenStore = MemoryAi68TokenStore();
    adapter = QueueHttpClientAdapter();
    final dio = Dio(
      BaseOptions(baseUrl: ai68ApiBaseUrl, responseType: ResponseType.json),
    )..httpClientAdapter = adapter;
    api = Ai68ApiClient(tokenStore: tokenStore, dio: dio);
  });

  tearDown(() {
    api.close(force: true);
  });

  test('login parses API and subscription credentials separately', () async {
    adapter.enqueue(<String, dynamic>{
      'status': 'success',
      'message': 'ok',
      'data': <String, dynamic>{
        'auth_data': 'Bearer api-secret',
        'token': 'subscription-secret',
        'is_admin': 0,
      },
      'error': null,
    });

    final session = await api.login(
      email: 'user@example.com',
      password: 'password123',
    );

    expect(session.apiAuthorization, 'Bearer api-secret');
    expect(session.subscriptionToken, 'subscription-secret');
    expect(adapter.requests.single.path, 'passport/auth/login');
    expect(adapter.requests.single.headers[ai68AuthorizationHeader], isNull);
    expect(adapter.requests.single.data, <String, dynamic>{
      'email': 'user@example.com',
      'password': 'password123',
    });
  });

  test('guest config drives optional registration fields', () async {
    adapter
      ..enqueue(<String, dynamic>{
        'status': 'success',
        'message': 'ok',
        'data': <String, dynamic>{
          'is_email_verify': 1,
          'is_invite_force': 1,
          'is_captcha': 1,
          'captcha_type': 'turnstile',
          'turnstile_site_key': 'site-key',
          'email_whitelist_suffix': <String>['example.com'],
        },
        'error': null,
      })
      ..enqueue(<String, dynamic>{
        'status': 'success',
        'message': 'ok',
        'data': <String, dynamic>{
          'auth_data': 'Bearer api-secret',
          'token': 'subscription-secret',
          'is_admin': false,
        },
        'error': null,
      });

    final config = await api.fetchGuestConfig();
    await api.register(
      const Ai68RegisterRequest(
        email: 'user@example.com',
        password: 'password123',
        inviteCode: 'INVITE',
        emailCode: '123456',
        turnstileToken: 'captcha-token',
      ),
    );

    expect(config.isEmailVerify, isTrue);
    expect(config.isInviteForce, isTrue);
    expect(config.captchaType, 'turnstile');
    expect(config.emailWhitelistSuffixes, <String>['example.com']);
    expect(adapter.requests.last.data, <String, dynamic>{
      'email': 'user@example.com',
      'password': 'password123',
      'invite_code': 'INVITE',
      'email_code': '123456',
      'turnstile_token': 'captcha-token',
    });
  });

  test('guest config accepts comma-separated email suffixes', () async {
    adapter.enqueue(<String, dynamic>{
      'status': 'success',
      'message': 'ok',
      'data': <String, dynamic>{
        'is_email_verify': 1,
        'is_invite_force': 0,
        'is_captcha': 0,
        'email_whitelist_suffix': 'example.com, ai68ai.cn',
      },
      'error': null,
    });

    final config = await api.fetchGuestConfig();

    expect(config.emailWhitelistSuffixes, <String>['example.com', 'ai68ai.cn']);
  });

  test(
    'protected requests use auth_data and never subscription token',
    () async {
      tokenStore.session = const Ai68Session(
        apiAuthorization: 'Bearer api-secret',
        subscriptionToken: 'subscription-secret',
        isAdmin: false,
      );
      adapter.enqueue(<String, dynamic>{
        'status': 'success',
        'message': 'ok',
        'data': <String, dynamic>{
          'email': 'user@example.com',
          'transfer_enable': 10737418240,
          'banned': 0,
          'remind_expire': 1,
          'remind_traffic': 1,
          'balance': 500,
          'commission_balance': 0,
        },
        'error': null,
      });

      final user = await api.fetchUserInfo();

      final authorization =
          adapter.requests.single.headers[ai68AuthorizationHeader];
      expect(authorization, 'Bearer api-secret');
      expect(authorization, isNot(contains('subscription-secret')));
      expect(user.email, 'user@example.com');
      expect(user.transferEnableBytes, 10737418240);
    },
  );

  test('protected requests fail before transport when session is absent', () {
    expect(
      api.fetchUserInfo,
      throwsA(
        isA<Ai68ApiException>()
            .having((error) => error.statusCode, 'statusCode', 401)
            .having(
              (error) => error.isAuthenticationFailure,
              'isAuthenticationFailure',
              isTrue,
            ),
      ),
    );
    expect(adapter.requests, isEmpty);
  });

  test('maps backend authentication errors without exposing request data', () {
    tokenStore.session = const Ai68Session(
      apiAuthorization: 'Bearer expired-secret',
      subscriptionToken: 'subscription-secret',
      isAdmin: false,
    );
    adapter.enqueue(<String, dynamic>{
      'status': 'fail',
      'message': 'Login expired',
      'data': null,
      'error': null,
    }, statusCode: 403);

    expect(
      api.fetchUserInfo,
      throwsA(
        isA<Ai68ApiException>()
            .having((error) => error.statusCode, 'statusCode', 403)
            .having((error) => error.message, 'message', 'Login expired')
            .having((error) => error.cause, 'cause', isNull)
            .having(
              (error) => error.toString(),
              'toString',
              isNot(contains('expired-secret')),
            ),
      ),
    );
  });

  test('parses checkout, notice, and server response variants', () async {
    tokenStore.session = const Ai68Session(
      apiAuthorization: 'api-secret',
      subscriptionToken: 'subscription-secret',
      isAdmin: false,
    );
    adapter
      ..enqueue(<String, dynamic>{
        'type': 1,
        'data': 'https://payments.example/checkout',
      })
      ..enqueue(<String, dynamic>{
        'data': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 7,
            'title': 'Maintenance',
            'content': 'Scheduled',
            'show': true,
            'tags': <String>['service'],
            'created_at': 100,
            'updated_at': 101,
          },
        ],
        'total': 1,
      })
      ..enqueue(<String, dynamic>{
        'data': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 3,
            'type': 'shadowsocks',
            'name': 'Hong Kong 01',
            'rate': 1.5,
            'tags': <String>['HK'],
            'is_online': 1,
            'cache_key': 'server-3',
          },
        ],
      });

    final checkout = await api.checkoutOrder(
      tradeNo: 'T2026082201',
      paymentMethodId: 2,
    );
    final notices = await api.fetchNotices();
    final servers = await api.fetchServers();

    expect(
      checkout.redirectUrl,
      Uri.parse('https://payments.example/checkout'),
    );
    expect(notices.total, 1);
    expect(notices.items.single.title, 'Maintenance');
    expect(servers.single.name, 'Hong Kong 01');
    expect(servers.single.isOnline, isTrue);
    expect(
      adapter.requests.every(
        (request) =>
            request.headers[ai68AuthorizationHeader] == 'Bearer api-secret',
      ),
      isTrue,
    );
  });

  test('creates orders with XBoard legacy period keys', () async {
    tokenStore.session = const Ai68Session(
      apiAuthorization: 'Bearer api-secret',
      subscriptionToken: 'subscription-secret',
      isAdmin: false,
    );
    adapter.enqueue(<String, dynamic>{
      'status': 'success',
      'message': 'ok',
      'data': 'T2026082202',
      'error': null,
    });

    final tradeNo = await api.createOrder(
      planId: 8,
      period: Ai68PlanPeriod.year,
      couponCode: 'PLUS',
    );

    expect(tradeNo, 'T2026082202');
    expect(adapter.requests.single.data, <String, dynamic>{
      'plan_id': 8,
      'period': 'year_price',
      'coupon_code': 'PLUS',
    });
  });

  test('omits payment method when checking out a free order', () async {
    tokenStore.session = const Ai68Session(
      apiAuthorization: 'Bearer api-secret',
      subscriptionToken: 'subscription-secret',
      isAdmin: false,
    );
    adapter.enqueue(<String, dynamic>{'type': 0, 'data': true});

    final checkout = await api.checkoutOrder(
      tradeNo: 'T2026082203',
      paymentMethodId: null,
    );

    expect(checkout.type, 0);
    expect(adapter.requests.single.data, <String, dynamic>{
      'trade_no': 'T2026082203',
    });
  });

  test('parses subscription, plan prices, and traffic units', () async {
    tokenStore.session = const Ai68Session(
      apiAuthorization: 'Bearer api-secret',
      subscriptionToken: 'subscription-secret',
      isAdmin: false,
    );
    adapter
      ..enqueue(<String, dynamic>{
        'status': 'success',
        'message': 'ok',
        'data': <String, dynamic>{
          'token': 'subscription-secret',
          'subscribe_url': 'https://example.com/s/subscription-secret',
          'u': 100,
          'd': 250,
          'transfer_enable': 10737418240,
        },
        'error': null,
      })
      ..enqueue(<String, dynamic>{
        'status': 'success',
        'message': 'ok',
        'data': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 1,
            'name': 'Monthly',
            'tags': <String>['AI68'],
            'month_price': 1000,
            'transfer_enable': 10,
            'show': true,
            'sell': true,
            'renew': true,
          },
        ],
        'error': null,
      })
      ..enqueue(<String, dynamic>{
        'status': 'success',
        'message': 'ok',
        'data': <Map<String, dynamic>>[
          <String, dynamic>{
            'd': 20,
            'u': 10,
            'record_at': 1787328000,
            'server_rate': 1.5,
          },
        ],
        'error': null,
      });

    final subscription = await api.fetchSubscription();
    final plans = await api.fetchPlans();
    final traffic = await api.fetchTrafficLogs();

    expect(subscription.usedBytes, 350);
    expect(subscription.remainingBytes, 10737417890);
    expect(subscription.transferEnableBytes, 10737418240);
    expect(plans.single.pricesCents[Ai68PlanPeriod.month], 1000);
    expect(plans.single.transferEnableGb, 10);
    expect(traffic.single.downloadBytes, 20);
    expect(traffic.single.serverRate, 1.5);
  });

  test('subscription remaining traffic never becomes negative', () {
    final subscription = Ai68Subscription(
      subscriptionToken: 'subscription-secret',
      subscribeUrl: Uri.parse('https://example.com/s/subscription-secret'),
      uploadBytes: 800,
      downloadBytes: 700,
      transferEnableBytes: 1000,
    );

    expect(subscription.usedBytes, 1500);
    expect(subscription.remainingBytes, 0);
  });

  test('supports XBoard invitation and commission endpoints', () async {
    tokenStore.session = const Ai68Session(
      apiAuthorization: 'Bearer api-secret',
      subscriptionToken: 'subscription-secret',
      isAdmin: false,
    );
    adapter
      ..enqueue(<String, dynamic>{
        'status': 'success',
        'message': 'ok',
        'data': <String, dynamic>{
          'withdraw_methods': <String>['Alipay'],
          'withdraw_close': 0,
          'currency': 'CNY',
          'currency_symbol': '¥',
          'commission_distribution_enable': 1,
          'commission_distribution_l1': 50,
          'commission_distribution_l2': 30,
          'commission_distribution_l3': 20,
        },
        'error': null,
      })
      ..enqueue(<String, dynamic>{
        'status': 'success',
        'message': 'ok',
        'data': <String, dynamic>{
          'codes': <Map<String, dynamic>>[
            <String, dynamic>{
              'code': 'INVITE68',
              'pv': 3,
              'status': 0,
              'created_at': 1787961600,
            },
          ],
          'stat': <int>[4, 1200, 300, 10, 900],
        },
        'error': null,
      })
      ..enqueue(<String, dynamic>{
        'data': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 7,
            'order_amount': 5000,
            'trade_no': 'T2026082901',
            'get_amount': 500,
            'created_at': 1787961600,
          },
        ],
        'total': 1,
      })
      ..enqueue(<String, dynamic>{
        'status': 'success',
        'message': 'ok',
        'data': true,
        'error': null,
      })
      ..enqueue(<String, dynamic>{
        'status': 'success',
        'message': 'ok',
        'data': true,
        'error': null,
      })
      ..enqueue(<String, dynamic>{
        'status': 'success',
        'message': 'ok',
        'data': true,
        'error': null,
      });

    final config = await api.fetchUserConfig();
    final overview = await api.fetchInviteOverview();
    final details = await api.fetchCommissionLogs(page: 2, pageSize: 20);
    await api.generateInviteCode();
    await api.transferCommission(250);
    await api.withdrawCommission(method: 'Alipay', account: 'user@example.com');

    expect(config.withdrawMethods, <String>['Alipay']);
    expect(config.commissionDistributionRates, <int>[50, 30, 20]);
    expect(overview.codes.single.code, 'INVITE68');
    expect(overview.stats.registeredUsers, 4);
    expect(overview.stats.availableCommissionCents, 900);
    expect(details.items.single.amountCents, 500);
    expect(details.total, 1);
    expect(adapter.requests[2].queryParameters, <String, dynamic>{
      'current': 2,
      'page_size': 20,
    });
    expect(adapter.requests[4].data, <String, dynamic>{'transfer_amount': 250});
    expect(adapter.requests[5].data, <String, dynamic>{
      'withdraw_method': 'Alipay',
      'withdraw_account': 'user@example.com',
    });
  });
}

final class QueueHttpClientAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  final List<_QueuedResponse> _responses = [];

  void enqueue(Object? data, {int statusCode = 200}) {
    _responses.add(_QueuedResponse(data: data, statusCode: statusCode));
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
    return ResponseBody.fromString(
      jsonEncode(response.data),
      response.statusCode,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

final class _QueuedResponse {
  const _QueuedResponse({required this.data, required this.statusCode});

  final Object? data;
  final int statusCode;
}
