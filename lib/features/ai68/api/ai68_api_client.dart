import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fl_clash/features/ai68/api/ai68_api_exception.dart';
import 'package:fl_clash/features/ai68/api/ai68_api_models.dart';
import 'package:fl_clash/features/ai68/api/ai68_http_client_adapter.dart';
import 'package:fl_clash/features/ai68/auth/ai68_session.dart';
import 'package:fl_clash/features/ai68/auth/ai68_token_store.dart';

const ai68ApiBaseUrl = 'https://mingjie-panel.ai68ai.cn/api/v1/';
const ai68AuthorizationHeader = 'Authorization';

abstract interface class Ai68Api {
  Future<Ai68GuestConfig> fetchGuestConfig();

  Future<Ai68Session> login({required String email, required String password});

  Future<Ai68Session> register(Ai68RegisterRequest request);

  Future<void> sendEmailVerification({
    required String email,
    Ai68CaptchaTokens captchaTokens = const Ai68CaptchaTokens(),
  });

  Future<Ai68User> fetchUserInfo();

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  });

  Future<Ai68UserConfig> fetchUserConfig();

  Future<Ai68Subscription> fetchSubscription();

  Future<List<Ai68Plan>> fetchPlans({bool authenticated = true});

  Future<String> createOrder({
    required int planId,
    required Ai68PlanPeriod period,
    String? couponCode,
  });

  Future<Ai68CheckoutResult> checkoutOrder({
    required String tradeNo,
    required int? paymentMethodId,
    String? paymentToken,
  });

  Future<Ai68OrderStatus> checkOrder(String tradeNo);

  Future<Ai68Order> fetchOrderDetail(String tradeNo);

  Future<List<Ai68Order>> fetchOrders({Ai68OrderStatus? status});

  Future<List<Ai68PaymentMethod>> fetchPaymentMethods();

  Future<void> cancelOrder(String tradeNo);

  Future<Ai68NoticePage> fetchNotices({int page = 1});

  Future<List<Ai68Server>> fetchServers();

  Future<List<Ai68TrafficLog>> fetchTrafficLogs();

  Future<Ai68InviteOverview> fetchInviteOverview();

  Future<void> generateInviteCode();

  Future<Ai68CommissionPage> fetchCommissionLogs({
    int page = 1,
    int pageSize = 20,
  });

  Future<void> transferCommission(int amountCents);

  Future<void> withdrawCommission({
    required String method,
    required String account,
  });

  void close({bool force = false});
}

final class Ai68ApiClient implements Ai68Api {
  Ai68ApiClient({required Ai68TokenStore tokenStore, Dio? dio})
    : _dio = dio ?? _createDio() {
    _dio.interceptors.add(_Ai68AuthorizationInterceptor(tokenStore));
  }

  static const _requiresAuthentication = 'ai68.requiresAuthentication';

  final Dio _dio;

  static Dio _createDio() {
    final dio = Dio(
      BaseOptions(
        baseUrl: ai68ApiBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        responseType: ResponseType.json,
        headers: const <String, dynamic>{
          Headers.acceptHeader: Headers.jsonContentType,
        },
      ),
    );
    dio.httpClientAdapter = createAi68HttpClientAdapter();
    return dio;
  }

  @override
  Future<Ai68GuestConfig> fetchGuestConfig() async {
    final data = await _standardRequest('GET', 'guest/comm/config');
    return Ai68GuestConfig.fromJson(
      Ai68Json.object(data, 'guest configuration'),
    );
  }

  @override
  Future<Ai68Session> login({
    required String email,
    required String password,
  }) async {
    final data = await _standardRequest(
      'POST',
      'passport/auth/login',
      data: <String, dynamic>{'email': email, 'password': password},
    );
    return Ai68Session.fromJson(Ai68Json.object(data, 'login session'));
  }

  @override
  Future<Ai68Session> register(Ai68RegisterRequest request) async {
    final data = await _standardRequest(
      'POST',
      'passport/auth/register',
      data: request.toJson(),
    );
    return Ai68Session.fromJson(Ai68Json.object(data, 'register session'));
  }

  @override
  Future<void> sendEmailVerification({
    required String email,
    Ai68CaptchaTokens captchaTokens = const Ai68CaptchaTokens(),
  }) async {
    await _standardRequest(
      'POST',
      'passport/comm/sendEmailVerify',
      data: <String, dynamic>{'email': email, ...captchaTokens.toJson()},
    );
  }

  @override
  Future<Ai68User> fetchUserInfo() async {
    final data = await _standardRequest(
      'GET',
      'user/info',
      authenticated: true,
    );
    return Ai68User.fromJson(Ai68Json.object(data, 'user'));
  }

