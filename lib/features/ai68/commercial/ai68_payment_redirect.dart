import 'package:fl_clash/features/ai68/api/ai68_api_exception.dart';

const ai68PaymentHosts = String.fromEnvironment('AI68_PAYMENT_HOSTS');

Uri validateAi68PaymentRedirect(
  Uri? uri, {
  String configuredHosts = ai68PaymentHosts,
}) {
  if (uri == null ||
      !uri.isAbsolute ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.port != 443 ||
      !_isAllowedPaymentHost(uri.host, configuredHosts)) {
    throw const Ai68ApiException(message: 'AI68 返回了不安全的支付地址');
  }
  return uri;
}

bool _isAllowedPaymentHost(String host, String configuredHosts) {
  final normalizedHost = host.toLowerCase();
  const ai68Domain = 'ai68ai.cn';
  if (_matchesDomain(normalizedHost, ai68Domain)) return true;
  final allowedDomains = configuredHosts
      .split(',')
      .map((value) => value.trim().toLowerCase())
      .where(_isValidConfiguredDomain);
  return allowedDomains.any((domain) => _matchesDomain(normalizedHost, domain));
}

bool _matchesDomain(String host, String domain) {
  return host == domain || host.endsWith('.$domain');
}

bool _isValidConfiguredDomain(String value) {
  if (value.isEmpty ||
      value.startsWith('.') ||
      value.endsWith('.') ||
      value.contains('/') ||
      value.contains(':')) {
    return false;
  }
  return RegExp(r'^[a-z0-9-]+(?:\.[a-z0-9-]+)+$').hasMatch(value);
}
