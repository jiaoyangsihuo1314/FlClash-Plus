import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const ai68SecureStorage = FlutterSecureStorage(
  mOptions: MacOsOptions(usesDataProtectionKeychain: false),
);
