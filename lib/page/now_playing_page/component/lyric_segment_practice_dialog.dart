import 'dart:math' as math;

import 'package:dan_player/component/app_dialog_resize.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_text_search.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/play_service/lyric_line_practice.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'lyric_reading_tools.dart';
import 'lyric_reading_result_list.dart';

Future<bool?> showLyricSegmentPracticeDialog(
  BuildContext context, {
  required PlaybackService playback,
  required Lyric lyric,
  required int playbackSession,
  required bool Function() isCurrentLyric,
  required String songTitle,
  Listenable? lyricChanges,
  Duration initialPosition = Duration.zero,
}) =>
    showAppDialog<bool>(
      context: context,
      builder: (_) => LyricSegmentPracticeDialog(
        playback: playback,
        lyric: lyric,
        playbackSession: playbackSession,
        isCurrentLyric: isCurrentLyric,
        songTitle: songTitle,
        lyricChanges: lyricChanges,
        initialPosition: initialPosition,
      ),
    );

class LyricSegmentPracticeDialog extends StatefulWidget {
  const LyricSegmentPracticeDialog({
    super.key,
    required this.playback,
    required this.lyric,
    required this.playbackSession,
    required this.isCurrentLyric,
    required this.songTitle,
    this.lyricChanges,
    this.initialPosition = Duration.zero,
  });
  final PlaybackService playback;
  final Lyric lyric;
  final int playbackSession;
  final bool Function() isCurrentLyric;
  final String songTitle;
  final Listenable? lyricChanges;
  final Duration initialPosition;

  @override
  State<LyricSegmentPracticeDialog> createState() =>
      _LyricSegmentPracticeDialogState();
}

