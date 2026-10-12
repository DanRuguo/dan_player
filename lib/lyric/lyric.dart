import 'package:desktop_lyric/lyric_ruby.dart';

abstract class Lyric {
  List<LyricLine> lines;

  Lyric(this.lines);
}

abstract class LyricLine {
  Duration start;
  String? romanization;

  /// Display-only offline reading. Source/cache/document serialization omits it.
  String? japaneseReading;
  List<JapaneseLyricReadingSpan> japaneseReadingSpans = const [];

  LyricLine(this.start);
}

/// A derived reading above a complete source-text range (UTF-16, half open).
class JapaneseLyricReadingSpan implements LyricRubySpan {
  const JapaneseLyricReadingSpan(
      {required this.start, required this.end, required this.text});
  @override
  final int start;
  @override
  final int end;
  @override
  final String text;
}

abstract class UnsyncLyricLine extends LyricLine {
  String content;

  UnsyncLyricLine(super.start, this.content);
}

abstract class SyncLyricLine extends LyricLine {
  Duration length;
  List<SyncLyricWord> words;
  late String content;
  String? translation;

  SyncLyricLine(super.start, this.length, this.words, [this.translation]) {
    final buffer = StringBuffer();
    for (final e in words) {
      buffer.write(e.content);
    }
    content = buffer.toString();
  }

  @override
  String toString() {
    return "[${start.inMilliseconds},${length.inMilliseconds}]$content";
  }
}

abstract class SyncLyricWord {
  Duration start;
  Duration length;
  String content;

  SyncLyricWord(this.start, this.length, this.content);

  @override
  String toString() {
    return "(${start.inMilliseconds},${length.inMilliseconds})$content";
  }
}

/// Timestamp-only/whitespace payloads are not usable lyrics or cache hits.
bool hasLyricContent(Lyric lyric) => lyric.lines.any((line) => switch (line) {
      UnsyncLyricLine() => line.content.trim().isNotEmpty,
      SyncLyricLine() => line.content.trim().isNotEmpty ||
          (line.translation?.trim().isNotEmpty ?? false),
      _ => false,
    });
