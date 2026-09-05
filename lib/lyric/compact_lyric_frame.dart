import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_timeline.dart';
import 'package:dan_player/lyric/plain_lyric.dart';

enum CompactLyricStatus {
  idle,
  loading,
  unavailable,
  failed,
  upcoming,
  active,
  interlude,
  instrumental,
}

enum CompactLyricSecondary {
  none,
  information,
  translation,
  nextLine,
  firstLine
}

/// Text-only presentation state. Its identity excludes the playback position so
/// pauses, seeks within one line and normal progress ticks never replay a fade.
class CompactLyricFrame {
  const CompactLyricFrame({
    required this.status,
    required this.primary,
    this.secondary = '',
    this.secondaryKind = CompactLyricSecondary.none,
    this.lineIndex = -1,
  });

  final CompactLyricStatus status;
  final String primary;
  final String secondary;
  final CompactLyricSecondary secondaryKind;
  final int lineIndex;

  Object get identity => (status, lineIndex, primary, secondary, secondaryKind);

  String get secondaryLabel => switch (secondaryKind) {
        CompactLyricSecondary.translation => '译文',
        CompactLyricSecondary.nextLine => '下一句',
        CompactLyricSecondary.firstLine => '首句',
        _ => '',
      };

  String get displaySecondary => secondary.isEmpty
      ? ''
      : secondaryKind == CompactLyricSecondary.nextLine
          ? '下一句 · $secondary'
          : secondary;

  String get fullText => secondary.isEmpty
      ? primary
      : '$primary\n${secondaryLabel.isEmpty ? '' : '$secondaryLabel：'}$secondary';

  static const idle = CompactLyricFrame(
    status: CompactLyricStatus.idle,
    primary: '选择歌曲，开始聆听',
    secondary: '这里会显示当前歌词',
    secondaryKind: CompactLyricSecondary.information,
  );
  static const loading = CompactLyricFrame(
    status: CompactLyricStatus.loading,
    primary: '正在加载歌词…',
    secondary: '与完整播放器同步',
    secondaryKind: CompactLyricSecondary.information,
  );
  static const unavailable = CompactLyricFrame(
    status: CompactLyricStatus.unavailable,
    primary: '暂无歌词',
    secondary: '可在完整播放器选择歌词',
    secondaryKind: CompactLyricSecondary.information,
  );
  static const failed = CompactLyricFrame(
    status: CompactLyricStatus.failed,
    primary: '歌词加载失败',
    secondary: '请在完整播放器重试或切换来源',
    secondaryKind: CompactLyricSecondary.information,
  );
}

/// A read-only view of the already-resolved lyric. The existing parser has
/// applied local offsets; searching these same line timestamps applies no
/// additional offset and makes backward seeks deterministic.
class CompactLyricTimeline {
  CompactLyricTimeline(Lyric lyric)
      : _plainLyric = lyric is PlainLyric ? lyric : null,
        _lines = List.unmodifiable(lyric.lines),
        _parts = lyric.lines.map(_textOf).toList(growable: false) {
    _nextContent = List.filled(_parts.length, -1);
    var next = -1;
    for (var index = _parts.length - 1; index >= 0; index--) {
      _nextContent[index] = next;
      if (_parts[index].primary.isNotEmpty) next = index;
    }
    _firstContent = next;
    final nonEmpty = _parts.where((part) => part.primary.isNotEmpty);
    // Missing/empty lyrics are not proof of an instrumental track. Only an
    // explicit provider/editor marker with no sung lines gets that label.
    _instrumentalOnly = nonEmpty.isNotEmpty &&
        nonEmpty.every((part) => _isInstrumentalMarker(part.primary));
  }

  final List<LyricLine> _lines;
  final PlainLyric? _plainLyric;
  final List<({String primary, String translation})> _parts;
  late final List<int> _nextContent;
  late final int _firstContent;
  late final bool _instrumentalOnly;

  CompactLyricFrame at(Duration position) {
    if (_lines.isEmpty || _firstContent < 0) {
      return CompactLyricFrame.unavailable;
    }
    if (_instrumentalOnly) {
      return const CompactLyricFrame(
        status: CompactLyricStatus.instrumental,
        primary: '纯音乐，请欣赏',
      );
    }
    final plain = _plainLyric;
    if (plain != null) {
      return CompactLyricFrame(
        status: CompactLyricStatus.active,
        primary: plain.firstLine,
        secondary: '无时间轴歌词 · 完整内容请在歌词详情页查看',
        secondaryKind: CompactLyricSecondary.information,
        lineIndex: 0,
      );
    }
    if (position < _lines[_firstContent].start) {
      return CompactLyricFrame(
        status: CompactLyricStatus.upcoming,
        primary: '歌词即将开始',
        secondary: _parts[_firstContent].primary,
        secondaryKind: CompactLyricSecondary.firstLine,
      );
    }
    final index = findCurrentLyricLineIndex(_lines, position);
    final part = _parts[index];
    final next = _nextContent[index];
    if (part.primary.isEmpty || _isInstrumentalMarker(part.primary)) {
      return CompactLyricFrame(
        status: CompactLyricStatus.interlude,
        primary: '间奏 · 聆听音乐',
        secondary: next < 0 ? '' : _parts[next].primary,
        secondaryKind: next < 0
            ? CompactLyricSecondary.none
            : CompactLyricSecondary.nextLine,
        lineIndex: index,
      );
    }
    final translated = part.translation.isNotEmpty;
    return CompactLyricFrame(
      status: CompactLyricStatus.active,
      primary: part.primary,
      secondary: translated
          ? part.translation
          : next < 0
              ? ''
              : _parts[next].primary,
      secondaryKind: translated
          ? CompactLyricSecondary.translation
          : next < 0
              ? CompactLyricSecondary.none
              : CompactLyricSecondary.nextLine,
      lineIndex: index,
    );
  }
}

({String primary, String translation}) _textOf(LyricLine line) {
  if (line is SyncLyricLine) {
    return (
      primary: line.content.trim(),
      translation: line.translation?.trim() ?? '',
    );
  }
  if (line is UnsyncLyricLine) {
    // The shared LRC loader joins same-timestamp original/translated lines with
    // this separator. Do not invent word timing or split ordinary punctuation.
    final parts = line.content
        .split('┃')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    return (
      primary: parts.isEmpty ? '' : parts.first,
      translation: parts.skip(1).join(' · '),
    );
  }
  return (primary: '', translation: '');
}

bool _isInstrumentalMarker(String text) => const {
      '纯音乐',
      '纯音乐请欣赏',
      '纯音乐请您欣赏',
      '此歌曲为没有填词的纯音乐请您欣赏',
      'instrumental',
      'instrumentalversion',
      'instrumentaltrack',
    }.contains(
        text.replaceAll(RegExp(r'[\s，,。.!！\[\]()（）]'), '').toLowerCase());
