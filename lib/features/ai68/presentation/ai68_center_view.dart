import 'dart:math';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/features/ai68/api/ai68_api_client.dart';
import 'package:fl_clash/features/ai68/api/ai68_api_models.dart';
import 'package:fl_clash/features/ai68/commercial/ai68_commercial_controller.dart';
import 'package:fl_clash/features/ai68/connect/ai68_smart_connect.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class Ai68CenterView extends ConsumerStatefulWidget {
  const Ai68CenterView({super.key});

  @override
  ConsumerState<Ai68CenterView> createState() => _Ai68CenterViewState();
}

class _Ai68CenterViewState extends ConsumerState<Ai68CenterView> {
  Ai68Region _nodeRegion = Ai68Region.automatic;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ai68CommercialProvider);
    if (!state.isAuthenticated) {
      return _Ai68SignedOutCenter(
        onLogin: () {
          ref.read(ai68CommercialProvider.notifier).exitLocalMode();
        },
      );
    }
    final l10n = context.appLocalizations;
    return DefaultTabController(
      length: 7,
      child: CommonScaffold(
        title: l10n.ai68Center,
        isLoading: state.isRefreshing,
        actions: [
          IconButton(
            onPressed: state.isRefreshing
                ? null
                : () {
                    ref.read(ai68CommercialProvider.notifier).refresh();
                  },
            tooltip: l10n.ai68Refresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: state.isAuthenticating
                ? null
                : () {
                    ref.read(ai68CommercialProvider.notifier).logout();
                  },
            tooltip: l10n.ai68Logout,
            icon: const Icon(Icons.logout),
          ),
        ],
        body: Column(
          children: [
            _Ai68ConnectionBand(state: state),
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(icon: const Icon(Icons.person), text: l10n.ai68Account),
                Tab(icon: const Icon(Icons.shopping_bag), text: l10n.ai68Store),
                Tab(
                  icon: const Icon(Icons.receipt_long),
                  text: l10n.ai68Orders,
                ),
                Tab(
                  icon: const Icon(Icons.card_giftcard),
                  text: l10n.ai68MyInvites,
                ),
                Tab(icon: const Icon(Icons.public), text: l10n.ai68Nodes),
                Tab(
                  icon: const Icon(Icons.notifications),
                  text: l10n.ai68Notices,
                ),
                Tab(
                  icon: const Icon(Icons.account_circle_outlined),
                  text: l10n.ai68Me,
                ),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _Ai68AccountTab(state: state),
                  _Ai68PlansTab(state: state, onBuy: _buyPlan),
                  _Ai68OrdersTab(state: state, onPay: _payOrder),
                  _Ai68InviteTab(state: state),
                  _Ai68NodesTab(
                    state: state,
                    selectedRegion: _nodeRegion,
                    onRegionChanged: (region) {
                      setState(() => _nodeRegion = region);
                    },
                  ),
                  _Ai68NoticesTab(state: state),
                  _Ai68MeTab(state: state),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _buyPlan(Ai68Plan plan) async {
    final hasPrice = plan.pricesCents.values.any((price) => (price ?? 0) > 0);
    if (!hasPrice) return;
    final request = await showDialog<_Ai68OrderRequest>(
      context: context,
      builder: (context) => _Ai68CreateOrderDialog(plan: plan),
    );
    if (request == null || !mounted) return;
    final tradeNo = await ref
        .read(ai68CommercialProvider.notifier)
        .createOrder(
          planId: plan.id,
          period: request.period,
          couponCode: request.couponCode,
        );
    if (tradeNo == null || !mounted) return;
    await _selectPayment(tradeNo);
  }

  Future<void> _payOrder(Ai68Order order) async {
    await _selectPayment(order.tradeNo);
  }

  Future<void> _selectPayment(String tradeNo) async {
    final controller = ref.read(ai68CommercialProvider.notifier);
    final methods = await controller.fetchPaymentMethods();
    if (!mounted || methods == null) return;
    if (methods.isEmpty) {
      await controller.checkoutOrder(tradeNo: tradeNo, paymentMethodId: null);
      return;
    }
    final method = await showDialog<Ai68PaymentMethod>(
      context: context,
      builder: (context) {
        final l10n = context.appLocalizations;
        return AlertDialog(
          title: Text(l10n.ai68SelectPayment),
          content: SizedBox(
            width: 360,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: methods.length,
              itemBuilder: (context, index) {
                final method = methods[index];
                return ListTile(
                  leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: Text(method.name),
                  subtitle: method.handlingFeePercent > 0
                      ? Text('${method.handlingFeePercent}%')
                      : null,
                  onTap: () => Navigator.of(context).pop(method),
                );
              },
              separatorBuilder: (_, _) => const Divider(height: 1),
            ),
          ),
        );
      },
    );
    if (method == null) return;
    await controller.checkoutOrder(
      tradeNo: tradeNo,
      paymentMethodId: method.id,
    );
  }
}

class _Ai68ConnectionBand extends ConsumerWidget {
  const _Ai68ConnectionBand({required this.state});

  final Ai68CommercialState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.appLocalizations;
    final isRunning = ref.watch(isStartProvider);
    final busy = const {
      Ai68ConnectionStage.checkingNetwork,
      Ai68ConnectionStage.synchronizing,
      Ai68ConnectionStage.selectingNode,
      Ai68ConnectionStage.connecting,
      Ai68ConnectionStage.stopping,
    }.contains(state.connectionStage);
    final displayStage =
        busy || state.connectionStage == Ai68ConnectionStage.failed
        ? state.connectionStage
        : isRunning
        ? Ai68ConnectionStage.connected
        : Ai68ConnectionStage.idle;
    return ColoredBox(
      color: context.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Align(
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 720;
                final regions = SegmentedButton<Ai68Region>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: Ai68Region.automatic,
                      icon: const Icon(Icons.auto_awesome),
                      label: Text(l10n.ai68Automatic),
                    ),
                    ButtonSegment(
                      value: Ai68Region.unitedStates,
                      label: Text(l10n.ai68UnitedStates),
                    ),
                    ButtonSegment(
                      value: Ai68Region.japan,
                      label: Text(l10n.ai68Japan),
                    ),
                    ButtonSegment(
                      value: Ai68Region.hongKong,
                      label: Text(l10n.ai68HongKong),
                    ),
                  ],
                  selected: {state.selectedRegion},
                  onSelectionChanged: busy
                      ? null
                      : (regions) {
                          ref
                              .read(ai68CommercialProvider.notifier)
                              .selectRegion(regions.first);
                        },
                );
                final action = SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: busy
                        ? null
                        : isRunning
                        ? () {
                            ref
                                .read(ai68CommercialProvider.notifier)
                                .stopConnection();
                          }
                        : () {
                            ref
                                .read(ai68CommercialProvider.notifier)
                                .smartConnect();
                          },
                    icon: busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            isRunning ? Icons.stop : Icons.power_settings_new,
                          ),
                    label: Text(
                      busy
                          ? l10n.ai68Connecting
                          : isRunning
                          ? l10n.ai68Disconnect
                          : l10n.ai68Connect,
                    ),
                  ),
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _connectionLabel(context, displayStage),
                      style: context.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    if (narrow)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: regions,
                          ),
                          const SizedBox(height: 12),
                          action,
                        ],
                      )
                    else
                      Row(
                        children: [
                          Expanded(child: regions),
                          const SizedBox(width: 16),
                          action,
                        ],
                      ),
                    if (state.errorMessage != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        state.errorMessage!,
                        style: TextStyle(color: context.colorScheme.error),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  String _connectionLabel(BuildContext context, Ai68ConnectionStage stage) {
    final l10n = context.appLocalizations;
    return switch (stage) {
      Ai68ConnectionStage.checkingNetwork => l10n.ai68AutoDetectNetwork,
      Ai68ConnectionStage.synchronizing => l10n.update,
      Ai68ConnectionStage.selectingNode => l10n.ai68AutoSelectNode,
      Ai68ConnectionStage.connecting => l10n.ai68Connecting,
      Ai68ConnectionStage.connected => l10n.connected,
      Ai68ConnectionStage.stopping => l10n.ai68Disconnect,
      Ai68ConnectionStage.failed => l10n.networkException,
      Ai68ConnectionStage.idle => l10n.ai68WelcomeSubtitle,
    };
  }
}

