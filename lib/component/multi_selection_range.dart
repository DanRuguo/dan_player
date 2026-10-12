/// Deliberate range operations follow the caller's displayed, filtered order.
enum MultiSelectRange { between, above, below }

/// Identity is supplied by the caller: playlist occurrences use entry IDs,
/// while ordinary library pages use their current metadata objects.
List<T> visibleSelectionRange<T>(Iterable<T> orderedVisible,
    bool Function(T) isSelected, MultiSelectRange range) {
  final visible = orderedVisible.toList(growable: false);
  final endpoints = <int>[
    for (var index = 0; index < visible.length; index++)
      if (isSelected(visible[index])) index,
  ];
  if (range == MultiSelectRange.between) {
    if (endpoints.length != 2 || endpoints.last - endpoints.first < 2) {
      return <T>[];
    }
    return visible.sublist(endpoints.first, endpoints.last + 1);
  }
  if (endpoints.length != 1) return <T>[];
  final at = endpoints.single;
  return switch (range) {
    MultiSelectRange.above => at == 0 ? <T>[] : visible.sublist(0, at + 1),
    MultiSelectRange.below =>
      at == visible.length - 1 ? <T>[] : visible.sublist(at),
    MultiSelectRange.between => <T>[],
  };
}
