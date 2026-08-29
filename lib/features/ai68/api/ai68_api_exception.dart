final class Ai68ApiException implements Exception {
  const Ai68ApiException({required this.message, this.statusCode, this.cause});

  final String message;
  final int? statusCode;
  final Object? cause;

  bool get isAuthenticationFailure => statusCode == 401 || statusCode == 403;

  String get displayMessage => ai68ChineseMessage(message);

  @override
  String toString() {
    final status = statusCode == null ? '' : ' ($statusCode)';
    return 'Ai68ApiException$status: $message';
  }
}

String ai68ChineseMessage(String message) {
  final value = message.trim();
  if (value.isEmpty) return '操作失败，请稍后重试';
  if (RegExp(r'[\u3400-\u9fff]').hasMatch(value)) return value;
  final normalized = value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  final exact = _ai68ChineseMessages[normalized];
  if (exact != null) return exact;
  if (normalized.contains('old password') &&
      (normalized.contains('wrong') || normalized.contains('incorrect'))) {
    return '旧密码错误';
  }
  if (normalized.contains('password') &&
      (normalized.contains('8') || normalized.contains('minimum'))) {
    return '新密码至少需要 8 个字符';
  }
  if ((normalized.contains('login') || normalized.contains('session')) &&
      (normalized.contains('expired') ||
          normalized.contains('unauthenticated') ||
          normalized.contains('unauthorized'))) {
    return '登录状态已过期，请重新登录';
  }
  if (normalized.contains('email') &&
      (normalized.contains('taken') || normalized.contains('exists'))) {
    return '该邮箱已注册';
  }
  if (normalized.contains('network') ||
      normalized.contains('timeout') ||
      normalized.contains('connection')) {
    return '网络连接失败，请稍后重试';
  }
  return '操作失败，请稍后重试';
}

const _ai68ChineseMessages = <String, String>{
  'the old password is wrong': '旧密码错误',
  'old password is wrong': '旧密码错误',
  'old password cannot be empty': '请输入旧密码',
  'new password cannot be empty': '请输入新密码',
  'password must be greater than 8 digits': '新密码至少需要 8 个字符',
  'save failed': '保存失败，请稍后重试',
  'login expired': '登录状态已过期，请重新登录',
  'session expired': '登录状态已过期，请重新登录',
  'unauthorized': '登录状态已过期，请重新登录',
  'unauthenticated.': '登录状态已过期，请重新登录',
  'email delivery failed': '邮件发送失败，请稍后重试',
  'the user does not exist': '用户不存在',
  'insufficient balance': '账户余额不足',
  'insufficient commission balance': '推广佣金余额不足',
  'too many attempts.': '操作过于频繁，请稍后重试',
  'network error': '网络连接失败，请稍后重试',
  'request failed': '请求失败，请稍后重试',
};