class _Ai68AccountTab extends StatelessWidget {
  const _Ai68AccountTab({required this.state});

  final Ai68CommercialState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final subscription = state.subscription;
    final trafficRatio =
        subscription == null || subscription.transferEnableBytes <= 0
        ? 0.0
        : min<double>(
            1,
            subscription.usedBytes / subscription.transferEnableBytes,
          );
    final expiry = _formatEpoch(context, subscription?.expiredAt);
    final lowTraffic = subscription != null && trafficRatio >= 0.9;
    final expiringSoon = _expiresSoon(subscription?.expiredAt);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (lowTraffic || expiringSoon)
          MaterialBanner(
            content: Text(
              lowTraffic ? l10n.ai68TrafficReminder : l10n.ai68ExpiryReminder,
            ),
            leading: const Icon(Icons.warning_amber),
            actions: const [SizedBox.shrink()],
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _Ai68MetricCard(
              icon: Icons.person_outline,
              label: l10n.ai68Account,
              value: state.user?.email ?? '-',
            ),
            _Ai68MetricCard(
              icon: Icons.workspace_premium_outlined,
              label: l10n.ai68Plan,
              value: subscription?.plan?.name ?? l10n.ai68NoPlan,
            ),
            _Ai68MetricCard(
              icon: Icons.event_outlined,
              label: l10n.ai68Expiry,
              value: expiry,
            ),
            _Ai68MetricCard(
              icon: Icons.account_balance_wallet_outlined,
              label: l10n.ai68Balance,
              value: _formatMoney(context, state.user?.balanceCents ?? 0),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(l10n.ai68Traffic, style: context.textTheme.titleMedium),
        const SizedBox(height: 12),
        LinearProgressIndicator(value: trafficRatio),
        const SizedBox(height: 10),
        Wrap(
          spacing: 24,
          runSpacing: 10,
          children: [
            _Ai68TrafficValue(
              label: l10n.ai68UsedTraffic,
              value: _formatBytes(subscription?.usedBytes ?? 0),
            ),
            _Ai68TrafficValue(
              label: '${l10n.ai68RemainingTraffic} / ${l10n.ai68TotalTraffic}',
              value:
                  '${_formatBytes(state.remainingBytes)} / ${_formatBytes(subscription?.transferEnableBytes ?? 0)}',
            ),
          ],
        ),
      ],
    );
  }
}

