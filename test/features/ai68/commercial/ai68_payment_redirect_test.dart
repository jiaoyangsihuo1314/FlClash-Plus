import 'package:fl_clash/features/ai68/api/ai68_api_exception.dart';
import 'package:fl_clash/features/ai68/commercial/ai68_payment_redirect.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('allows AI68 and configured payment domains', () {
    expect(
      validateAi68PaymentRedirect(
        Uri.parse('https://pay.ai68ai.cn/checkout'),
      ).host,
      'pay.ai68ai.cn',
    );
    expect(
      validateAi68PaymentRedirect(
        Uri.parse('https://checkout.stripe.com/pay/session'),
        configuredHosts: 'stripe.com,paypal.com',
      ).host,
      'checkout.stripe.com',
    );
  });

  test('rejects spoofed or unapproved payment authorities', () {
    final invalid = <Uri>[
      Uri.parse('http://pay.ai68ai.cn/checkout'),
      Uri.parse('https://mingjie-panel.ai68ai.cn@evil.example/checkout'),
      Uri.parse('https://pay.ai68ai.cn:8443/checkout'),
      Uri.parse('https://evil.example/checkout'),
    ];

    for (final uri in invalid) {
      expect(
        () => validateAi68PaymentRedirect(uri),
        throwsA(isA<Ai68ApiException>()),
        reason: uri.toString(),
      );
    }
  });

  test('rejects malformed configured payment domains', () {
    expect(
      () => validateAi68PaymentRedirect(
        Uri.parse('https://checkout.stripe.com/pay/session'),
        configuredHosts: 'https://stripe.com,.stripe.com,stripe.com:443',
      ),
      throwsA(isA<Ai68ApiException>()),
    );
  });
}
