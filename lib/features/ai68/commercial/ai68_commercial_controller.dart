import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/ai68/api/ai68_api_client.dart';
import 'package:fl_clash/features/ai68/api/ai68_api_exception.dart';
import 'package:fl_clash/features/ai68/api/ai68_api_models.dart';
import 'package:fl_clash/features/ai68/auth/ai68_auth_providers.dart';
import 'package:fl_clash/features/ai68/auth/ai68_auth_repository.dart';
import 'package:fl_clash/features/ai68/commercial/ai68_payment_redirect.dart';
import 'package:fl_clash/features/ai68/connect/ai68_smart_connect.dart';
import 'package:fl_clash/features/ai68/subscription/ai68_managed_profile.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

const _unsetAi68Value = Object();
const _ai68CredentialCleanupTimeout = Duration(seconds: 3);
const _ai68RuntimeCleanupTimeout = Duration(seconds: 5);

final class _Ai68OperationCancelled implements Exception {
  const _Ai68OperationCancelled();
}

enum Ai68CommercialPhase { booting, signedOut, localMode, ready, failure }

enum Ai68ConnectionStage {
  idle,
  checkingNetwork,
  synchronizing,
  selectingNode,
  connecting,
  connected,
  stopping,
  failed,
}

final class Ai68CommercialState {
  const Ai68CommercialState({
    required this.phase,
    required this.connectionStage,
    required this.plans,
    required this.orders,
    required this.notices,
    required this.servers,
    required this.selectedRegion,
    this.guestConfig,
    this.user,
    this.subscription,
    this.isRefreshing = false,
    this.isAuthenticating = false,
    this.isOrdering = false,
    this.errorMessage,
  });

  const Ai68CommercialState.initial()
    : this(
        phase: Ai68CommercialPhase.booting,
        connectionStage: Ai68ConnectionStage.idle,
        plans: const [],
        orders: const [],
        notices: const [],
        servers: const [],
        selectedRegion: Ai68Region.automatic,
      );

  final Ai68CommercialPhase phase;
  final Ai68ConnectionStage connectionStage;
  final Ai68GuestConfig? guestConfig;
  final Ai68User? user;
  final Ai68Subscription? subscription;
  final List<Ai68Plan> plans;
  final List<Ai68Order> orders;
  final List<Ai68Notice> notices;
  final List<Ai68Server> servers;
  final Ai68Region selectedRegion;
  final bool isRefreshing;
  final bool isAuthenticating;
  final bool isOrdering;
  final String? errorMessage;

  bool get isAuthenticated {
    return phase == Ai68CommercialPhase.ready && user != null;
  }

  int get remainingBytes {
    final value = subscription;
    if (value == null) return 0;
    return (value.transferEnableBytes - value.usedBytes).clamp(
      0,
      value.transferEnableBytes,
    );
  }

