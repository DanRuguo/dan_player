/// Expected lookup outcomes, distinct from malformed responses and I/O errors.
class NoMatchingOnlineLyric implements Exception {
  const NoMatchingOnlineLyric();
  static const message = '联网无匹配歌词 (╥﹏╥)';
}

class InstrumentalLyric implements Exception {
  const InstrumentalLyric();
  static const message = '纯音乐，请欣赏';
}

String? lyricLookupStatus(Object? error) => switch (error) {
      NoMatchingOnlineLyric() => NoMatchingOnlineLyric.message,
      InstrumentalLyric() => InstrumentalLyric.message,
      _ => null,
    };
