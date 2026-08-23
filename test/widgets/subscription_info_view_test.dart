import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/widgets/subscription_info_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows used, remaining, total traffic and expiry', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _TestApp(
        subscriptionInfo: SubscriptionInfo(
          upload: 200,
          download: 300,
          total: 1000,
          expire: 1800000000,
        ),
      ),
    );

    expect(find.textContaining('Used:'), findsOneWidget);
    expect(find.textContaining('Remaining / Total:'), findsOneWidget);
    expect(find.textContaining('Expires:'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0.5,
    );
    expect(tester.takeException(), null);
  });

  testWidgets('clamps overused traffic to a complete progress bar', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _TestApp(
        subscriptionInfo: SubscriptionInfo(
          upload: 800,
          download: 700,
          total: 1000,
        ),
      ),
    );

    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      1,
    );
    expect(find.textContaining('0B / 1000B'), findsOneWidget);
    expect(tester.takeException(), null);
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.subscriptionInfo});

  final SubscriptionInfo subscriptionInfo;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.delegate.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 320,
          child: SubscriptionInfoView(subscriptionInfo: subscriptionInfo),
        ),
      ),
    );
  }
}
