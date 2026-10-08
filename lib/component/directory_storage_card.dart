import 'dart:async';

import 'package:dan_player/component/app_data_storage_card.dart';
import 'package:dan_player/component/app_segmented_control.dart';
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
        headerControls: AppSegmentedControl<DirectoryStorageScope>(
            key: const ValueKey('directory-storage-scope'),
            wrapCompactLabel: true,
            value: _scope,
            onChanged: _select,
            options: [
              AppSegmentOption(
                  value: DirectoryStorageScope.cache,
                  label: ui('缓存与播放器数据'),
                  icon: Symbols.database,
                  key: const ValueKey('directory-storage-scope-cache')),
              AppSegmentOption(
                  value: DirectoryStorageScope.player,
                  label: ui('播放器目录'),
                  icon: Symbols.folder,
                  key: const ValueKey('directory-storage-scope-player')),
            ]));
  }
}