class _Ai68MeTab extends ConsumerStatefulWidget {
  const _Ai68MeTab({required this.state});

  final Ai68CommercialState state;

  @override
  ConsumerState<_Ai68MeTab> createState() => _Ai68MeTabState();
}

class _Ai68MeTabState extends ConsumerState<_Ai68MeTab> {
  final _formKey = GlobalKey<FormState>();
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscureOldPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_formKey.currentState?.validate() != true) return;
    FocusScope.of(context).unfocus();
    final controller = ref.read(ai68CommercialProvider.notifier);
    final changed = await controller.changePassword(
      oldPassword: _oldPasswordController.text,
      newPassword: _newPasswordController.text,
    );
    if (!mounted) return;
    if (changed) {
      _oldPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      context.showSnackBar(context.appLocalizations.ai68PasswordChanged);
      return;
    }
    final message = ref.read(ai68CommercialProvider).errorMessage;
    if (message != null) context.showSnackBar(message);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final state = widget.state;
    final currency = state.userConfig?.currency ?? 'CNY';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CommonCard(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: context.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.account_balance_wallet_outlined,
                            color: context.colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.ai68MyWallet,
                                style: context.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.end,
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  Text(
                                    _formatMoney(
                                      context,
                                      state.user?.balanceCents ?? 0,
                                      symbol:
                                          state.userConfig?.currencySymbol ??
                                          '¥',
                                    ),
                                    style: context.textTheme.headlineSmall,
                                  ),
                                  Text(
                                    currency,
                                    style: context.textTheme.labelLarge
                                        ?.copyWith(
                                          color: context
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                l10n.ai68AccountBalanceOnly,
                                style: context.textTheme.bodySmall?.copyWith(
                                  color: context.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                CommonCard(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: AutofillGroup(
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              l10n.ai68ChangePassword,
                              style: context.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 18),
                            TextFormField(
                              controller: _oldPasswordController,
                              autofillHints: const [AutofillHints.password],
                              inputFormatters: TextInputLimits.limit(32),
                              obscureText: _obscureOldPassword,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                labelText: l10n.ai68OldPassword,
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  onPressed: () {
                                    setState(() {
                                      _obscureOldPassword =
                                          !_obscureOldPassword;
                                    });
                                  },
                                  tooltip: l10n.ai68OldPassword,
                                  icon: Icon(
                                    _obscureOldPassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return l10n.ai68OldPassword;
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _newPasswordController,
                              autofillHints: const [AutofillHints.newPassword],
                              inputFormatters: TextInputLimits.limit(32),
                              obscureText: _obscureNewPassword,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                labelText: l10n.ai68NewPassword,
                                prefixIcon: const Icon(Icons.password),
                                suffixIcon: IconButton(
                                  onPressed: () {
                                    setState(() {
                                      _obscureNewPassword =
                                          !_obscureNewPassword;
                                    });
                                  },
                                  tooltip: l10n.ai68NewPassword,
                                  icon: Icon(
                                    _obscureNewPassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.length < 8) {
                                  return l10n.ai68PasswordRequirement;
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _confirmPasswordController,
                              autofillHints: const [AutofillHints.newPassword],
                              inputFormatters: TextInputLimits.limit(32),
                              obscureText: _obscureConfirmPassword,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _submit(),
                              decoration: InputDecoration(
                                labelText: l10n.ai68ConfirmNewPassword,
                                prefixIcon: const Icon(Icons.password),
                                suffixIcon: IconButton(
                                  onPressed: () {
                                    setState(() {
                                      _obscureConfirmPassword =
                                          !_obscureConfirmPassword;
                                    });
                                  },
                                  tooltip: l10n.ai68ConfirmNewPassword,
                                  icon: Icon(
                                    _obscureConfirmPassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                              validator: (value) {
                                if (value != _newPasswordController.text) {
                                  return l10n.ai68PasswordMismatch;
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 20),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.icon(
                                onPressed: state.isChangingPassword
                                    ? null
                                    : _submit,
                                icon: state.isChangingPassword
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.save_outlined),
                                label: Text(l10n.ai68Save),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Ai68TrafficValue extends StatelessWidget {
  const _Ai68TrafficValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 180),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.textTheme.labelMedium?.copyWith(
              color: context.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 3),
          Text(value, style: context.textTheme.titleSmall),
        ],
      ),
    );
  }
}

class _Ai68MetricCard extends StatelessWidget {
  const _Ai68MetricCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 250,
      height: 104,
      child: CommonCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: context.colorScheme.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: context.textTheme.labelLarge?.copyWith(
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Ai68InviteTab extends ConsumerWidget {
  const _Ai68InviteTab({required this.state});

  final Ai68CommercialState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.appLocalizations;
    final overview = state.inviteOverview;
    if (overview == null) {
      return _Ai68EmptyState(
        icon: Icons.card_giftcard,
        text: l10n.ai68NoInviteData,
      );
    }
    final config = state.userConfig;
    final stats = overview.stats;
    final currencySymbol = config?.currencySymbol ?? '¥';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        CommonCard(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 24,
              runSpacing: 16,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatMoney(
                        context,
                        stats.availableCommissionCents,
                        symbol: currencySymbol,
                      ),
                      style: context.textTheme.headlineMedium?.copyWith(
                        color: context.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.ai68AvailableCommission,
                      style: context.textTheme.bodyMedium?.copyWith(
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: state.isInviting
                          ? null
                          : () => _transfer(context, ref, stats),
                      icon: const Icon(Icons.swap_horiz),
                      label: Text(l10n.ai68Transfer),
                    ),
                    if (config != null &&
                        !config.withdrawClosed &&
                        config.withdrawMethods.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: state.isInviting
                            ? null
                            : () => _withdraw(context, ref, config),
                        icon: const Icon(Icons.account_balance_outlined),
                        label: Text(l10n.ai68Withdraw),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _Ai68MetricCard(
              icon: Icons.group_outlined,
              label: l10n.ai68RegisteredUsers,
              value: l10n.ai68People(stats.registeredUsers),
            ),
            _Ai68MetricCard(
              icon: Icons.percent,
              label: l10n.ai68CommissionRate,
              value: _commissionRate(config, stats),
            ),
            _Ai68MetricCard(
              icon: Icons.hourglass_top,
              label: l10n.ai68PendingCommission,
              value: _formatMoney(
                context,
                stats.pendingCommissionCents,
                symbol: currencySymbol,
              ),
            ),
            _Ai68MetricCard(
              icon: Icons.savings_outlined,
              label: l10n.ai68CumulativeCommission,
              value: _formatMoney(
                context,
                stats.cumulativeCommissionCents,
                symbol: currencySymbol,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _Ai68InviteSectionHeader(
          title: l10n.ai68InviteCodeManagement,
          action: FilledButton.icon(
            onPressed: state.isInviting
                ? null
                : () => _generateCode(context, ref),
            icon: const Icon(Icons.add),
            label: Text(l10n.ai68GenerateInviteCode),
          ),
        ),
        const SizedBox(height: 8),
        if (overview.codes.isEmpty)
          _Ai68EmptyState(
            icon: Icons.card_giftcard,
            text: l10n.ai68NoInviteCodes,
          )
        else
          ...overview.codes.map(
            (code) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.confirmation_number_outlined),
                title: SelectableText(code.code),
                subtitle: Text(_formatEpoch(context, code.createdAt)),
                trailing: IconButton(
                  onPressed: () => _copyInviteLink(context, code.code),
                  tooltip: l10n.ai68CopyInviteLink,
                  icon: const Icon(Icons.content_copy),
                ),
              ),
            ),
          ),
        const SizedBox(height: 16),
        _Ai68InviteSectionHeader(title: l10n.ai68CommissionHistory),
        const SizedBox(height: 8),
        if (state.commissionLogs.isEmpty)
          _Ai68EmptyState(
            icon: Icons.receipt_long_outlined,
            text: l10n.ai68NoCommissionRecords,
          )
        else
          ...state.commissionLogs.map(
            (log) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.payments_outlined),
                title: Text(_formatEpoch(context, log.createdAt)),
                subtitle: Text(l10n.ai68CommissionPaidAt),
                trailing: Text(
                  _formatMoney(
                    context,
                    log.amountCents,
                    symbol: currencySymbol,
                  ),
                  style: context.textTheme.titleMedium?.copyWith(
                    color: context.colorScheme.primary,
                  ),
                ),
              ),
            ),
          ),
        if (state.commissionLogs.length < state.commissionTotal)
          Center(
            child: OutlinedButton.icon(
              onPressed: state.isInviting
                  ? null
                  : () {
                      ref
                          .read(ai68CommercialProvider.notifier)
                          .loadMoreCommissionLogs();
                    },
              icon: const Icon(Icons.expand_more),
              label: Text(l10n.ai68LoadMore),
            ),
          ),
      ],
    );
  }

  String _commissionRate(Ai68UserConfig? config, Ai68InviteStats stats) {
    if (config == null || !config.commissionDistributionEnabled) {
      return '${stats.commissionRate}%';
    }
    return config.commissionDistributionRates
        .map((rate) => '${rate * stats.commissionRate ~/ 100}%')
        .join(' / ');
  }

  Future<void> _generateCode(BuildContext context, WidgetRef ref) async {
    final created = await ref
        .read(ai68CommercialProvider.notifier)
        .generateInviteCode();
    if (created && context.mounted) {
      context.showSnackBar(context.appLocalizations.ai68InviteCodeCreated);
    }
  }

  Future<void> _copyInviteLink(BuildContext context, String code) async {
    final baseUrl = state.guestConfig?.appUrl ?? ai68ApiBaseUrl;
    final normalized = baseUrl.replaceFirst(RegExp(r'/api/v1/?$'), '');
    final link =
        '${normalized.replaceFirst(RegExp(r'/$'), '')}'
        '/#/register?code=${Uri.encodeComponent(code)}';
    await Clipboard.setData(ClipboardData(text: link));
    if (context.mounted) {
      context.showSnackBar(context.appLocalizations.ai68CopySuccess);
    }
  }

  Future<void> _transfer(
    BuildContext context,
    WidgetRef ref,
    Ai68InviteStats stats,
  ) async {
    final amount = await showDialog<int>(
      context: context,
      builder: (context) => _Ai68TransferDialog(
        availableCents: stats.availableCommissionCents,
        currencySymbol: state.userConfig?.currencySymbol ?? '¥',
      ),
    );
    if (amount == null || !context.mounted) return;
    final transferred = await ref
        .read(ai68CommercialProvider.notifier)
        .transferCommission(amount);
    if (transferred && context.mounted) {
      context.showSnackBar(context.appLocalizations.ai68TransferSuccess);
    }
  }

  Future<void> _withdraw(
    BuildContext context,
    WidgetRef ref,
    Ai68UserConfig config,
  ) async {
    final request = await showDialog<_Ai68WithdrawRequest>(
      context: context,
      builder: (context) =>
          _Ai68WithdrawDialog(methods: config.withdrawMethods),
    );
    if (request == null || !context.mounted) return;
    final submitted = await ref
        .read(ai68CommercialProvider.notifier)
        .withdrawCommission(method: request.method, account: request.account);
    if (submitted && context.mounted) {
      context.showSnackBar(context.appLocalizations.ai68WithdrawSubmitted);
    }
  }
}

class _Ai68InviteSectionHeader extends StatelessWidget {
  const _Ai68InviteSectionHeader({required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(title, style: context.textTheme.titleMedium)),
        ?action,
      ],
    );
  }
}

class _Ai68TransferDialog extends StatefulWidget {
  const _Ai68TransferDialog({
    required this.availableCents,
    required this.currencySymbol,
  });

  final int availableCents;
  final String currencySymbol;

  @override
  State<_Ai68TransferDialog> createState() => _Ai68TransferDialogState();
}

class _Ai68TransferDialogState extends State<_Ai68TransferDialog> {
  final _controller = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    return AlertDialog(
      title: Text(l10n.ai68TransferCommissionTitle),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.ai68TransferCommissionHint),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: l10n.ai68TransferAmount,
                prefixText: widget.currencySymbol,
                helperText: _formatMoney(
                  context,
                  widget.availableCents,
                  symbol: widget.currencySymbol,
                ),
                errorText: _errorText,
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.confirm)),
      ],
    );
  }

  void _submit() {
    final amount = double.tryParse(_controller.text.trim());
    final cents = amount == null ? 0 : (amount * 100).round();
    if (cents <= 0 || cents > widget.availableCents) {
      setState(() {
        _errorText = context.appLocalizations.ai68TransferAmountInvalid;
      });
      return;
    }
    Navigator.of(context).pop(cents);
  }
}

