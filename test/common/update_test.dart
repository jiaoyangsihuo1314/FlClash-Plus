import 'package:fl_clash/common/request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selects the newest stable Plus release only', () {
    final release = selectLatestPlusRelease(<Object?>[
      <String, dynamic>{
        'tag_name': 'v99.0.0',
        'html_url': 'https://github.com/ai68/flclash-plus/releases/tag/v99',
      },
      <String, dynamic>{
        'tag_name': 'plus-v1.2.0-beta',
        'html_url': 'https://github.com/ai68/flclash-plus/releases/tag/beta',
      },
      <String, dynamic>{
        'tag_name': 'plus-v1.1.0',
        'html_url': 'https://github.com/ai68/flclash-plus/releases/tag/1.1.0',
      },
      <String, dynamic>{
        'tag_name': 'plus-v1.3.0',
        'prerelease': true,
        'html_url': 'https://github.com/ai68/flclash-plus/releases/tag/1.3.0',
      },
      <String, dynamic>{
        'tag_name': 'plus-v1.2.0',
        'html_url': 'https://github.com/ai68/flclash-plus/releases/tag/1.2.0',
      },
    ], currentVersion: '1.0.0+2026082201');

    expect(release?['tag_name'], 'plus-v1.2.0');
  });

  test('ignores malformed, draft, and non-newer Plus releases', () {
    final release = selectLatestPlusRelease(<Object?>[
      <String, dynamic>{'tag_name': 'plus-vnext'},
      <String, dynamic>{'tag_name': 'plus-v1.0.0'},
      <String, dynamic>{'tag_name': 'plus-v1.1.0', 'draft': true},
      <String, dynamic>{'tag_name': 123},
    ], currentVersion: '1.0.0+2026082201');

    expect(release, isNull);
  });
}
