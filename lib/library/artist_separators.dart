/// Settings describe literal delimiters, not regular expressions. Longest
/// matches win when a user adds both a short and a longer delimiter.
String artistSeparatorPattern(Iterable<Object?> separators) {
  final literals = separators
      .whereType<String>()
      .where((s) => s.isNotEmpty)
      .toSet()
      .toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  // An empty RegExp would split every character when the user removes all
  // delimiters. A never-matching expression deliberately keeps the full name.
  return literals.isEmpty ? r'(?!)' : literals.map(RegExp.escape).join('|');
}