final class _Ai68WithdrawRequest {
  const _Ai68WithdrawRequest({required this.method, required this.account});

  final String method;
  final String account;
}

class _Ai68WithdrawDialog extends StatefulWidget {
  const _Ai68WithdrawDialog({required this.methods});

  final List<String> methods;

  @override
  State<_Ai68WithdrawDialog> createState() => _Ai68WithdrawDialogState();
}

class _Ai68WithdrawDialogState extends State<_Ai68WithdrawDialog> {
  final _accountController = TextEditingController();
  String? _method;
  String? _errorText;

  @override
  void dispose() {
    _accountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    return AlertDialog(
      title: Text(l10n.ai68WithdrawCommissionTitle),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _method,
              decoration: InputDecoration(labelText: l10n.ai68WithdrawMethod),
              hint: Text(l10n.ai68SelectWithdrawMethod),
              items: widget.methods
                  .map(
                    (method) =>
                        DropdownMenuItem(value: method, child: Text(method)),
                  )
                  .toList(),
              onChanged: (method) => setState(() => _method = method),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _accountController,
              decoration: InputDecoration(
                labelText: l10n.ai68WithdrawAccount,
                hintText: l10n.ai68WithdrawAccountHint,
                errorText: _errorText,
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.confirm)),
      ],
    );
  }

  void _submit() {
    final account = _accountController.text.trim();
    if (_method == null || account.isEmpty) {
      setState(() {
        _errorText = context.appLocalizations.ai68WithdrawDetailsRequired;
      });
      return;
    }
    Navigator.of(
      context,
    ).pop(_Ai68WithdrawRequest(method: _method!, account: account));
  }
}

