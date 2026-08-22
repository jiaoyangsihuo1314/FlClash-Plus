import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _ai68MacOsTestStorage = bool.fromEnvironment(
  'AI68_MACOS_TEST_STORAGE',
);

bool get useAi68MacOsTestStorage {
  return _ai68MacOsTestStorage &&
      defaultTargetPlatform == TargetPlatform.macOS;
}

const ai68SecureStorage = FlutterSecureStorage(
  mOptions: MacOsOptions(usesDataProtectionKeychain: false),
);
