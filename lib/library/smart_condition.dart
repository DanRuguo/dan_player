import 'package:dan_player/library/personal_library.dart';

enum SmartField {
  ratingAtLeast,
  personalTag,
  addedAfter,
  addedBefore,
  playlist
}

enum RuleTruth { yes, no, unknown }

class SmartCondition {
  const SmartCondition.group(this.children, {this.any = false})
      : field = null,
        value = '',
        exclude = false;
  const SmartCondition.term(this.field, this.value, {this.exclude = false})
      : children = const [],
        any = false;
  final SmartField? field;
  final String value;
  final bool any, exclude;
  final List<SmartCondition> children;
  bool get isGroup => field == null;
  int get leaves => isGroup ? children.fold(0, (n, c) => n + c.leaves) : 1;
  Map<String, Object?> toJson() => isGroup
      ? {
          'group': any ? 'any' : 'all',
          'children': children.map((c) => c.toJson()).toList()
        }
      : {'field': field!.name, 'value': value, 'exclude': exclude};
  static SmartCondition fromJson(Object? raw, [int depth = 0]) {
    if (raw is! Map) throw const FormatException('Invalid condition');
    if (raw.containsKey('group')) {
      if (depth >= 2 ||
          !['any', 'all'].contains(raw['group']) ||
          raw['children'] is! List ||
          (raw['children'] as List).length > 32)
        throw const FormatException('Invalid condition group');
      final result = SmartCondition.group(
          (raw['children'] as List).map((c) => fromJson(c, depth + 1)).toList(),
          any: raw['group'] == 'any');
      if (result.leaves > 32)
        throw const FormatException('At most 32 conditions');
      return result;
    }
    final field =
        SmartField.values.where((f) => f.name == raw['field']).firstOrNull;
    final value = raw['value'];
    if (field == null ||
        value is! String ||
        value.trim().isEmpty ||
        value.length > 160 ||
        (raw['exclude'] != null && raw['exclude'] is! bool))
      throw const FormatException('Invalid condition value');
    if (field == SmartField.ratingAtLeast &&
        !['1', '2', '3', '4', '5'].contains(value))
      throw const FormatException('Invalid rating');
    if ((field == SmartField.addedAfter || field == SmartField.addedBefore) &&
        (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
            DateTime.tryParse(value) == null ||
            DateTime.parse(value).toIso8601String().substring(0, 10) != value))
      throw const FormatException('Use yyyy-mm-dd');
    return SmartCondition.term(field, value, exclude: raw['exclude'] == true);
  }

  RuleTruth evaluate(
      String track, PersonalTrack? data, Map<String, Set<String>> memberships) {
    if (isGroup) {
      final values =
          children.map((c) => c.evaluate(track, data, memberships)).toList();
      if (any && values.contains(RuleTruth.yes)) return RuleTruth.yes;
      if (!any && values.contains(RuleTruth.no)) return RuleTruth.no;
      if (values.contains(RuleTruth.unknown)) return RuleTruth.unknown;
      return any ? RuleTruth.no : RuleTruth.yes;
    }
    final bool? match = switch (field!) {
      SmartField.ratingAtLeast =>
        data?.rating == null ? null : data!.rating! >= int.parse(value),
      SmartField.personalTag => data?.tags.contains(value) ?? false,
      SmartField.addedAfter => data?.firstAddedAtUtc == null
          ? null
          : !data!.firstAddedAtUtc!.isBefore(DateTime.parse(value)),
      SmartField.addedBefore => data?.firstAddedAtUtc == null
          ? null
          : data!.firstAddedAtUtc!
              .isBefore(DateTime.parse(value).add(const Duration(days: 1))),
      SmartField.playlist => memberships[value]?.contains(track),
    };
    if (match == null) return RuleTruth.unknown;
    return match != exclude ? RuleTruth.yes : RuleTruth.no;
  }
}