class _Ai68PlansTab extends StatelessWidget {
  const _Ai68PlansTab({required this.state, required this.onBuy});

  final Ai68CommercialState state;
  final ValueChanged<Ai68Plan> onBuy;

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final plans = state.plans.where((plan) => plan.show && plan.sell).toList();
    if (plans.isEmpty) {
      return _Ai68EmptyState(icon: Icons.shopping_bag, text: l10n.ai68NoPlan);
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: plans.length,
      itemBuilder: (context, index) {
        final plan = plans[index];
        final prices = plan.pricesCents.entries
            .where((entry) => (entry.value ?? 0) > 0)
            .map((entry) => MapEntry(entry.key, entry.value!))
            .toList(growable: false);
        final lowest = prices.isEmpty
            ? null
            : prices.map((entry) => entry.value).reduce(min);
        return CommonCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 600;
                final identity = Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: context.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.workspace_premium_outlined,
                        color: context.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(plan.name, style: context.textTheme.titleMedium),
                          if (plan.tags.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: plan.tags
                                  .map((tag) => _Ai68PlanTag(text: tag))
                                  .toList(growable: false),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                );
                final action = Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      lowest == null ? '-' : _formatMoney(context, lowest),
                      style: context.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    FilledButton.icon(
                      onPressed: state.isOrdering || lowest == null
                          ? null
                          : () => onBuy(plan),
                      icon: const Icon(Icons.shopping_cart_checkout),
                      label: Text(l10n.ai68Buy),
                    ),
                  ],
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (isCompact)
                      identity
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: identity),
                          const SizedBox(width: 24),
                          action,
                        ],
                      ),
                    const SizedBox(height: 16),
                    _Ai68PlanMetrics(plan: plan),
                    if (prices.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: prices
                            .map(
                              (entry) => _Ai68PlanPrice(
                                period: entry.key,
                                priceCents: entry.value,
                              ),
                            )
                            .toList(growable: false),
                      ),
                    ],
                    if (_parsePlanContent(plan.content).isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Divider(color: context.colorScheme.outlineVariant),
                      const SizedBox(height: 8),
                      _Ai68PlanDescription(
                        key: ValueKey('ai68-plan-description-${plan.id}'),
                        content: plan.content!,
                      ),
                    ],
                    if (isCompact) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Text(
                            lowest == null
                                ? '-'
                                : _formatMoney(context, lowest),
                            style: context.textTheme.titleLarge,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: state.isOrdering || lowest == null
                                  ? null
                                  : () => onBuy(plan),
                              icon: const Icon(Icons.shopping_cart_checkout),
                              label: Text(l10n.ai68Buy),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        );
      },
      separatorBuilder: (_, _) => const SizedBox(height: 10),
    );
  }
}

