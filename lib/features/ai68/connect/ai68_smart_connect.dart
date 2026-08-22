import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';

enum Ai68Region { automatic, unitedStates, japan, hongKong }

final class Ai68ProxySelection {
  const Ai68ProxySelection({required this.groupName, required this.proxyName});

  final String groupName;
  final String proxyName;
}

final class Ai68SmartConnectPolicy {
  const Ai68SmartConnectPolicy._();

  static Ai68ProxySelection? strategySelection(
    List<Group> groups,
    Ai68Region region,
  ) {
    final target = strategyGroup(groups, region);
    if (target == null) return null;
    for (final group in groups) {
      if (group.type != GroupType.Selector) continue;
      if (group.all.any((proxy) => proxy.name == target.name)) {
        return Ai68ProxySelection(
          groupName: group.name,
          proxyName: target.name,
        );
      }
    }
    return null;
  }

  static Group? strategyGroup(List<Group> groups, Ai68Region region) {
    for (final group in groups) {
      if (!group.type.isComputedSelected ||
          !matchesRegion(group.name, region)) {
        continue;
      }
      return group;
    }
    if (region != Ai68Region.automatic) return null;
    for (final group in groups) {
      if (group.type.isComputedSelected) return group;
    }
    return null;
  }

  static Group? fallbackSelector(List<Group> groups, Ai68Region region) {
    for (final group in groups) {
      if (group.type != GroupType.Selector || group.all.isEmpty) continue;
      if (region == Ai68Region.automatic ||
          matchesRegion(group.name, region) ||
          group.all.any((proxy) => matchesRegion(proxy.name, region))) {
        return group;
      }
    }
    if (region != Ai68Region.automatic) return null;
    return groups.cast<Group?>().firstWhere(
      (group) => group?.type == GroupType.Selector && group!.all.isNotEmpty,
      orElse: () => null,
    );
  }

  static bool matchesRegion(String value, Ai68Region region) {
    final normalized = value.toLowerCase();
    return switch (region) {
      Ai68Region.automatic => _containsAny(normalized, const [
        'auto',
        'smart',
        '自动',
        '智能',
        '故障转移',
        'fallback',
      ]),
      Ai68Region.unitedStates => _containsAny(normalized, const [
        'united states',
        'america',
        'usa',
        '美国',
        '美國',
        'us-',
        'us ',
        '🇺🇸',
      ]),
      Ai68Region.japan => _containsAny(normalized, const [
        'japan',
        '日本',
        'jp-',
        'jp ',
        '🇯🇵',
      ]),
      Ai68Region.hongKong => _containsAny(normalized, const [
        'hong kong',
        'hongkong',
        '香港',
        'hk-',
        'hk ',
        '🇭🇰',
      ]),
    };
  }

  static bool _containsAny(String value, List<String> terms) {
    return terms.any(value.contains);
  }
}