class _LyricSegmentPracticeDialogState
    extends State<LyricSegmentPracticeDialog> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  late final List<LyricSearchRow> _rows;
  late final Listenable _changes;
  int? _first, _last;
  bool _choosingStart = true;
  String? _error;

  bool get _current =>
      widget.playback.playbackSessionToken == widget.playbackSession &&
      widget.isCurrentLyric();
  int? get _from =>
      _first == null || _last == null ? null : math.min(_first!, _last!);
  int? get _to =>
      _first == null || _last == null ? null : math.max(_first!, _last!);

  LyricPracticeRange? get _range {
    final from = _from, to = _to;
    if (from == null || to == null) return null;
    return lyricSegmentPracticeRange(widget.lyric, widget.lyric.lines[from],
        widget.lyric.lines[to], widget.playback.length);
  }

  @override
  void initState() {
    super.initState();
    _changes = Listenable.merge([
      widget.playback,
      widget.playback.resolvingAudioPath,
      widget.playback.isChangingOutput,
      widget.lyricChanges,
    ]);
    _rows = widget.lyric is PlainLyric
        ? []
        : lyricSearchRows(widget.lyric,
            project: lyricReadingText, includeLine: isTimedLyricPracticeLine);
    if (_rows.isNotEmpty) {
      var initial = _rows.first;
      for (final row in _rows) {
        if (row.line.start <= widget.initialPosition &&
            row.line.start >= initial.line.start) {
          initial = row;
        }
      }
      _first = _last = initial.index;
    }
  }

  void _choose(LyricSearchRow row) {
    setState(() {
      if (_choosingStart) {
        _first = row.index;
        _last = row.index;
        _choosingStart = false;
      } else {
        _last = row.index;
      }
      _error = null;
    });
  }

  void _apply() {
    final from = _from, to = _to;
    if (from == null || to == null) return;
    final result = practiceLyricSegment(
      playback: widget.playback,
      lyric: widget.lyric,
      first: widget.lyric.lines[from],
      last: widget.lyric.lines[to],
      playbackSession: widget.playbackSession,
      isCurrentLyric: widget.isCurrentLyric,
    );
    if (result == LyricPracticeResult.applied) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _error = switch (result) {
        LyricPracticeResult.stale => '歌曲或歌词已改变，请重新选择练习片段',
        LyricPracticeResult.unavailable => '请先加载一首本地歌曲，再设置片段循环。',
        _ => '所选歌词没有至少 1 秒的有效时间范围',
      };
    });
  }

  static String _time(double seconds) =>
      Duration(microseconds: (seconds * Duration.microsecondsPerSecond).round())
          .toString()
          .split('.')
          .first;

  Widget _endpoint(bool start) {
    final selected = start == _choosingStart;
    return Semantics(
      selected: selected,
      container: true,
      child: OutlinedButton(
        key: ValueKey(start ? 'lyric-segment-start' : 'lyric-segment-end'),
        style: appToolbarControlStyle(context).copyWith(
          fixedSize: const WidgetStatePropertyAll<Size?>(null),
          backgroundColor: selected
              ? WidgetStatePropertyAll(
                  Theme.of(context).colorScheme.secondaryContainer)
              : null,
        ),
        onPressed: () => setState(() => _choosingStart = start),
        child: Text(ui(start ? '起始句' : '结束句'), textAlign: TextAlign.center),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return ListenableBuilder(
      listenable: _changes,
      builder: (context, _) {
        final current = _current;
        final available = current && widget.playback.canUseSegmentLoop;
        final range = _range;
        final from = _from, to = _to;
        final visible = filterLyricSearchRows(_rows, _search.text);
        final count = from == null || to == null
            ? 0
            : _rows.where((row) => row.index >= from && row.index <= to).length;
        final scheme = Theme.of(context).colorScheme;
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyF, control: true):
                _searchFocus.requestFocus,
          },
          child: Focus(
            autofocus: true,
            child: AlertDialog(
              scrollable: true,
              icon: Icon(Symbols.repeat, color: scheme.primary),
              title: AppDialogTitle(ui('歌词片段练习')),
              content: AppDialogResize(
                  child: SizedBox(
                width: 560,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(widget.songTitle,
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Text(ui('选择首尾两句，连续练习中间的歌词；查找不会改变片段范围。')),
                    const SizedBox(height: 12),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _endpoint(true)),
                          const SizedBox(width: 8),
                          Expanded(child: _endpoint(false)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('lyric-segment-search'),
                      controller: _search,
                      focusNode: _searchFocus,
                      decoration: InputDecoration(
                        labelText: ui('查找'),
                        helperText: ui('搜索原文、译文或注音'),
                        helperMaxLines: 8,
                        prefixIcon: const Icon(Symbols.search),
                        border: const OutlineInputBorder(
                            borderRadius:
                                BorderRadius.all(Radius.circular(16))),
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: ui('清除'),
                                onPressed: () => setState(_search.clear),
                                icon: const Icon(Symbols.close),
                              ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: (MediaQuery.sizeOf(context).height * .32)
                          .clamp(120, 260),
                      child: visible.isEmpty
                          ? Center(
                              child: Text(ui(_rows.isEmpty
                                  ? '没有可选择的带时间歌词'
                                  : '当前歌词中没有匹配内容')),
                            )
                          : LyricReadingResultList(
                              scrollViewKey:
                                  const ValueKey('lyric-segment-lines'),
                              resetToken: _search.text,
                              itemCount: visible.length,
                              itemBuilder: (context, index) {
                                final row = visible[index];
                                final selected = from != null &&
                                    to != null &&
                                    row.index >= from &&
                                    row.index <= to;
                                final endpoint =
                                    row.index == from || row.index == to;
                                return LyricReadingResultRow(
                                  tileKey: ValueKey(
                                      'lyric-segment-line-${row.index}'),
                                  selected: selected,
                                  icon: endpoint
                                      ? Symbols.radio_button_checked
                                      : selected
                                          ? Symbols.check
                                          : Symbols.radio_button_unchecked,
                                  text: row.text,
                                  timestamp: _time(
                                      row.line.start.inMicroseconds /
                                          Duration.microsecondsPerSecond),
                                  onTap: available ? () => _choose(row) : null,
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      ui(
                          range == null
                              ? '所选歌词没有至少 1 秒的有效时间范围'
                              : '练习范围：{0} — {1} · {2} 句',
                          range == null
                              ? const []
                              : [_time(range.start), _time(range.end), count]),
                      key: const ValueKey('lyric-segment-range'),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(ui('沿用 A-B 次数与间隔；可在 A-B 设置中调整，并将区间保存为书签。暂停时不会自动播放。')),
                    if (!current || !available || _error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        ui(!current
                            ? '歌曲或歌词已改变，请重新选择练习片段'
                            : !available
                                ? '请先加载一首本地歌曲，再设置片段循环。'
                                : _error!),
                        style: TextStyle(color: scheme.error),
                      ),
                    ],
                  ],
                ),
              )),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(ui('取消')),
                ),
                FilledButton(
                  key: const ValueKey('lyric-segment-apply'),
                  onPressed: available && range != null ? _apply : null,
                  child: Text(ui('启动片段循环')),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }
}