class _Ai68PlanMetrics extends StatelessWidget {
  const _Ai68PlanMetrics({required this.plan});

  final Ai68Plan plan;

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _Ai68PlanMetric(
          icon: Icons.data_usage,
          text: '${plan.transferEnableGb} GB',
        ),
        _Ai68PlanMetric(
          icon: Icons.speed,
          text: '${_formatPlanSpeed(plan.speedLimitMbps)} Mbps',
        ),
        _Ai68PlanMetric(
          icon: Icons.devices_outlined,
          text: '${plan.deviceLimit ?? '∞'} ${l10n.ai68DeviceLimit}',
        ),
      ],
    );
  }
}

class _Ai68PlanMetric extends StatelessWidget {
  const _Ai68PlanMetric({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: context.colorScheme.primary),
          const SizedBox(width: 7),
          Text(text, style: context.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _Ai68PlanTag extends StatelessWidget {
  const _Ai68PlanTag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: context.textTheme.labelMedium?.copyWith(
          color: context.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

class _Ai68PlanPrice extends StatelessWidget {
  const _Ai68PlanPrice({required this.period, required this.priceCents});

  final Ai68PlanPeriod period;
  final int priceCents;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        border: Border.all(color: context.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.sell_outlined,
            size: 17,
            color: context.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 7),
          Text(
            '${_periodText(context, period)} · ${_formatMoney(context, priceCents)}',
            style: context.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _Ai68PlanDescription extends StatelessWidget {
  const _Ai68PlanDescription({super.key, required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    final lines = _parsePlanContent(content);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines
          .map((line) {
            return switch (line.type) {
              _Ai68PlanContentType.heading => Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 8),
                child: Text(line.text, style: context.textTheme.titleSmall),
              ),
              _Ai68PlanContentType.item => Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.check_circle_outline,
                        size: 17,
                        color: context.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        line.text,
                        style: context.textTheme.bodyMedium?.copyWith(
                          color: context.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _Ai68PlanContentType.paragraph => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  line.text,
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            };
          })
          .toList(growable: false),
    );
  }
}

class _Ai68OrdersTab extends ConsumerWidget {
  const _Ai68OrdersTab({required this.state, required this.onPay});

  final Ai68CommercialState state;
  final ValueChanged<Ai68Order> onPay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.appLocalizations;
    if (state.orders.isEmpty) {
      return _Ai68EmptyState(icon: Icons.receipt_long, text: l10n.ai68NoOrders);
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: state.orders.length,
      itemBuilder: (context, index) {
        final order = state.orders[index];
        final pending = order.status == Ai68OrderStatus.pending;
        return CommonCard(
          child: ListItem(
            leading: Icon(_orderIcon(order.status)),
            title: Text(order.plan?.name ?? order.tradeNo),
            subtitle: Text(
              '${_formatMoney(context, order.totalAmountCents)} · ${_orderStatusText(context, order.status)}',
            ),
            trailing: pending
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: state.isOrdering ? null : () => onPay(order),
                        tooltip: l10n.ai68Pay,
                        icon: const Icon(Icons.payment),
                      ),
                      IconButton(
                        onPressed: state.isOrdering
                            ? null
                            : () {
                                ref
                                    .read(ai68CommercialProvider.notifier)
                                    .cancelOrder(order.tradeNo);
                              },
                        tooltip: l10n.ai68CancelOrder,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  )
                : Text(_formatEpoch(context, order.createdAt)),
          ),
        );
      },
      separatorBuilder: (_, _) => const SizedBox(height: 10),
    );
  }
}

class _Ai68NodesTab extends StatelessWidget {
  const _Ai68NodesTab({
    required this.state,
    required this.selectedRegion,
    required this.onRegionChanged,
  });

  final Ai68CommercialState state;
  final Ai68Region selectedRegion;
  final ValueChanged<Ai68Region> onRegionChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final servers = state.servers.where((server) {
      if (selectedRegion == Ai68Region.automatic) return true;
      return Ai68SmartConnectPolicy.matchesRegion(
        '${server.name} ${server.tags.join(' ')}',
        selectedRegion,
      );
    }).toList();
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: SegmentedButton<Ai68Region>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: Ai68Region.automatic,
                label: Text(l10n.ai68Automatic),
              ),
              ButtonSegment(
                value: Ai68Region.unitedStates,
                label: Text(l10n.ai68UnitedStates),
              ),
              ButtonSegment(
                value: Ai68Region.japan,
                label: Text(l10n.ai68Japan),
              ),
              ButtonSegment(
                value: Ai68Region.hongKong,
                label: Text(l10n.ai68HongKong),
              ),
            ],
            selected: {selectedRegion},
            onSelectionChanged: (regions) => onRegionChanged(regions.first),
          ),
        ),
        Expanded(
          child: servers.isEmpty
              ? _Ai68EmptyState(icon: Icons.public_off, text: l10n.ai68Nodes)
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: servers.length,
                  itemBuilder: (context, index) {
                    final server = servers[index];
                    return CommonCard(
                      child: ListItem(
                        leading: Icon(
                          Icons.circle,
                          size: 12,
                          color: server.isOnline
                              ? Colors.green
                              : context.colorScheme.outline,
                        ),
                        title: Text(server.name),
                        subtitle: Text(
                          '${server.type} · ${server.rate}x · ${server.tags.join(' ')}',
                        ),
                        trailing: Text(
                          server.isOnline ? l10n.ai68Online : l10n.ai68Offline,
                        ),
                      ),
                    );
                  },
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                ),
        ),
      ],
    );
  }
}

