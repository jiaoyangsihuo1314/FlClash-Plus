import 'package:fl_clash/common/navigation.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AI68 center is the first mobile and desktop navigation item', () {
    final ai68Item = navigation.getItems().first;

    expect(ai68Item.label, PageLabel.ai68Center);
    expect(
      ai68Item.modes,
      containsAll([NavigationItemMode.mobile, NavigationItemMode.desktop]),
    );
  });
}
