import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/ai68/connect/ai68_smart_connect.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Ai68SmartConnectPolicy.matchesRegion', () {
    test('recognizes supported region aliases', () {
      expect(
        Ai68SmartConnectPolicy.matchesRegion(
          '🇺🇸 United States Premium',
          Ai68Region.unitedStates,
        ),
        isTrue,
      );
      expect(
        Ai68SmartConnectPolicy.matchesRegion('JP-Tokyo', Ai68Region.japan),
        isTrue,
      );
      expect(
        Ai68SmartConnectPolicy.matchesRegion('香港 01', Ai68Region.hongKong),
        isTrue,
      );
      expect(
        Ai68SmartConnectPolicy.matchesRegion('智能故障转移', Ai68Region.automatic),
        isTrue,
      );
    });

    test('does not confuse unsupported region names', () {
      expect(
        Ai68SmartConnectPolicy.matchesRegion('Singapore 01', Ai68Region.japan),
        isFalse,
      );
      expect(
        Ai68SmartConnectPolicy.matchesRegion(
          'Manual Select',
          Ai68Region.automatic,
        ),
        isFalse,
      );
    });
  });

  group('Ai68SmartConnectPolicy.strategySelection', () {
    test('selects a named automatic strategy through its parent selector', () {
      const groups = [
        Group(
          name: '智能选择',
          type: GroupType.URLTest,
          all: [
            Proxy(name: '日本 01', type: 'ss'),
            Proxy(name: '香港 01', type: 'ss'),
          ],
        ),
        Group(
          name: 'GLOBAL',
          type: GroupType.Selector,
          all: [
            Proxy(name: '智能选择', type: 'url-test'),
            Proxy(name: 'DIRECT', type: 'direct'),
          ],
        ),
      ];

      final selection = Ai68SmartConnectPolicy.strategySelection(
        groups,
        Ai68Region.automatic,
      );

      expect(selection, isNotNull);
      expect(selection!.groupName, 'GLOBAL');
      expect(selection.proxyName, '智能选择');
    });

    test('falls back to the first computed group for automatic mode', () {
      const groups = [
        Group(
          name: 'Latency Pool',
          type: GroupType.Fallback,
          all: [Proxy(name: 'Node 01', type: 'ss')],
        ),
        Group(
          name: 'Proxy',
          type: GroupType.Selector,
          all: [Proxy(name: 'Latency Pool', type: 'fallback')],
        ),
      ];

      final selection = Ai68SmartConnectPolicy.strategySelection(
        groups,
        Ai68Region.automatic,
      );

      expect(selection, isNotNull);
      expect(selection!.groupName, 'Proxy');
      expect(selection.proxyName, 'Latency Pool');
    });

    test('selects a regional strategy through its parent selector', () {
      const groups = [
        Group(
          name: 'JP-Auto',
          type: GroupType.URLTest,
          all: [Proxy(name: 'Tokyo 01', type: 'ss')],
        ),
        Group(
          name: 'Proxy',
          type: GroupType.Selector,
          all: [Proxy(name: 'JP-Auto', type: 'url-test')],
        ),
      ];

      final selection = Ai68SmartConnectPolicy.strategySelection(
        groups,
        Ai68Region.japan,
      );

      expect(selection, isNotNull);
      expect(selection!.groupName, 'Proxy');
      expect(selection.proxyName, 'JP-Auto');
    });

    test('leaves regional selectors for latency testing', () {
      const groups = [
        Group(
          name: 'Hong Kong',
          type: GroupType.Selector,
          all: [
            Proxy(name: 'HK 01', type: 'ss'),
            Proxy(name: 'HK 02', type: 'ss'),
          ],
        ),
      ];

      final selection = Ai68SmartConnectPolicy.strategySelection(
        groups,
        Ai68Region.hongKong,
      );

      expect(selection, isNull);
    });

    test('returns null when no requested regional group exists', () {
      const groups = [
        Group(
          name: 'Japan',
          type: GroupType.Selector,
          all: [Proxy(name: 'JP 01', type: 'ss')],
        ),
      ];

      expect(
        Ai68SmartConnectPolicy.strategySelection(
          groups,
          Ai68Region.unitedStates,
        ),
        isNull,
      );
    });
  });

  group('Ai68SmartConnectPolicy.fallbackSelector', () {
    test('prefers a non-empty selector matching the requested region', () {
      const groups = [
        Group(
          name: 'Proxy',
          type: GroupType.Selector,
          all: [Proxy(name: 'Any', type: 'ss')],
        ),
        Group(
          name: '美国节点',
          type: GroupType.Selector,
          all: [Proxy(name: 'US 01', type: 'ss')],
        ),
      ];

      final group = Ai68SmartConnectPolicy.fallbackSelector(
        groups,
        Ai68Region.unitedStates,
      );

      expect(group?.name, '美国节点');
    });

    test('falls back to the first usable selector in automatic mode', () {
      const groups = [
        Group(name: 'Empty', type: GroupType.Selector),
        Group(
          name: 'Proxy',
          type: GroupType.Selector,
          all: [Proxy(name: 'Any', type: 'ss')],
        ),
      ];

      final group = Ai68SmartConnectPolicy.fallbackSelector(
        groups,
        Ai68Region.automatic,
      );

      expect(group?.name, 'Proxy');
    });

    test('uses a generic selector containing regional nodes', () {
      const groups = [
        Group(
          name: 'Proxy',
          type: GroupType.Selector,
          all: [
            Proxy(name: 'JP Tokyo 01', type: 'ss'),
            Proxy(name: 'Hong Kong 01', type: 'ss'),
          ],
        ),
      ];

      final group = Ai68SmartConnectPolicy.fallbackSelector(
        groups,
        Ai68Region.japan,
      );

      expect(group?.name, 'Proxy');
    });
  });
}
