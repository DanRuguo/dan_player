import 'package:dan_player/component/multi_selection_range.dart';
import 'package:flutter/foundation.dart';

/// Selection belongs to queue occurrences, including duplicate songs. Filtering
/// only changes the available range; it never silently drops hidden selections.
class QueueSelection extends ChangeNotifier {
  final Set<int> _selected = {};
  Set<int> get selected => Set.unmodifiable(_selected);
  bool enabled = false;
  int? _anchor;
  int revision = 0;

  void _changed() {
    revision++;
    notifyListeners();
  }

  void enter([int? occurrence]) {
    enabled = true;
    if (occurrence != null) {
      _selected.add(occurrence);
      _anchor = occurrence;
    }
    _changed();
  }

  void exit() {
    enabled = false;
    _selected.clear();
    _anchor = null;
    _changed();
  }

  void clear() {
    if (_selected.isEmpty && _anchor == null) return;
    _selected.clear();
    _anchor = null;
    _changed();
  }

  void retain(Iterable<int> occurrences) {
    final valid = occurrences.toSet();
    final oldLength = _selected.length;
    _selected.retainAll(valid);
    if (!valid.contains(_anchor)) _anchor = null;
    if (oldLength != _selected.length) _changed();
  }

  bool contains(int? occurrence) => _selected.contains(occurrence);

  List<int> ordered(Iterable<int> occurrences) =>
      occurrences.where(_selected.contains).toList(growable: false);

  void toggle(int occurrence, List<int> visible, {bool extend = false}) {
    if (!visible.contains(occurrence)) return;
    enabled = true;
    final from = extend ? visible.indexOf(_anchor ?? -1) : -1;
    if (from >= 0) {
      final to = visible.indexOf(occurrence);
      _selected.addAll(
          visible.sublist(from < to ? from : to, (from > to ? from : to) + 1));
    } else {
      if (!_selected.add(occurrence)) _selected.remove(occurrence);
      _anchor = occurrence;
    }
    _changed();
  }

  void toggleAll(List<int> visible) {
    if (visible.isEmpty) return;
    if (_selected.containsAll(visible)) {
      _selected.removeAll(visible);
    } else {
      _selected.addAll(visible);
    }
    _changed();
  }

  void invert(List<int> visible) {
    if (visible.isEmpty) return;
    for (final occurrence in visible) {
      if (!_selected.add(occurrence)) _selected.remove(occurrence);
    }
    _changed();
  }

  bool canSelectRange(List<int> visible, MultiSelectRange range) =>
      visibleSelectionRange(visible, _selected.contains, range).isNotEmpty;

  void selectRange(List<int> visible, MultiSelectRange range) {
    final additions = visibleSelectionRange(visible, _selected.contains, range);
    if (additions.isEmpty) return;
    _selected.addAll(additions);
    _changed();
  }
}
