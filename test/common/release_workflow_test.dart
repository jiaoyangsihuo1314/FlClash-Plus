import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final workflow = File(
    '.github/workflows/flclash-plus-release.yaml',
  ).readAsStringSync();

  test('tagged releases fail closed and verify all platform trust chains', () {
    expect(
      workflow,
      contains('Tagged releases require all Android signing secrets.'),
    );
    expect(
      workflow,
      contains('Tagged releases require the Windows certificate and password.'),
    );
    expect(
      workflow,
      contains(
        'Tagged releases require macOS signing and Apple notarization credentials.',
      ),
    );
    expect(workflow, contains('notarytool submit'));
    expect(workflow, contains('stapler validate'));
    expect(workflow, contains('Get-AuthenticodeSignature'));
    expect(workflow, contains('apksigner" verify'));
  });

  test('Windows signing preserves the Mihomo Core integrity contract', () {
    expect(workflow, contains("\$_.Name -ne 'FlClashCore.exe'"));
    expect(
      workflow,
      contains('Windows Core SHA256 no longer matches the bundled manifest.'),
    );
    final installer = File(
      'windows/packaging/exe/flclash_plus_ci.iss',
    ).readAsStringSync();
    final processLine = installer
        .split('\n')
        .singleWhere((line) => line.contains('Processes :='));
    expect(processLine, isNot(contains('FlClashCore.exe')));
  });

  test('release actions are pinned to immutable commit SHAs', () {
    final usesLines = workflow
        .split('\n')
        .where((line) => line.trimLeft().startsWith('uses:'));
    expect(usesLines, isNotEmpty);
    for (final line in usesLines) {
      expect(
        line,
        matches(RegExp(r'^\s*uses:\s+[^@\s]+@[0-9a-f]{40}(?:\s+#.*)?$')),
        reason: line,
      );
    }
  });

  test('release tags must match pubspec and declare payment domains', () {
    expect(workflow, contains('does not match pubspec version'));
    expect(
      workflow,
      contains(
        'AI68_PAYMENT_HOSTS must list the production payment domains for tagged releases.',
      ),
    );
  });
}
