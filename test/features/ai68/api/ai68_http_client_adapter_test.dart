import 'dart:io';

import 'package:fl_clash/features/ai68/api/ai68_http_client_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('strict client creation bypasses active HttpOverrides', () {
    var overrideCalls = 0;

    HttpOverrides.runZoned(
      () {
        final client = createAi68HttpClient();
        client.close(force: true);
      },
      createHttpClient: (_) {
        overrideCalls += 1;
        throw StateError('Global overrides must not create the AI68 client');
      },
    );

    expect(overrideCalls, 0);
  });
}