  @override
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    await _standardRequest(
      'POST',
      'user/changePassword',
      authenticated: true,
      data: <String, dynamic>{
        'old_password': oldPassword,
        'new_password': newPassword,
      },
    );
  }

  @override
  Future<Ai68UserConfig> fetchUserConfig() async {
    final data = await _standardRequest(
      'GET',
      'user/comm/config',
      authenticated: true,
    );
    return Ai68UserConfig.fromJson(Ai68Json.object(data, 'user configuration'));
  }

  @override
  Future<Ai68Subscription> fetchSubscription() async {
    final data = await _standardRequest(
      'GET',
      'user/getSubscribe',
      authenticated: true,
    );
    return Ai68Subscription.fromJson(Ai68Json.object(data, 'subscription'));
  }

  @override
  Future<List<Ai68Plan>> fetchPlans({bool authenticated = true}) async {
    final data = await _standardRequest(
      'GET',
      authenticated ? 'user/plan/fetch' : 'guest/plan/fetch',
      authenticated: authenticated,
    );
    return Ai68Json.array(data, 'plans')
        .map((item) => Ai68Plan.fromJson(Ai68Json.object(item, 'plan')))
        .toList(growable: false);
  }

  @override
  Future<String> createOrder({
    required int planId,
    required Ai68PlanPeriod period,
    String? couponCode,
  }) async {
    final data = await _standardRequest(
      'POST',
      'user/order/save',
      authenticated: true,
      data: <String, dynamic>{
        'plan_id': planId,
        'period': period.apiValue,
        'coupon_code': ?couponCode,
      },
    );
    return Ai68Json.string(data, 'order trade number');
  }

  @override
  Future<Ai68CheckoutResult> checkoutOrder({
    required String tradeNo,
    required int? paymentMethodId,
    String? paymentToken,
  }) async {
    final data = await _rawRequest(
      'POST',
      'user/order/checkout',
      authenticated: true,
      data: <String, dynamic>{
        'trade_no': tradeNo,
        'method': ?paymentMethodId,
        'token': ?paymentToken,
      },
    );
    return Ai68CheckoutResult.fromJson(
      Ai68Json.object(data, 'checkout response'),
    );
  }

  @override
  Future<Ai68OrderStatus> checkOrder(String tradeNo) async {
    final data = await _standardRequest(
      'GET',
      'user/order/check',
      authenticated: true,
      queryParameters: <String, dynamic>{'trade_no': tradeNo},
    );
    return Ai68OrderStatus.fromCode(Ai68Json.integer(data, 'order status'));
  }

  @override
  Future<Ai68Order> fetchOrderDetail(String tradeNo) async {
    final data = await _standardRequest(
      'GET',
      'user/order/detail',
      authenticated: true,
      queryParameters: <String, dynamic>{'trade_no': tradeNo},
    );
    return Ai68Order.fromJson(Ai68Json.object(data, 'order'));
  }

  @override
  Future<List<Ai68Order>> fetchOrders({Ai68OrderStatus? status}) async {
    final data = await _standardRequest(
      'GET',
      'user/order/fetch',
      authenticated: true,
      queryParameters: status == null
          ? null
          : <String, dynamic>{'status': status.code},
    );
    return Ai68Json.array(data, 'orders')
        .map((item) => Ai68Order.fromJson(Ai68Json.object(item, 'order')))
        .toList(growable: false);
  }

  @override
  Future<List<Ai68PaymentMethod>> fetchPaymentMethods() async {
    final data = await _standardRequest(
      'GET',
      'user/order/getPaymentMethod',
      authenticated: true,
    );
    return Ai68Json.array(data, 'payment methods')
        .map(
          (item) => Ai68PaymentMethod.fromJson(
            Ai68Json.object(item, 'payment method'),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> cancelOrder(String tradeNo) async {
    await _standardRequest(
      'POST',
      'user/order/cancel',
      authenticated: true,
      data: <String, dynamic>{'trade_no': tradeNo},
    );
  }

  @override
  Future<Ai68NoticePage> fetchNotices({int page = 1}) async {
    final data = Ai68Json.object(
      await _rawRequest(
        'GET',
        'user/notice/fetch',
        authenticated: true,
        queryParameters: <String, dynamic>{'current': page},
      ),
      'notice page',
    );
    final items = Ai68Json.array(data['data'], 'notices')
        .map((item) => Ai68Notice.fromJson(Ai68Json.object(item, 'notice')))
        .toList(growable: false);
    return Ai68NoticePage(
      items: items,
      total: Ai68Json.optionalInteger(data['total']) ?? items.length,
    );
  }

  @override
  Future<List<Ai68Server>> fetchServers() async {
    final data = Ai68Json.object(
      await _rawRequest('GET', 'user/server/fetch', authenticated: true),
      'servers response',
    );
    return Ai68Json.array(data['data'], 'servers')
        .map((item) => Ai68Server.fromJson(Ai68Json.object(item, 'server')))
        .toList(growable: false);
  }

  @override
  Future<List<Ai68TrafficLog>> fetchTrafficLogs() async {
    final data = await _standardRequest(
      'GET',
      'user/stat/getTrafficLog',
      authenticated: true,
    );
    return Ai68Json.array(data, 'traffic logs')
        .map(
          (item) =>
              Ai68TrafficLog.fromJson(Ai68Json.object(item, 'traffic log')),
        )
        .toList(growable: false);
  }

  @override
  Future<Ai68InviteOverview> fetchInviteOverview() async {
    final data = await _standardRequest(
      'GET',
      'user/invite/fetch',
      authenticated: true,
    );
    return Ai68InviteOverview.fromJson(
      Ai68Json.object(data, 'invite overview'),
    );
  }

  @override
  Future<void> generateInviteCode() async {
    await _standardRequest('GET', 'user/invite/save', authenticated: true);
  }

  @override
  Future<Ai68CommissionPage> fetchCommissionLogs({
    int page = 1,
    int pageSize = 20,
  }) async {
    final data = Ai68Json.object(
      await _rawRequest(
        'GET',
        'user/invite/details',
        authenticated: true,
        queryParameters: <String, dynamic>{
          'current': page,
          'page_size': pageSize,
        },
      ),
      'commission page',
    );
    final items = Ai68Json.array(data['data'], 'commission logs')
        .map(
          (item) => Ai68CommissionLog.fromJson(
            Ai68Json.object(item, 'commission log'),
          ),
        )
        .toList(growable: false);
    return Ai68CommissionPage(
      items: items,
      total: Ai68Json.optionalInteger(data['total']) ?? items.length,
    );
  }

  @override
  Future<void> transferCommission(int amountCents) async {
    await _standardRequest(
      'POST',
      'user/transfer',
      authenticated: true,
      data: <String, dynamic>{'transfer_amount': amountCents},
    );
  }

  @override
  Future<void> withdrawCommission({
    required String method,
    required String account,
  }) async {
    await _standardRequest(
      'POST',
      'user/ticket/withdraw',
      authenticated: true,
      data: <String, dynamic>{
        'withdraw_method': method,
        'withdraw_account': account,
      },
    );
  }

  Future<Object?> _standardRequest(
    String method,
    String path, {
    bool authenticated = false,
    Object? data,
    Map<String, dynamic>? queryParameters,
  }) async {
    final response = Ai68Json.object(
      await _rawRequest(
        method,
        path,
        authenticated: authenticated,
        data: data,
        queryParameters: queryParameters,
      ),
      'API response',
    );
    if (response['status'] != 'success') {
      throw Ai68ApiException(
        message: _messageFrom(response, 'AI68 request failed'),
      );
    }
    if (!response.containsKey('data')) {
      throw const Ai68ApiException(message: 'AI68 response has no data');
    }
    return response['data'];
  }

  Future<Object?> _rawRequest(
    String method,
    String path, {
    bool authenticated = false,
    Object? data,
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await _dio.request<Object?>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(
          method: method,
          extra: <String, dynamic>{_requiresAuthentication: authenticated},
        ),
      );
      return response.data;
    } on DioException catch (error) {
      final cause = error.error;
      if (cause is Ai68ApiException) throw cause;
      final response = error.response;
      throw Ai68ApiException(
        message: _messageFrom(
          response?.data,
          error.message ?? 'Unable to reach AI68',
        ),
        statusCode: response?.statusCode,
      );
    } on FormatException catch (error) {
      throw Ai68ApiException(
        message: 'AI68 returned an invalid response',
        cause: error,
      );
    }
  }

  static String _messageFrom(Object? value, String fallback) {
    if (value is Map) {
      final message = value['message'];
      if (message is String && message.isNotEmpty) return message;
      final error = value['error'];
      if (error is String && error.isNotEmpty) return error;
      final errors = value['errors'];
      if (errors is Map) {
        for (final item in errors.values) {
          if (item is List && item.isNotEmpty) return item.first.toString();
          if (item != null) return item.toString();
        }
      }
    }
    return fallback;
  }

  @override
  void close({bool force = false}) {
    _dio.close(force: force);
  }
}

final class _Ai68AuthorizationInterceptor extends Interceptor {
  _Ai68AuthorizationInterceptor(this._tokenStore);

  final Ai68TokenStore _tokenStore;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    unawaited(_authorize(options, handler));
  }

  Future<void> _authorize(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.extra[Ai68ApiClient._requiresAuthentication] != true) {
      handler.next(options);
      return;
    }
    String? authorization;
    try {
      authorization = await _tokenStore.readApiAuthorization();
    } catch (_) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.unknown,
          error: const Ai68ApiException(
            message: 'Unable to read AI68 authentication',
          ),
        ),
      );
      return;
    }
    if (authorization == null || authorization.trim().isEmpty) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.unknown,
          error: const Ai68ApiException(
            message: 'AI68 authentication is required',
            statusCode: 401,
          ),
        ),
      );
      return;
    }
    options.headers[ai68AuthorizationHeader] =
        authorization.toLowerCase().startsWith('bearer ')
        ? authorization
        : 'Bearer $authorization';
    handler.next(options);
  }
}
