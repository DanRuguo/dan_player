import 'package:dan_player/component/app_dialog_resize.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_text_search.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'lyric_reading_tools.dart';
import 'lyric_reading_result_list.dart';

Future<LyricReadingTarget?> showLyricFindDialog(BuildContext context,
        {required Lyric lyric,
        required bool Function() isCurrentLyric,
        required String songTitle,
        Listenable? lyricChanges}) =>
    showAppDialog<LyricReadingTarget>(
        context: context,
        builder: (_) => LyricFindDialog(
            lyric: lyric,
            isCurrentLyric: isCurrentLyric,
            songTitle: songTitle,
            lyricChanges: lyricChanges));

class LyricFindDialog extends StatefulWidget {
  const LyricFindDialog(
      {super.key,
      required this.lyric,
      required this.isCurrentLyric,
      required this.songTitle,
      this.lyricChanges});
  final Lyric lyric;
  final bool Function() isCurrentLyric;
  final String songTitle;
  final Listenable? lyricChanges;

  @override
  State<LyricFindDialog> createState() => _LyricFindDialogState();
}

class _LyricFindDialogState extends State<LyricFindDialog> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _list = ScrollController();
  final _results = GlobalKey<LyricReadingResultListState>();
  late final List<LyricSearchRow> _rows;
  late List<LyricSearchRow> _visible;
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    _rows = lyricSearchRows(widget.lyric, project: lyricReadingText);
    _visible = _rows;
  }

  void _filter() => setState(() {
        _visible = filterLyricSearchRows(_rows, _search.text);
        _selected = 0;
        if (_list.hasClients) _list.jumpTo(0);
      });

  void _move(int direction) {
    if (_visible.isEmpty || !widget.isCurrentLyric()) return;
    setState(() => _selected = (_selected + direction) % _visible.length);
    _results.currentState?.revealIndex(_selected);
  }

  void _apply() {
    if (_visible.isEmpty || !widget.isCurrentLyric()) return;
    final target = _visible[_selected].target;
    if (target.belongsTo(widget.lyric)) Navigator.of(context).pop(target);
  }

  Widget _step(bool previous, bool current) => OutlinedButton(
      key: ValueKey(previous ? 'lyric-find-previous' : 'lyric-find-next'),
      style: appToolbarControlStyle(context)
          .copyWith(fixedSize: const WidgetStatePropertyAll<Size?>(null)),
      onPressed: current && _visible.isNotEmpty
          ? () => _move(previous ? -1 : 1)
          : null,
      child: AppToolbarLabel(
          labelKey: ValueKey(
              previous ? 'lyric-find-previous-label' : 'lyric-find-next-label'),
          icon: previous
              ? Symbols.keyboard_arrow_up
              : Symbols.keyboard_arrow_down,
          label: ui(previous ? '上一个匹配' : '下一个匹配')));

  Widget _steps(bool current, double contentWidth) {
    var neededWidth = 0.0;
    for (final key in ['上一个匹配', '下一个匹配']) {
      final painter = TextPainter(
          text: TextSpan(
              text: ui(key), style: Theme.of(context).textTheme.labelLarge),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context))
        ..layout();
      final width = painter.width +
          appToolbarIconSize +
          appToolbarLabelGap +
          appToolbarPadding.horizontal;
      if (width > neededWidth) neededWidth = width;
      painter.dispose();
    }
    if ((contentWidth - 8) / 2 < neededWidth) {
      return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _step(true, current),
            const SizedBox(height: 8),
            _step(false, current)
          ]);
    }
    return IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(child: _step(true, current)),
      const SizedBox(width: 8),
      Expanded(child: _step(false, current))
    ]));
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return LayoutBuilder(builder: (context, constraints) {
      final insets = DialogTheme.of(context).insetPadding ??
          const EdgeInsets.symmetric(horizontal: 40, vertical: 24);
      // Measure above AlertDialog's intrinsic-size boundary, as in the track
      // settings dialog. Its content must not contain a LayoutBuilder.
      final contentWidth = (constraints.maxWidth -
              insets.horizontal -
              MediaQuery.viewInsetsOf(context).horizontal -
              48)
          .clamp(0.0, 560.0);
      return _dialog(context, contentWidth);
    });
  }

  Widget _dialog(BuildContext context, double contentWidth) {
    return ListenableBuilder(
        listenable: widget.lyricChanges ?? const _NoChanges(),
        builder: (context, _) {
          final current = widget.isCurrentLyric();
          final scheme = Theme.of(context).colorScheme;
          return CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.keyF, control: true):
                    _searchFocus.requestFocus,
                const SingleActivator(LogicalKeyboardKey.f3): () => _move(1),
                const SingleActivator(LogicalKeyboardKey.f3, shift: true): () =>
                    _move(-1),
              },
              child: Focus(
                  autofocus: true,
                  child: AlertDialog(
                    scrollable: true,
                    icon: Icon(Symbols.manage_search, color: scheme.primary),
                    title: AppDialogTitle(ui('查找')),
                    content: AppDialogResize(
                        child: SizedBox(
                            width: contentWidth,
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(widget.songTitle,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall),
                                  const SizedBox(height: 8),
                                  Text(ui('查找原文、译文或注音；定位仅滚动歌词，不改变播放与练习范围。')),
                                  const SizedBox(height: 12),
                                  TextField(
                                      key: const ValueKey('lyric-find-search'),
                                      controller: _search,
                                      focusNode: _searchFocus,
                                      onChanged: (_) => _filter(),
                                      onSubmitted: (_) => _move(1),
                                      decoration: InputDecoration(
                                          labelText: ui('查找'),
                                          prefixIcon:
                                              const Icon(Symbols.search),
                                          border: const OutlineInputBorder(
                                              borderRadius: BorderRadius.all(
                                                  Radius.circular(16))),
                                          suffixIcon: _search.text.isEmpty
                                              ? null
                                              : IconButton(
                                                  tooltip: ui('清除'),
                                                  icon:
                                                      const Icon(Symbols.close),
                                                  onPressed: () {
                                                    _search.clear();
                                                    _filter();
                                                  }))),
                                  const SizedBox(height: 8),
                                  _steps(current, contentWidth),
                                  const SizedBox(height: 8),
                                  Text(
                                      ui('匹配：{0} / {1}', [
                                        _visible.isEmpty ? 0 : _selected + 1,
                                        _visible.length
                                      ]),
                                      key: const ValueKey('lyric-find-count'),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall),
                                  const SizedBox(height: 8),
                                  SizedBox(
                                      height:
                                          (MediaQuery.sizeOf(context).height *
                                                  .3)
                                              .clamp(120, 260),
                                      child: _visible.isEmpty
                                          ? Center(
                                              child: Text(ui('当前歌词中没有匹配内容')))
                                          : LyricReadingResultList(
                                              key: _results,
                                              scrollViewKey: const ValueKey(
                                                  'lyric-find-results'),
                                              controller: _list,
                                              resetToken: _search.text,
                                              itemCount: _visible.length,
                                              itemBuilder: (context, index) {
                                                final row = _visible[index];
                                                return LyricReadingResultRow(
                                                    tileKey: ValueKey(
                                                        'lyric-find-result-${row.index}-${row.target.textOffset ?? -1}'),
                                                    selected:
                                                        index == _selected,
                                                    icon: index == _selected
                                                        ? Symbols
                                                            .radio_button_checked
                                                        : Symbols
                                                            .radio_button_unchecked,
                                                    text: row
                                                        .preview(_search.text),
                                                    semanticsText: row.text,
                                                    timestamp: widget.lyric
                                                            is PlainLyric
                                                        ? null
                                                        : lyricReadingTimestamp(
                                                            row.line.start),
                                                    onTap: current
                                                        ? () => setState(() =>
                                                            _selected = index)
                                                        : null);
                                              })),
                                  if (!current) ...[
                                    const SizedBox(height: 8),
                                    Text(ui('歌曲或歌词已改变，请重新查找'),
                                        style: TextStyle(color: scheme.error))
                                  ],
                                ]))),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(ui('取消'))),
                      FilledButton(
                          key: const ValueKey('lyric-find-locate'),
                          onPressed:
                              current && _visible.isNotEmpty ? _apply : null,
                          child: Text(ui('定位阅读')))
                    ],
                  )));
        });
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    _list.dispose();
    super.dispose();
  }
}

class _NoChanges implements Listenable {
  const _NoChanges();
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}
