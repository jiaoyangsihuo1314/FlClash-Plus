import 'package:fl_clash/features/ai68/api/ai68_api_exception.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('translates known Xboard English errors into Chinese', () {
    expect(
      const Ai68ApiException(
        message: 'The old password is wrong',
      ).displayMessage,
      '旧密码错误',
    );
    expect(
      const Ai68ApiException(message: 'Login expired').displayMessage,
      '登录状态已过期，请重新登录',
    );
  });

  test('keeps Chinese errors and hides unknown English errors', () {
    expect(const Ai68ApiException(message: '账户余额不足').displayMessage, '账户余额不足');
    expect(
      const Ai68ApiException(
        message: 'Unexpected upstream failure',
      ).displayMessage,
      '操作失败，请稍后重试',
    );
  });
}