class _Ai68NoticesTab extends StatelessWidget {
  const _Ai68NoticesTab({required this.state});

  final Ai68CommercialState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    if (state.notices.isEmpty) {
      return _Ai68EmptyState(
        icon: Icons.notifications_none,
        text: l10n.ai68NoNotices,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: state.notices.length,
      itemBuilder: (context, index) {
        final notice = state.notices[index];
        return CommonCard(
          child: ExpansionTile(
            leading: const Icon(Icons.campaign_outlined),
            title: Text(notice.title),
            subtitle: Text(_formatEpoch(context, notice.createdAt)),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(_plainText(notice.content)),
                ),
              ),
            ],
          ),
        );
      },
      separatorBuilder: (_, _) => const SizedBox(height: 8),
    );
  }
}

class _Ai68SignedOutCenter extends StatelessWidget {
  const _Ai68SignedOutCenter({required this.onLogin});

  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    return CommonScaffold(
      title: l10n.ai68Center,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.account_circle_outlined, size: 64),
              const SizedBox(height: 18),
              Text(l10n.ai68WelcomeSubtitle),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onLogin,
                icon: const Icon(Icons.login),
                label: Text(l10n.ai68LoginAccount),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Ai68EmptyState extends StatelessWidget {
  const _Ai68EmptyState({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: context.colorScheme.outline),
          const SizedBox(height: 12),
          Text(text, style: context.textTheme.bodyLarge),
        ],
      ),
    );
  }
}

final class _Ai68OrderRequest {
  const _Ai68OrderRequest({required this.period, this.couponCode});

  final Ai68PlanPeriod period;
  final String? couponCode;
}

class _Ai68CreateOrderDialog extends StatefulWidget {
  const _Ai68CreateOrderDialog({required this.plan});

  final Ai68Plan plan;

  @override
  State<_Ai68CreateOrderDialog> createState() => _Ai68CreateOrderDialogState();
}