  Ai68CommercialState copyWith({
    Ai68CommercialPhase? phase,
    Ai68ConnectionStage? connectionStage,
    Object? guestConfig = _unsetAi68Value,
    Object? user = _unsetAi68Value,
    Object? subscription = _unsetAi68Value,
    List<Ai68Plan>? plans,
    List<Ai68Order>? orders,
    List<Ai68Notice>? notices,
    List<Ai68Server>? servers,
    Ai68Region? selectedRegion,
    bool? isRefreshing,
    bool? isAuthenticating,
    bool? isOrdering,
    Object? errorMessage = _unsetAi68Value,
  }) {
    return Ai68CommercialState(
      phase: phase ?? this.phase,
      connectionStage: connectionStage ?? this.connectionStage,
      guestConfig: identical(guestConfig, _unsetAi68Value)
          ? this.guestConfig
          : guestConfig as Ai68GuestConfig?,
      user: identical(user, _unsetAi68Value) ? this.user : user as Ai68User?,
      subscription: identical(subscription, _unsetAi68Value)
          ? this.subscription
          : subscription as Ai68Subscription?,
      plans: plans ?? this.plans,
      orders: orders ?? this.orders,
      notices: notices ?? this.notices,
      servers: servers ?? this.servers,
      selectedRegion: selectedRegion ?? this.selectedRegion,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isAuthenticating: isAuthenticating ?? this.isAuthenticating,
      isOrdering: isOrdering ?? this.isOrdering,
      errorMessage: identical(errorMessage, _unsetAi68Value)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}

final ai68CommercialProvider =
    NotifierProvider<Ai68CommercialController, Ai68CommercialState>(
      Ai68CommercialController.new,
    );

final class Ai68CommercialController extends Notifier<Ai68CommercialState> {
  final _sessionScheduler = SerialTaskScheduler();
  final _profileScheduler = SerialTaskScheduler();
  bool _bootstrapped = false;
  int _connectionIntent = 0;
  int _orderPollIntent = 0;
  int _sessionRevision = 0;

  Ai68Api get _api => ref.read(ai68ApiProvider);

  Ai68AuthRepository get _authRepository {
    return ref.read(ai68AuthRepositoryProvider);
  }

  @override
  Ai68CommercialState build() {
    return const Ai68CommercialState.initial();
  }

  Future<void> bootstrap() {
    return _sessionScheduler.run(_bootstrap);
  }

  Future<void> _bootstrap() async {
    if (_bootstrapped) return;
    _bootstrapped = true;
    final revision = ++_sessionRevision;
    state = const Ai68CommercialState.initial();
    final guestConfig = await _loadGuestConfig();
    try {
      final authenticated = await _authRepository.restoreSession();
      if (!_isCurrentSession(revision)) return;
      if (authenticated == null) {
        _connectionIntent++;
        await _stopProxyBestEffort();
        if (!_isCurrentSession(revision)) return;
        Object? cleanupError;
        try {
          await _cleanupManagedProfile();
        } catch (error) {
          cleanupError = error;
        }
        if (!_isCurrentSession(revision)) return;
        state = state.copyWith(
          phase: Ai68CommercialPhase.signedOut,
          guestConfig: guestConfig,
          errorMessage: cleanupError == null ? null : _messageFor(cleanupError),
        );
        return;
      }
      state = state.copyWith(
        phase: Ai68CommercialPhase.ready,
        guestConfig: guestConfig,
        user: authenticated.user,
      );
      _openAi68Center();
      await _refresh(
        revision: revision,
        syncProfile: true,
        startIfConfigured: true,
      );
    } catch (error) {
      if (!_isCurrentSession(revision)) return;
      _connectionIntent++;
      await _stopProxyBestEffort();
      state = state.copyWith(
        phase: Ai68CommercialPhase.failure,
        guestConfig: guestConfig,
        errorMessage: _messageFor(error),
      );
    }
  }

  Future<void> retryBootstrap() {
    return _sessionScheduler.run(() async {
      _bootstrapped = false;
      await _bootstrap();
    });
  }

  Future<void> continueLocalMode() async {
    ref.read(currentPageLabelProvider.notifier).toPage(PageLabel.dashboard);
    state = state.copyWith(
      phase: Ai68CommercialPhase.localMode,
      errorMessage: null,
    );
    globalState.needInitStatus = true;
    await ref.read(setupActionProvider.notifier).initStatus();
    globalState.needInitStatus = false;
  }

  Future<void> exitLocalMode() async {
    await _stopProxyBestEffort();
    state = state.copyWith(
      phase: Ai68CommercialPhase.signedOut,
      connectionStage: Ai68ConnectionStage.idle,
      errorMessage: null,
    );
  }

  void selectRegion(Ai68Region region) {
    state = state.copyWith(selectedRegion: region);
  }

  Future<void> login({required String email, required String password}) {
    return _sessionScheduler.run(() => _login(email, password));
  }

  Future<void> _login(String email, String password) async {
    final revision = ++_sessionRevision;
    _connectionIntent++;
    _orderPollIntent++;
    state = state.copyWith(isAuthenticating: true, errorMessage: null);
    try {
      final authenticated = await _authRepository.login(
        email: email,
        password: password,
      );
      if (!_isCurrentSession(revision)) return;
      state = state.copyWith(
        phase: Ai68CommercialPhase.ready,
        user: authenticated.user,
        isAuthenticating: false,
      );
      _openAi68Center();
      await _refresh(revision: revision, syncProfile: true);
    } catch (error) {
      if (!_isCurrentSession(revision)) return;
      state = state.copyWith(
        isAuthenticating: false,
        errorMessage: _messageFor(error),
      );
      rethrow;
    }
  }

  Future<void> register(Ai68RegisterRequest request) {
    return _sessionScheduler.run(() => _register(request));
  }

  Future<void> _register(Ai68RegisterRequest request) async {
    final revision = ++_sessionRevision;
    _connectionIntent++;
    _orderPollIntent++;
    state = state.copyWith(isAuthenticating: true, errorMessage: null);
    try {
      final authenticated = await _authRepository.register(request);
      if (!_isCurrentSession(revision)) return;
      state = state.copyWith(
        phase: Ai68CommercialPhase.ready,
        user: authenticated.user,
        isAuthenticating: false,
      );
      _openAi68Center();
      await _refresh(revision: revision, syncProfile: true);
    } catch (error) {
      if (!_isCurrentSession(revision)) return;
      state = state.copyWith(
        isAuthenticating: false,
        errorMessage: _messageFor(error),
      );
      rethrow;
    }
  }

  Future<void> sendEmailVerification(
    String email, {
    Ai68CaptchaTokens captchaTokens = const Ai68CaptchaTokens(),
  }) async {
    await _api.sendEmailVerification(
      email: email,
      captchaTokens: captchaTokens,
    );
  }

  Future<void> logout() {
    return _sessionScheduler.run(() => _signOut());
  }

  Future<void> refresh({
    bool syncProfile = false,
    bool startIfConfigured = false,
  }) {
    return _sessionScheduler.run(() {
      return _refresh(
        revision: _sessionRevision,
        syncProfile: syncProfile,
        startIfConfigured: startIfConfigured,
      );
    });
  }

  Future<void> _refresh({
    required int revision,
    bool syncProfile = false,
    bool startIfConfigured = false,
  }) async {
    if (!_isCurrentSession(revision) || !state.isAuthenticated) return;
    state = state.copyWith(isRefreshing: true, errorMessage: null);
    try {
      final user = await _api.fetchUserInfo();
      if (!_isCurrentSession(revision)) return;
      final subscription = await _authRepository.refreshSubscription();
      if (!_isCurrentSession(revision)) return;
      final plans = await _api.fetchPlans();
      final orders = await _loadOrders(state.orders);
      final notices = await _loadNotices(state.notices);
      final servers = await _loadServers(state.servers);
      if (!_isCurrentSession(revision)) return;
      state = state.copyWith(
        phase: Ai68CommercialPhase.ready,
        user: user,
        subscription: subscription,
        plans: plans,
        orders: orders,
        notices: notices,
        servers: servers,
        isRefreshing: false,
      );
      if (!_canUseSubscription(subscription)) {
        await _handleUnavailableSubscription(revision);
        return;
      }
      if (syncProfile) {
        await _synchronizeProfile(subscription, revision);
      }
      if (_isCurrentSession(revision) &&
          startIfConfigured &&
          ref.read(appSettingProvider).autoRun) {
        await _smartConnect(
          revision: revision,
          refreshSubscription: false,
          sessionLocked: true,
        );
      }
    } on Ai68ApiException catch (error) {
      if (!_isCurrentSession(revision)) return;
      if (error.isAuthenticationFailure) {
        await _signOut(message: error.message);
        return;
      }
      state = state.copyWith(isRefreshing: false, errorMessage: error.message);
    } on _Ai68OperationCancelled {
      return;
    } catch (error) {
      if (!_isCurrentSession(revision)) return;
      state = state.copyWith(
        isRefreshing: false,
        errorMessage: _messageFor(error),
      );
    }
  }

  Future<void> smartConnect({
    Ai68Region? region,
    bool refreshSubscription = true,
  }) {
    return _smartConnect(
      revision: _sessionRevision,
      region: region,
      refreshSubscription: refreshSubscription,
    );
  }

  Future<void> _smartConnect({
    required int revision,
    Ai68Region? region,
    bool refreshSubscription = true,
    bool sessionLocked = false,
  }) async {
    if (!_isCurrentSession(revision) || !state.isAuthenticated) return;
    final intent = ++_connectionIntent;
    final selectedRegion = region ?? state.selectedRegion;
    state = state.copyWith(
      selectedRegion: selectedRegion,
      connectionStage: Ai68ConnectionStage.checkingNetwork,
      errorMessage: null,
    );
    try {
      var subscription = state.subscription;
      if (refreshSubscription || subscription == null) {
        subscription = await _sessionScheduler.run(() async {
          if (!_isCurrentSession(revision) || !state.isAuthenticated) {
            throw const _Ai68OperationCancelled();
          }
          return _authRepository.refreshSubscription();
        });
      }
      final activeSubscription = subscription;
      if (activeSubscription == null ||
          !_canUseSubscription(activeSubscription)) {
        await _stopProxyBestEffort();
        throw const Ai68ApiException(
          message: 'AI68 subscription is expired or has no traffic',
        );
      }
      if (!_isCurrentOperation(intent, revision)) return;
      state = state.copyWith(
        subscription: activeSubscription,
        connectionStage: Ai68ConnectionStage.synchronizing,
      );
      await _synchronizeProfile(activeSubscription, revision);
      if (!_isCurrentOperation(intent, revision)) return;
      state = state.copyWith(
        connectionStage: Ai68ConnectionStage.selectingNode,
      );
      await ref.read(proxiesActionProvider.notifier).updateGroups();
      await _selectProxy(selectedRegion);
      if (!_isCurrentOperation(intent, revision)) return;
      state = state.copyWith(connectionStage: Ai68ConnectionStage.connecting);
      await ref
          .read(setupActionProvider.notifier)
          .setRunning(true, requireSuccess: true);
      if (!_isCurrentOperation(intent, revision)) return;
      state = state.copyWith(connectionStage: Ai68ConnectionStage.connected);
    } on _Ai68OperationCancelled {
      return;
    } on Ai68ApiException catch (error) {
      if (error.isAuthenticationFailure && _isCurrentSession(revision)) {
        if (sessionLocked) {
          await _signOut(message: error.message);
        } else {
          await _sessionScheduler.run(() async {
            if (_isCurrentSession(revision)) {
              await _signOut(message: error.message);
            }
          });
        }
        return;
      }
      if (!_isCurrentOperation(intent, revision)) return;
      await _stopProxyBestEffort();
      state = state.copyWith(
        connectionStage: Ai68ConnectionStage.failed,
        errorMessage: error.message,
      );
    } catch (error) {
      if (!_isCurrentOperation(intent, revision)) return;
      await _stopProxyBestEffort();
      state = state.copyWith(
        connectionStage: Ai68ConnectionStage.failed,
        errorMessage: _messageFor(error),
      );
    }
  }

  Future<void> stopConnection() async {
    ++_connectionIntent;
    state = state.copyWith(connectionStage: Ai68ConnectionStage.stopping);
    try {
      await ref.read(setupActionProvider.notifier).setRunning(false);
      state = state.copyWith(connectionStage: Ai68ConnectionStage.idle);
    } catch (error) {
      state = state.copyWith(
        connectionStage: Ai68ConnectionStage.failed,
        errorMessage: _messageFor(error),
      );
    }
  }

  Future<String?> createOrder({
    required int planId,
    required Ai68PlanPeriod period,
    String? couponCode,
  }) async {
    final revision = _sessionRevision;
    if (!_isCurrentSession(revision) || !state.isAuthenticated) return null;
    state = state.copyWith(isOrdering: true, errorMessage: null);
    try {
      final tradeNo = await _api.createOrder(
        planId: planId,
        period: period,
        couponCode: couponCode,
      );
      if (!_isCurrentSession(revision)) return null;
      final orders = await _api.fetchOrders();
      if (!_isCurrentSession(revision)) return null;
      state = state.copyWith(orders: orders, isOrdering: false);
      return tradeNo;
    } catch (error) {
      if (!_isCurrentSession(revision)) return null;
      if (await _handleAuthenticationFailure(error, revision)) return null;
      state = state.copyWith(
        isOrdering: false,
        errorMessage: _messageFor(error),
      );
      return null;
    }
  }

  Future<Ai68CheckoutResult?> checkoutOrder({
    required String tradeNo,
    required int? paymentMethodId,
  }) async {
    final revision = _sessionRevision;
    if (!_isCurrentSession(revision) || !state.isAuthenticated) return null;
    state = state.copyWith(isOrdering: true, errorMessage: null);
    try {
      final result = await _api.checkoutOrder(
        tradeNo: tradeNo,
        paymentMethodId: paymentMethodId,
      );
      if (!_isCurrentSession(revision)) return null;
      if (result.type == -1) {
        state = state.copyWith(isOrdering: false);
        unawaited(pollOrder(tradeNo));
        return result;
      }
      if (result.type != 1) {
        throw const Ai68ApiException(
          message: 'AI68 returned an unsupported payment response',
        );
      }
      final redirectUrl = validateAi68PaymentRedirect(result.redirectUrl);
      final confirmed = await globalState.showMessage(
        title: currentAppLocalizations.externalLink,
        message: TextSpan(text: '${redirectUrl.host}\n$redirectUrl'),
        confirmText: currentAppLocalizations.go,
      );
      if (!_isCurrentSession(revision)) return null;
      if (confirmed != true) {
        state = state.copyWith(isOrdering: false);
        return result;
      }
      final launched = await launchUrl(
        redirectUrl,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw const Ai68ApiException(
          message: 'Unable to open the AI68 payment page',
        );
      }
      state = state.copyWith(isOrdering: false);
      unawaited(pollOrder(tradeNo));
      return result;
    } catch (error) {
      if (!_isCurrentSession(revision)) return null;
      if (await _handleAuthenticationFailure(error, revision)) return null;
      state = state.copyWith(
        isOrdering: false,
        errorMessage: _messageFor(error),
      );
      return null;
    }
  }

  Future<void> pollOrder(String tradeNo, {int attempts = 30}) async {
    final intent = ++_orderPollIntent;
    final revision = _sessionRevision;
    for (var attempt = 0; attempt < attempts; attempt++) {
      if (intent != _orderPollIntent || !_isCurrentSession(revision)) return;
      try {
        final status = await _api.checkOrder(tradeNo);
        if (intent != _orderPollIntent || !_isCurrentSession(revision)) return;
        if (status == Ai68OrderStatus.completed) {
          await refresh(syncProfile: true);
          return;
        }
        if (status == Ai68OrderStatus.cancelled) {
          final orders = await _api.fetchOrders();
          if (intent != _orderPollIntent || !_isCurrentSession(revision)) {
            return;
          }
          state = state.copyWith(orders: orders);
          return;
        }
      } catch (error) {
        if (await _handleAuthenticationFailure(error, revision)) return;
        if (!_isCurrentSession(revision)) return;
        state = state.copyWith(errorMessage: _messageFor(error));
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    final orders = await _loadOrders(state.orders);
    if (intent != _orderPollIntent || !_isCurrentSession(revision)) return;
    state = state.copyWith(orders: orders);
  }

  Future<void> cancelOrder(String tradeNo) async {
    final revision = _sessionRevision;
    if (!_isCurrentSession(revision) || !state.isAuthenticated) return;
    state = state.copyWith(isOrdering: true, errorMessage: null);
    try {
      await _api.cancelOrder(tradeNo);
      if (!_isCurrentSession(revision)) return;
      final orders = await _api.fetchOrders();
      if (!_isCurrentSession(revision)) return;
      state = state.copyWith(orders: orders, isOrdering: false);
    } catch (error) {
      if (!_isCurrentSession(revision)) return;
      if (await _handleAuthenticationFailure(error, revision)) return;
      state = state.copyWith(
        isOrdering: false,
        errorMessage: _messageFor(error),
      );
    }
  }

  Future<List<Ai68PaymentMethod>?> fetchPaymentMethods() async {
    final revision = _sessionRevision;
    if (!_isCurrentSession(revision) || !state.isAuthenticated) return null;
    try {
      final methods = await _api.fetchPaymentMethods();
      return _isCurrentSession(revision) ? methods : null;
    } catch (error) {
      if (!_isCurrentSession(revision)) return null;
      if (await _handleAuthenticationFailure(error, revision)) return null;
      state = state.copyWith(errorMessage: _messageFor(error));
      return null;
    }
  }

  void clearError() {
    state = state.copyWith(errorMessage: null);
  }

  Future<Ai68GuestConfig?> _loadGuestConfig() async {
    try {
      return await _api.fetchGuestConfig();
    } catch (_) {
      return null;
    }
  }

  Future<List<Ai68Order>> _loadOrders(List<Ai68Order> fallback) async {
    try {
      return await _api.fetchOrders();
    } on Ai68ApiException catch (error) {
      if (error.isAuthenticationFailure) rethrow;
      return fallback;
    } catch (_) {
      return fallback;
    }
  }

  Future<List<Ai68Notice>> _loadNotices(List<Ai68Notice> fallback) async {
    try {
      final notices = <Ai68Notice>[];
      for (var page = 1; page <= 20; page++) {
        final result = await _api.fetchNotices(page: page);
        notices.addAll(result.items);
        if (notices.length >= result.total || result.items.isEmpty) break;
      }
      return notices;
    } on Ai68ApiException catch (error) {
      if (error.isAuthenticationFailure) rethrow;
      return fallback;
    } catch (_) {
      return fallback;
    }
  }

  Future<List<Ai68Server>> _loadServers(List<Ai68Server> fallback) async {
    try {
      return await _api.fetchServers();
    } on Ai68ApiException catch (error) {
      if (error.isAuthenticationFailure) rethrow;
      return fallback;
    } catch (_) {
      return fallback;
    }
  }

  Future<void> _synchronizeProfile(
    Ai68Subscription subscription,
    int revision,
  ) {
    return _profileScheduler.run(() async {
      if (!_isCurrentSession(revision)) {
        throw const _Ai68OperationCancelled();
      }
      final profile = await ref
          .read(ai68ProfileSynchronizerProvider)
          .synchronize(
            subscription: subscription,
            profiles: ref.read(profilesProvider),
            userAgent: globalState.packageInfo.ua,
          );
      ref.read(profilesActionProvider.notifier).putProfile(profile);
      ref.read(currentProfileIdProvider.notifier).value = profile.id;
      if (!_isCurrentSession(revision)) {
        throw const _Ai68OperationCancelled();
      }
      await ref
          .read(setupActionProvider.notifier)
          .applyProfile(force: true, silence: true, throwOnError: true);
      if (!_isCurrentSession(revision)) {
        throw const _Ai68OperationCancelled();
      }
    });
  }

  Future<void> _selectProxy(Ai68Region region) async {
    final groups = ref.read(groupsProvider);
    if (groups.isEmpty) {
      throw const Ai68ApiException(
        message: 'AI68 did not provide any available proxy groups',
      );
    }
    final strategyGroup = Ai68SmartConnectPolicy.strategyGroup(groups, region);
    final strategy = Ai68SmartConnectPolicy.strategySelection(groups, region);
    if (strategyGroup != null) {
      if (strategy != null) {
        await _changeProxy(strategy);
      }
      return;
    }
    final selector = Ai68SmartConnectPolicy.fallbackSelector(groups, region);
    if (selector == null) {
      throw const Ai68ApiException(
        message: 'No AI68 nodes match the selected region',
      );
    }
    final groupNames = groups.map((group) => group.name).toSet();
    final regionalSelector =
        region != Ai68Region.automatic &&
        Ai68SmartConnectPolicy.matchesRegion(selector.name, region);
    final candidates = selector.all.where((proxy) {
      final name = proxy.name;
      return name != UsedProxy.DIRECT.name &&
          name != UsedProxy.REJECT.name &&
          !groupNames.contains(name) &&
          (region == Ai68Region.automatic ||
              regionalSelector ||
              Ai68SmartConnectPolicy.matchesRegion(name, region));
    }).toList();
    if (candidates.isEmpty) {
      throw const Ai68ApiException(
        message: 'No AI68 nodes match the selected region',
      );
    }
    final testUrl = ref.read(appSettingProvider).testUrl;
    final delayValues = <String, int>{};
    for (var offset = 0; offset < candidates.length; offset += 50) {
      final end = (offset + 50).clamp(0, candidates.length);
      final batch = candidates.sublist(offset, end);
      await Future.wait(
        batch.map((proxy) async {
          try {
            final delay = await coreController.getDelay(testUrl, proxy.name);
            ref.read(proxiesActionProvider.notifier).setDelay(delay);
            final value = delay.value;
            if (value != null && value > 0) {
              delayValues[proxy.name] = value;
            }
          } catch (_) {
            ref
                .read(proxiesActionProvider.notifier)
                .setDelay(Delay(url: testUrl, name: proxy.name, value: -1));
          }
        }),
      );
    }
    if (delayValues.isEmpty) {
      throw const Ai68ApiException(message: 'No reachable AI68 node was found');
    }
    final best = delayValues.entries.reduce(
      (current, next) => next.value < current.value ? next : current,
    );
    await _changeProxy(
      Ai68ProxySelection(groupName: selector.name, proxyName: best.key),
    );
    await _activateParentSelectors(groups, selector.name);
  }

  Future<void> _activateParentSelectors(
    List<Group> groups,
    String selectedGroupName,
  ) async {
    final visited = <String>{selectedGroupName};
    var childName = selectedGroupName;
    while (true) {
      Group? parent;
      for (final group in groups) {
        if (group.type != GroupType.Selector || visited.contains(group.name)) {
          continue;
        }
        if (group.all.any((proxy) => proxy.name == childName)) {
          parent = group;
          break;
        }
      }
      if (parent == null) return;
      await _changeProxy(
        Ai68ProxySelection(groupName: parent.name, proxyName: childName),
      );
      childName = parent.name;
      visited.add(childName);
    }
  }

  Future<void> _changeProxy(Ai68ProxySelection selection) async {
    ref
        .read(profilesActionProvider.notifier)
        .updateCurrentSelectedMap(selection.groupName, selection.proxyName);
    await ref
        .read(proxiesActionProvider.notifier)
        .changeProxy(
          groupName: selection.groupName,
          proxyName: selection.proxyName,
          throwOnError: true,
        );
  }

  Future<void> _handleUnavailableSubscription(int revision) async {
    if (!_isCurrentSession(revision)) return;
    ++_connectionIntent;
    await _stopProxyBestEffort();
    if (!_isCurrentSession(revision)) return;
    state = state.copyWith(
      isRefreshing: false,
      connectionStage: Ai68ConnectionStage.failed,
      errorMessage: 'AI68 subscription is expired or has no traffic',
    );
  }

  Future<void> _signOut({String? message}) async {
    final guestConfig = state.guestConfig;
    ++_sessionRevision;
    ++_connectionIntent;
    ++_orderPollIntent;
    state = Ai68CommercialState(
      phase: Ai68CommercialPhase.signedOut,
      connectionStage: Ai68ConnectionStage.idle,
      guestConfig: guestConfig,
      plans: const [],
      orders: const [],
      notices: const [],
      servers: const [],
      selectedRegion: Ai68Region.automatic,
      errorMessage: message,
    );
    Object? firstError;

    Future<void> runCleanup(Future<void> Function() action) async {
      try {
        await action();
      } catch (error) {
        firstError ??= error;
      }
    }

    await runCleanup(
      () => _authRepository.logout().timeout(_ai68CredentialCleanupTimeout),
    );
    await runCleanup(
      () => ref
          .read(setupActionProvider.notifier)
          .setRunning(false)
          .timeout(_ai68RuntimeCleanupTimeout),
    );
    await runCleanup(
      () => _cleanupManagedProfile().timeout(_ai68RuntimeCleanupTimeout),
    );

    state = state.copyWith(
      errorMessage:
          message ?? (firstError == null ? null : _messageFor(firstError!)),
    );
  }

  Future<void> _cleanupManagedProfile() {
    return _profileScheduler.run(() async {
      Object? firstError;
      final profileStore = ref.read(ai68ManagedProfileStoreProvider);
      try {
        final profileId = await profileStore.readProfileId();
        if (profileId != null) {
          await ref
              .read(profilesActionProvider.notifier)
              .deleteProfile(profileId);
        }
      } catch (error) {
        firstError = error;
      }
      try {
        await ref.read(ai68ProfileSynchronizerProvider).clear();
      } catch (error) {
        firstError ??= error;
      }
      if (firstError != null) throw firstError;
    });
  }

  Future<Object?> _stopProxyBestEffort() async {
    try {
      await ref.read(setupActionProvider.notifier).setRunning(false);
      return null;
    } catch (error) {
      return error;
    }
  }

  Future<bool> _handleAuthenticationFailure(Object error, int revision) async {
    if (error is! Ai68ApiException ||
        !error.isAuthenticationFailure ||
        !_isCurrentSession(revision)) {
      return false;
    }
    await _sessionScheduler.run(() async {
      if (_isCurrentSession(revision)) {
        await _signOut(message: error.message);
      }
    });
    return true;
  }

  bool _canUseSubscription(Ai68Subscription subscription) {
    final expiredAt = subscription.expiredAt;
    final isExpired =
        expiredAt != null &&
        DateTime.fromMillisecondsSinceEpoch(
          expiredAt * 1000,
        ).isBefore(DateTime.now());
    return !isExpired &&
        subscription.transferEnableBytes > subscription.usedBytes;
  }

  bool _isCurrentConnection(int intent) {
    return intent == _connectionIntent;
  }

  bool _isCurrentSession(int revision) {
    return revision == _sessionRevision;
  }

  bool _isCurrentOperation(int intent, int revision) {
    return _isCurrentConnection(intent) && _isCurrentSession(revision);
  }

  void _openAi68Center() {
    ref.read(currentPageLabelProvider.notifier).toPage(PageLabel.ai68Center);
  }

  String _messageFor(Object error) {
    return error is Ai68ApiException ? error.message : error.toString();
  }
}
