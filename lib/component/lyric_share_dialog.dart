import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as raster;

import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/lyric_share_card.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as path;

typedef LyricSharePngSaver = Future<bool> Function(
    Uint8List bytes, String suggestedName);

Future<void> showLyricShareDialog(
  BuildContext context, {
  required String title,
  required String artist,
  required String album,
  required List<String> lines,
  int initialIndex = 0,
  ImageProvider? artwork,
}) {
  final snapshot = List<String>.unmodifiable(lines);
  return showAppDialog<void>(
    context: context,
    builder: (_) => LyricShareDialog(
      title: title,
      artist: artist,
      album: album,
      lines: snapshot,
      initialIndex: initialIndex,
      artwork: artwork,
    ),
  );
}

/// No persistent settings or media/network request belongs to this snapshot.
class LyricShareDialog extends StatefulWidget {
  const LyricShareDialog({
    super.key,
    required this.title,
    required this.artist,
    required this.album,
    required this.lines,
    this.initialIndex = 0,
    this.artwork,
    this.savePng,
  });
  final String title, artist, album;
  final List<String> lines;
  final int initialIndex;
  final ImageProvider? artwork;
  @visibleForTesting
  final LyricSharePngSaver? savePng;
  @override
  State<LyricShareDialog> createState() => _LyricShareDialogState();
}

class _LyricShareDialogState extends State<LyricShareDialog> {
  late final _lines = List<String>.unmodifiable(widget.lines);
  late final String _title = widget.title,
      _artist = widget.artist,
      _album = widget.album;
  late final _artwork = widget.artwork;
  final _selected = <int>{};
  final _boundary = GlobalKey();
  bool _showSongInfo = true, _saving = false;
  String? _error;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    if (_lines.isNotEmpty) {
      final initial = widget.initialIndex.clamp(0, _lines.length - 1);
      final index = _lines[initial].trim().isNotEmpty
          ? initial
          : _lines.indexWhere((line) => line.trim().isNotEmpty);
      if (index >= 0) _selected.add(index);
    }
  }

  List<String> get _chosen => [
        for (var i = 0; i < _lines.length; i++)
          if (_selected.contains(i)) _lines[i],
      ];

  void _toggle(int index) {
    if (_saving) return;
    setState(() {
      if (!_selected.remove(index) && _selected.length < 4) {
        _selected.add(index);
      }
      _saved = false;
      _error = null;
    });
  }

  // Generic network providers must not turn an offline card preview into a new
  // request. Captured pixels are represented by MemoryImage by the caller.
  ImageProvider? get _offlineArtwork {
    final provider = _artwork;
    return provider is MemoryImage ||
            provider is FileImage ||
            provider is AssetImage ||
            provider is ExactAssetImage
        ? provider
        : null;
  }

  LyricShareCard get _card => LyricShareCard(
        title: _title,
        artist: _artist,
        album: _album,
        lines: _chosen,
        showSongInfo: _showSongInfo,
        artwork: _offlineArtwork,
      );

  String get _suggestedName {
    final name = _title
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
        .trim()
        .replaceAll(RegExp(r'[. ]+$'), '');
    // A fixed prefix also avoids Windows device names such as CON or AUX.
    return '${name.isEmpty ? 'Dan Player' : 'Dan Player - ${name.characters.take(80)}'}.png';
  }

  Future<bool> _saveFile(Uint8List bytes, String name) async {
    final file = (SaveFilePicker()
          ..title = ui('导出歌词卡片')
          ..fileName = name
          ..defaultExtension = 'png'
          ..filterSpecification = {'PNG': '*.png'})
        .getFile();
    if (file == null) return false;
    final target = path.extension(file.path).toLowerCase() == '.png'
        ? file
        : File('${file.path}.png');
    await target.writeAsBytes(bytes, flush: true);
    return true;
  }

  Future<void> _export() async {
    if (_saving || _card.measuredHeight(Directionality.of(context)) == null) {
      return;
    }
    setState(() {
      _saving = true;
      _saved = false;
      _error = null;
    });
    try {
      // A last selection/toggle may not have painted yet. Freeze editing while
      // waiting for the shared preview surface's next completed frame.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final boundary = _boundary.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary) {
        throw StateError('The lyric card preview is unavailable');
      }
      final image =
          await boundary.toImage(pixelRatio: LyricShareCard.pixelRatio);
      late final Uint8List bytes;
      try {
        final data = await image.toByteData(format: raster.ImageByteFormat.png);
        if (data == null) throw StateError('PNG encoding failed');
        bytes = Uint8List.fromList(data.buffer.asUint8List());
      } finally {
        image.dispose();
      }
      if (!mounted) return;
      final saved = await (widget.savePng ?? _saveFile)(bytes, _suggestedName);
      if (mounted) setState(() => _saved = saved);
    } catch (_) {
      if (mounted) setState(() => _error = ui('无法保存歌词卡片，请检查位置与访问权限后重试。'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final card = _card;
    final cardHeight = card.measuredHeight(Directionality.of(context));
    final empty = _lines.every((line) => line.trim().isEmpty);
    return AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.all(12),
      title: AppDialogTitle(ui('导出歌词卡片')),
      content: SizedBox(
        width: 740,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(ui('选择最多 4 句歌词；卡片保留所选文字与换行。')),
          const SizedBox(height: 8),
          if (empty) Text(ui('没有可导出的歌词')),
          if (!empty)
            SizedBox(
              height: (MediaQuery.sizeOf(context).height * .25).clamp(120, 240),
              child: ListView.builder(
                key: const ValueKey('lyric-share-selection-list'),
                itemCount: _lines.length,
                itemBuilder: (context, i) => _lines[i].trim().isEmpty
                    ? const SizedBox.shrink()
                    : CheckboxListTile(
                        key: ValueKey('lyric-share-select-$i'),
                        value: _selected.contains(i),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        onChanged: _saving ||
                                (!_selected.contains(i) &&
                                    _selected.length >= 4)
                            ? null
                            : (_) => _toggle(i),
                        title: Text(_lines[i],
                            maxLines: 3, overflow: TextOverflow.ellipsis),
                      ),
              ),
            ),
          SwitchListTile(
            key: const ValueKey('lyric-share-song-info'),
            contentPadding: EdgeInsets.zero,
            title: Text(ui('显示歌曲信息')),
            value: _showSongInfo,
            onChanged: _saving
                ? null
                : (value) => setState(() {
                      _showSongInfo = value;
                      _saved = false;
                      _error = null;
                    }),
          ),
          const SizedBox(height: 12),
          if (_selected.isEmpty && !empty) Text(ui('请至少选择一句歌词')),
          if (_selected.isNotEmpty && cardHeight == null)
            Text(ui('所选内容过长，无法完整放入卡片。请减少句数或隐藏歌曲信息。'),
                key: const ValueKey('lyric-share-too-long')),
          if (cardHeight != null)
            Center(
              child: SizedBox(
                width: LyricShareCard.width,
                child: AspectRatio(
                  aspectRatio: LyricShareCard.width / cardHeight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topCenter,
                    child: RepaintBoundary(key: _boundary, child: card),
                  ),
                ),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!,
                  key: const ValueKey('lyric-share-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (_saved)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child:
                  Text(ui('歌词卡片已保存'), key: const ValueKey('lyric-share-saved')),
            ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(ui('关闭'))),
        FilledButton(
          key: const ValueKey('lyric-share-export'),
          onPressed: _saving || cardHeight == null ? null : _export,
          child: Text(ui(_saving ? '正在保存…' : '保存 PNG')),
        ),
      ],
    );
  }
}
