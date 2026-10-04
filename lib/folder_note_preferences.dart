import 'package:path/path.dart' as path;

/// Display labels only. The path stays separate so relocation can update it
/// without interpreting the user's text as a file-system location.
class FolderNotePreferences {
  const FolderNotePreferences() : _notes = const {};
  FolderNotePreferences._(Map<String, ({String path, String text})> notes)
      : _notes = Map.unmodifiable(notes);

  static const maxCodePoints = 160;
  final Map<String, ({String path, String text})> _notes;

  factory FolderNotePreferences.fromJson(Object? value) {
    var result = const FolderNotePreferences();
    if (value is! List) return result;
    for (final item in value) {
      if (item is! Map || item['path'] is! String || item['text'] is! String) {
        continue;
      }
      try {
        result =
            result.withNote(item['path'] as String, item['text'] as String);
      } on FormatException {
        // A malformed record must not discard unrelated valid notes.
      }
    }
    return result;
  }

  static String _normalizedPath(String value) {
    if (!path.windows.isAbsolute(value) ||
        path.windows.isRootRelative(value) ||
        _hasControls(value)) {
      throw const FormatException('Folder note paths must be absolute');
    }
    return path.windows.normalize(value);
  }

  static String pathKey(String value) => _normalizedPath(value).toLowerCase();

  static bool _hasControls(String value) => value.runes.any((rune) =>
      rune < 0x20 ||
      (rune >= 0x7f && rune <= 0x9f) ||
      rune == 0x2028 ||
      rune == 0x2029);

  static bool isValidText(String value) =>
      value.runes.length <= maxCodePoints && !_hasControls(value);

  String? noteFor(String absolutePath) {
    try {
      return _notes[pathKey(absolutePath)]?.text;
    } on FormatException {
      return null;
    }
  }

  FolderNotePreferences withNote(String absolutePath, String text) {
    final normalized = _normalizedPath(absolutePath);
    if (!isValidText(text)) {
      throw const FormatException('Invalid folder note');
    }
    final notes = Map<String, ({String path, String text})>.of(_notes);
    final key = pathKey(normalized);
    if (text.trim().isEmpty) {
      notes.remove(key);
    } else {
      notes[key] = (path: normalized, text: text);
    }
    return FolderNotePreferences._(notes);
  }

  List<Map<String, String>> toJson() => [
        for (final note in _notes.values)
          {'path': note.path, 'text': note.text},
      ];
}
