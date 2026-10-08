import 'dart:async';
import 'dart:math' as math;

import 'package:dan_player/component/app_data_storage_card.dart';
import 'package:dan_player/statistics/app_data_storage.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

enum DirectoryStorageScope { cache, player }

/// The page owns both read-only snapshots and explicit refreshes. The player
/// directory is requested only when selected for the first time.
class DirectoryStorageCard extends StatefulWidget {
  const DirectoryStorageCard(
      {super.key,
      required this.cacheReading,
      this.playerReading,
      required this.onPlayerSelected});

  final Future<AppDataStorageSnapshot> cacheReading;
  final Future<AppDataStorageSnapshot>? playerReading;
  final VoidCallback onPlayerSelected;

  @override
  State<DirectoryStorageCard> createState() => _DirectoryStorageCardState();
}

class _DirectoryStorageCardState extends State<DirectoryStorageCard> {
  var _scope = DirectoryStorageScope.cache;
  var _playerRequested = false;
  // A static pending result covers the frame before the page supplies its
  // future. Passing null would activate the cache card's standalone scanner.
  final _awaitingPlayer = Completer<AppDataStorageSnapshot>();

  void _select(DirectoryStorageScope scope) {
    if (scope == _scope) return;
    setState(() => _scope = scope);
    if (scope == DirectoryStorageScope.player &&
        widget.playerReading == null &&
        !_playerRequested) {
      _playerRequested = true;
      widget.onPlayerSelected();
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final player = _scope == DirectoryStorageScope.player;
    return AppDataStorageCard(
        reading: player
            ? widget.playerReading ?? _awaitingPlayer.future
            : widget.cacheReading,
        readingScope: _scope,
        title: player ? ui('播放器组件目录占用') : null,
        icon: player ? Symbols.folder : Symbols.database,
        scopeDescription: player
            ? ui('播放器目录内的实际文件字节；不包含外部音乐、用户数据或外部工具。链接不跟随，首次选择或手动刷新时读取。')
            : null,
        headerControls: LayoutBuilder(builder: (context, constraints) {
          Widget choice(DirectoryStorageScope scope, String text) {
            final selected = _scope == scope;
            final chipTheme = ChipTheme.of(context);
            final style = (chipTheme.labelStyle ??
                    Theme.of(context).textTheme.labelLarge!)
                .merge(selected ? chipTheme.secondaryLabelStyle : null);
            final line = TextPainter(
                text: TextSpan(text: text, style: style),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
                maxLines: 1)
              ..layout();
            final markSize = line.height;
            line.dispose();
            final label = Builder(builder: (context) {
              // RawChip supplies a one-line default. Keep its resolved
              // selected/disabled style while allowing the full label.
              return DefaultTextStyle(
                  style: DefaultTextStyle.of(context).style,
                  softWrap: true,
                  overflow: TextOverflow.visible,
                  child: ConstrainedBox(
                      constraints: BoxConstraints(
                          maxWidth: math.max(
                              1.0, constraints.maxWidth - markSize - 48)),
                      child: Text(text)));
            });
            return ChoiceChip(
                key: ValueKey('directory-storage-scope-${scope.name}'),
                label: label,
                // Keep the native check at a normal single-line size when the
                // label wraps. Its slot must use the resolved chip font's
                // actual line metrics, not the Theme's nominal font height.
                avatar: const SizedBox.shrink(),
                avatarBorder: const _EmptyAvatarBorder(),
                avatarBoxConstraints:
                    BoxConstraints.tightFor(width: markSize, height: markSize),
                showCheckmark: true,
                selected: selected,
                onSelected: (_) => _select(scope));
          }

          return Wrap(
              key: const ValueKey('directory-storage-scope'),
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                choice(DirectoryStorageScope.cache, ui('缓存与播放器数据')),
                choice(DirectoryStorageScope.player, ui('播放器目录')),
              ]);
        }));
  }
}

// A fixed empty avatar constrains RawChip's otherwise multi-line-sized check
// slot. RawChip also paints an avatar scrim; there is no avatar here to darken.
// Suppress only that scrim, leaving its native check, colors and animation.
class _EmptyAvatarBorder extends ShapeBorder {
  const _EmptyAvatarBorder();
  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;
  @override
  ShapeBorder scale(double t) => this;
  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => Path();
  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => Path();
  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}
}
