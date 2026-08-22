import 'dart:io';

import 'package:fl_clash/common/constant.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses the commercial brand without renaming native protocols', () {
    expect(appName, 'FlClash Plus');
    expect(packageName, 'com.follow.clash');
    expect(appHelperService, 'FlClashPlusHelperService');
    expect(helperPort, 47891);
    expect(coreName, 'clash.meta');
  });

  test('platform identities use FlClash Plus without breaking protocols', () {
    final androidBuild = File(
      'android/app/build.gradle.kts',
    ).readAsStringSync();
    final androidManifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final macAppInfo = File(
      'macos/Runner/Configs/AppInfo.xcconfig',
    ).readAsStringSync();
    final windowsCmake = File('windows/CMakeLists.txt').readAsStringSync();
    final helperWindows = File(
      'services/helper/src/service/windows.rs',
    ).readAsStringSync();
    final helperHub = File(
      'services/helper/src/service/hub.rs',
    ).readAsStringSync();
    final buildConfig = File(
      'plugins/setup/buildkit/build_tool/build_config.yaml',
    ).readAsStringSync();
    final buildOptions = File(
      'plugins/setup/buildkit/build_tool/lib/src/options.dart',
    ).readAsStringSync();
    final setupCmake = File(
      'plugins/setup/windows/CMakeLists.txt',
    ).readAsStringSync();
    final innoSetup = File(
      'windows/packaging/exe/inno_setup.iss',
    ).readAsStringSync();

    expect(androidBuild, contains('applicationId = "cn.ai68.flclashplus"'));
    expect(androidBuild, contains('namespace = "com.follow.clash"'));
    expect(androidManifest, contains('android:allowBackup="false"'));
    expect(androidManifest, contains('android:scheme="flclash"'));
    expect(androidManifest, contains('android:scheme="flclashplus"'));
    expect(macAppInfo, contains('PRODUCT_NAME = FlClash Plus'));
    expect(
      macAppInfo,
      contains('PRODUCT_BUNDLE_IDENTIFIER = cn.ai68.flclashplus'),
    );
    expect(windowsCmake, contains('set(BINARY_NAME "FlClashPlus")'));
    expect(
      helperWindows,
      contains('SERVICE_NAME: &str = "FlClashPlusHelperService"'),
    );
    expect(helperHub, contains('LISTEN_PORT: u16 = 47891'));
    expect(buildConfig, contains('helper_name: FlClashPlusHelperService'));
    expect(buildOptions, contains("helperName: 'FlClashPlusHelperService'"));
    expect(setupCmake, contains('FlClashPlusHelperService.exe'));
    expect(
      innoSetup,
      contains(
        "Processes := ['FlClashPlus.exe', 'FlClashPlusHelperService.exe']",
      ),
    );
    expect(innoSetup, contains('{app}\\\\FlClashPlusHelperService.exe'));
    expect(innoSetup, isNot(contains("'FlClashCore.exe'")));
  });
}
