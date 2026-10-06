import 'dart:async';
import 'dart:math' as math;

import 'package:dan_player/component/app_menu_anchor.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:dan_player/component/playlist_cover_transition.dart';
import 'package:dan_player/playlist_view.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';

/// The same bounded cover tracker as real playlists, with local sample artwork.
/// Its parent supplies visibility through TickerMode, including pending capture.
class PlayerGuidePlaylistDemo extends StatefulWidget {
  const PlayerGuidePlaylistDemo({super.key, this.viewportKey});
  final GlobalKey? viewportKey;

  @override
  State<PlayerGuidePlaylistDemo> createState() =>
      _PlayerGuidePlaylistDemoState();
}

class _PlayerGuidePlaylistDemoState extends State<PlayerGuidePlaylistDemo> {
  final _transition = PlaylistCoverTransitionController();
  PlaylistViewMode _mode = PlaylistViewMode.list;
  PlaylistViewMode _requestedMode = PlaylistViewMode.list;
  static const _ids = [
    'guide-playlist-dawn',
    'guide-playlist-noon',
    'guide-playlist-night'
  ];
  static const _names = ['晨光', '午后', '夜色'];

  String _label(PlaylistViewMode mode) => ui(switch (mode) {
        PlaylistViewMode.list => '列表',
        PlaylistViewMode.grid => '矩形',
        PlaylistViewMode.circular => '圆形',
        PlaylistViewMode.tree => '树状',
      });

  IconData _icon(PlaylistViewMode mode) => switch (mode) {
        PlaylistViewMode.list => Icons.view_list_outlined,
        PlaylistViewMode.grid => Icons.grid_view_outlined,
        PlaylistViewMode.circular => Icons.album_outlined,
        PlaylistViewMode.tree => Icons.account_tree_outlined,
      };

  void _select(PlaylistViewMode mode) {
    // The displayed mode may still be waiting for capture. Compare the last
    // input so a rapid return to the old layout remains a real user request.
    if (_requestedMode == mode) return;
    _requestedMode = mode;
    unawaited(_transition.transition(() {
      if (mounted) setState(() => _mode = mode);
    }, preserveAnchor: false));
  }

  @override
  void dispose() {
    _transition.dispose();
    super.dispose();
  }

  Widget _cover(int index, double side, {bool circular = false}) {
    final radius =
        circular ? BorderRadius.circular(side / 2) : AppShape.controlRadius;
    return ExcludeSemantics(
        child: ClipRRect(
            borderRadius: radius,
            child: PlaylistCoverTransitionMarker(
                key: ValueKey(_ids[index]),
                entryId: _ids[index],
                borderRadius: radius,
                child: Image.asset('assets/images/RCE_logo_transparent.png',
                    width: side, height: side, fit: BoxFit.cover))));
  }

  Widget _row(BuildContext context, int index, {bool tree = false}) => SizedBox(
      height: 64,
      child: Padding(
          padding: EdgeInsets.only(left: tree ? index * 12 : 0),
          child: Row(children: [
            if (tree) ...[
              Icon(index == 0 ? Icons.expand_more : Icons.chevron_right,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
            ],
            _cover(index, 40),
            const SizedBox(width: 10),
            Expanded(child: Text(ui(_names[index]), maxLines: 2)),
          ])));

  Widget _tiles(BuildContext context, {bool circular = false}) =>
      LayoutBuilder(builder: (context, constraints) {
        var labelWidth = 0.0, labelHeight = 0.0;
        for (final name in _names) {
          final painter = TextPainter(
              text: TextSpan(
                  text: ui(name),
                  style: Theme.of(context).textTheme.bodyMedium),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context))
            ..layout();
          labelWidth = math.max(labelWidth, painter.width);
          labelHeight = math.max(labelHeight, painter.height);
          painter.dispose();
        }
        final columns =
            (constraints.maxWidth - 16) / 3 >= math.max(56, labelWidth) ? 3 : 2;
        final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
        // At large text scales use two rows and preserve natural label height
        // within the same bounded demonstration surface.
        final side = math.min(
            width, columns == 3 ? 72.0 : math.max(24.0, 92 - labelHeight));
        return Wrap(spacing: 8, runSpacing: 8, children: [
          for (var index = 0; index < _ids.length; index++)
            SizedBox(
                width: width,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  _cover(index, side, circular: circular),
                  const SizedBox(height: 8),
                  Text(ui(_names[index]),
                      textAlign: TextAlign.center, maxLines: 2),
                ])),
        ]);
      });

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppMenuAnchor(
          menuChildren: [
            for (final mode in PlaylistViewMode.values)
              MenuItemButton(
                  key: ValueKey('guide-demo-playlist-select-${mode.name}'),
                  leadingIcon: Icon(_icon(mode), size: appToolbarIconSize),
                  trailingIcon:
                      _mode == mode ? const Icon(Icons.check, size: 18) : null,
                  onPressed: () => _select(mode),
                  child: Text(_label(mode))),
          ],
          builder: (context, menu, _) => Tooltip(
              message: _label(_mode),
              child: OutlinedButton(
                  key: const ValueKey('guide-demo-playlist-menu'),
                  style: appToolbarControlStyle(context),
                  onPressed: () => menu.isOpen ? menu.close() : menu.open(),
                  child: AppToolbarLabel(
                      label: _label(_mode),
                      icon: _icon(_mode),
                      trailing: const Icon(Icons.arrow_drop_down, size: 20))))),
      const SizedBox(height: 12),
      KeyedSubtree(
          key: const ValueKey('guide-demo-playlist-body'),
          child: SizedBox(
              key: widget.viewportKey,
              height: 208,
              child: PlaylistCoverTransitionHost(
                  controller: _transition,
                  itemIds: _ids,
                  child: Align(
                      alignment: Alignment.topCenter,
                      child: KeyedSubtree(
                          key: ValueKey(
                              'guide-demo-playlist-layout-${_mode.name}'),
                          child: switch (_mode) {
                            PlaylistViewMode.list => Column(children: [
                                for (var i = 0; i < _ids.length; i++)
                                  _row(context, i)
                              ]),
                            PlaylistViewMode.grid => _tiles(context),
                            PlaylistViewMode.circular =>
                              _tiles(context, circular: true),
                            PlaylistViewMode.tree => Column(children: [
                                for (var i = 0; i < _ids.length; i++)
                                  _row(context, i, tree: true)
                              ]),
                          }))))),
    ]);
  }
}