class _Ai68CreateOrderDialogState extends State<_Ai68CreateOrderDialog> {
  late final List<Ai68PlanPeriod> _periods;
  Ai68PlanPeriod? _period;
  final _couponController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _periods = widget.plan.pricesCents.entries
        .where((entry) => (entry.value ?? 0) > 0)
        .map((entry) => entry.key)
        .toList();
    _period = _periods.firstOrNull;
  }

  @override
  void dispose() {
    _couponController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final availableWidth = max(0.0, MediaQuery.sizeOf(context).width - 80);
    return AlertDialog(
      title: Text(widget.plan.name),
      content: SizedBox(
        width: min(520.0, availableWidth),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Ai68PlanMetrics(plan: widget.plan),
              if (_parsePlanContent(widget.plan.content).isNotEmpty) ...[
                const SizedBox(height: 16),
                _Ai68PlanDescription(content: widget.plan.content!),
              ],
              const SizedBox(height: 16),
              Divider(color: context.colorScheme.outlineVariant),
              const SizedBox(height: 12),
              DropdownButtonFormField<Ai68PlanPeriod>(
                initialValue: _period,
                decoration: InputDecoration(labelText: l10n.ai68Plan),
                items: _periods.map((period) {
                  final price = widget.plan.pricesCents[period] ?? 0;
                  return DropdownMenuItem(
                    value: period,
                    child: Text(
                      '${_periodText(context, period)} · ${_formatMoney(context, price)}',
                    ),
                  );
                }).toList(),
                onChanged: (period) {
                  if (period != null) {
                    setState(() => _period = period);
                  }
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _couponController,
                decoration: InputDecoration(
                  labelText: l10n.ai68CouponCode,
                  prefixIcon: const Icon(Icons.discount_outlined),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _period == null
              ? null
              : () {
                  final coupon = _couponController.text.trim();
                  Navigator.of(context).pop(
                    _Ai68OrderRequest(
                      period: _period!,
                      couponCode: coupon.isEmpty ? null : coupon,
                    ),
                  );
                },
          child: Text(l10n.ai68OrderCreated),
        ),
      ],
    );
  }
}

String _formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value >= 100 || unit == 0 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

String _formatMoney(BuildContext context, int cents, {String symbol = '¥'}) {
  final locale = Localizations.localeOf(context).toString();
  return NumberFormat.currency(
    locale: locale,
    symbol: symbol,
  ).format(cents / 100);
}

String _formatEpoch(BuildContext context, int? epoch) {
  if (epoch == null || epoch <= 0) {
    return context.appLocalizations.ai68Permanent;
  }
  final date = DateTime.fromMillisecondsSinceEpoch(epoch * 1000).toLocal();
  return DateFormat.yMMMd(
    Localizations.localeOf(context).toString(),
  ).add_Hm().format(date);
}

bool _expiresSoon(int? epoch) {
  if (epoch == null || epoch <= 0) {
    return false;
  }
  final expiry = DateTime.fromMillisecondsSinceEpoch(epoch * 1000);
  final remaining = expiry.difference(DateTime.now());
  return !remaining.isNegative && remaining <= const Duration(days: 7);
}

String _orderStatusText(BuildContext context, Ai68OrderStatus status) {
  final l10n = context.appLocalizations;
  return switch (status) {
    Ai68OrderStatus.pending ||
    Ai68OrderStatus.processing => l10n.ai68OrderPending,
    Ai68OrderStatus.completed ||
    Ai68OrderStatus.discounted => l10n.ai68OrderCompleted,
    Ai68OrderStatus.cancelled => l10n.ai68OrderCancelled,
    Ai68OrderStatus.unknown => '-',
  };
}

IconData _orderIcon(Ai68OrderStatus status) {
  return switch (status) {
    Ai68OrderStatus.pending || Ai68OrderStatus.processing => Icons.schedule,
    Ai68OrderStatus.completed ||
    Ai68OrderStatus.discounted => Icons.check_circle_outline,
    Ai68OrderStatus.cancelled => Icons.cancel_outlined,
    Ai68OrderStatus.unknown => Icons.help_outline,
  };
}

String _periodText(BuildContext context, Ai68PlanPeriod period) {
  final l10n = context.appLocalizations;
  return switch (period) {
    Ai68PlanPeriod.month => l10n.ai68Monthly,
    Ai68PlanPeriod.quarter => l10n.ai68Quarterly,
    Ai68PlanPeriod.halfYear => l10n.ai68HalfYear,
    Ai68PlanPeriod.year => l10n.ai68Yearly,
    Ai68PlanPeriod.twoYears || Ai68PlanPeriod.threeYears => l10n.ai68Yearly,
    Ai68PlanPeriod.onetime => l10n.ai68OneTime,
    Ai68PlanPeriod.resetTraffic => l10n.ai68ResetTraffic,
  };
}

String _formatPlanSpeed(double? speed) {
  if (speed == null) return '∞';
  return speed == speed.roundToDouble()
      ? speed.toInt().toString()
      : speed.toStringAsFixed(1);
}

enum _Ai68PlanContentType { heading, item, paragraph }

final class _Ai68PlanContentLine {
  const _Ai68PlanContentLine({required this.type, required this.text});

  final _Ai68PlanContentType type;
  final String text;
}

List<_Ai68PlanContentLine> _parsePlanContent(String? content) {
  if (content == null || content.trim().isEmpty) return const [];
  final normalized = content
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(?:p|div|li|h[1-6])>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '- ')
      .replaceAll(RegExp('<[^>]*>'), '');
  final lines = <_Ai68PlanContentLine>[];
  for (final rawLine in normalized.split(RegExp(r'\r?\n'))) {
    var line = _decodePlanText(rawLine.trim());
    if (line.isEmpty) continue;
    final heading = RegExp(r'^#{1,6}\s+').firstMatch(line);
    if (heading != null) {
      line = line.substring(heading.end).trim();
      if (line.isNotEmpty) {
        lines.add(
          _Ai68PlanContentLine(type: _Ai68PlanContentType.heading, text: line),
        );
      }
      continue;
    }
    final item = RegExp(r'^(?:[-*+]\s+|\d+[.)]\s+)').firstMatch(line);
    if (item != null) {
      line = line.substring(item.end).trim();
      if (line.isNotEmpty) {
        lines.add(
          _Ai68PlanContentLine(type: _Ai68PlanContentType.item, text: line),
        );
      }
      continue;
    }
    lines.add(
      _Ai68PlanContentLine(type: _Ai68PlanContentType.paragraph, text: line),
    );
  }
  return lines;
}

String _decodePlanText(String value) {
  return value
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll(RegExp(r'\*\*([^*]+)\*\*'), r'$1')
      .replaceAll(RegExp(r'__([^_]+)__'), r'$1')
      .replaceAll(RegExp(r'`([^`]+)`'), r'$1')
      .trim();
}

String _plainText(String value) {
  return value
      .replaceAll(RegExp('<[^>]*>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
