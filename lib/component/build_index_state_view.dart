import 'dart:async';
import 'dart:io';

import 'package:dan_player/src/rust/api/tag_reader.dart';
import 'package:dan_player/library/library_refresh.dart';
import 'package:dan_player/utils.dart';
import 'package:flutter/material.dart';
import 'package:desktop_lyric/ui_language.dart';

typedef IndexScanFactory = Stream<IndexActionState> Function(
    List<String> folders, Directory indexPath, bool incremental);

class BuildIndexStateView extends StatefulWidget {
  const BuildIndexStateView({
    super.key,
    required this.indexPath,
    required this.folders,
    required this.whenIndexBuilt,
    this.whenIndexFailed,
    this.incremental = false,
    this.scan,
  });

  final Directory indexPath;
  final List<String> folders;
  final bool incremental;
  final IndexScanFactory? scan;
  final FutureOr<void> Function() whenIndexBuilt;
  final void Function(Object error, StackTrace stackTrace)? whenIndexFailed;

  @override
  State<BuildIndexStateView> createState() => _BuildIndexStateViewState();
}

class _BuildIndexStateViewState extends State<BuildIndexStateView> {
  StreamSubscription? _subscription;
  IndexActionState? _action;
  Object? _error;
  late final List<String> _folders = List<String>.unmodifiable(widget.folders);
  bool _settled = false;
  LibraryRefreshTask? _nativeTask;

  void _phaseChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    try {
      _subscription = _scan().listen(
        (action) {
          LOGGER.i("[build index] ${action.progress}: ${action.message}");
          if (mounted) setState(() => _action = action);
        },
        onDone: () async {
          if (_settled) return;
          _settled = true;
          try {
            await widget.whenIndexBuilt();
          } catch (error, stackTrace) {
            LOGGER.e("[load refreshed index] $error", stackTrace: stackTrace);
            if (mounted) widget.whenIndexFailed?.call(error, stackTrace);
          } finally {
            await _subscription?.cancel();
          }
        },
        onError: _fail,
        cancelOnError: true,
      );
    } catch (error, stackTrace) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _fail(error, stackTrace));
    }
  }

  void _fail(Object error, StackTrace stackTrace) {
    if (_settled || !mounted) return;
    _settled = true;
    LOGGER.e('[build index] $error', stackTrace: stackTrace);
    setState(() => _error = error);
    widget.whenIndexFailed?.call(error, stackTrace);
    _subscription?.cancel();
  }

  Stream<IndexActionState> _scan() {
    if (widget.scan != null) {
      return widget.scan!(_folders, widget.indexPath, widget.incremental);
    }
    final task = LibraryRefreshTask.native(
        folders: _folders,
        indexPath: widget.indexPath,
        incremental: widget.incremental,
        commit: () async {
          if (!mounted || _settled) return 0;
          await widget.whenIndexBuilt();
          _settled = true;
          return 0;
        });
    _nativeTask = task;
    task.addListener(_phaseChanged);
    return task.stream;
  }

  @override
  void dispose() {
    _settled = true;
    _nativeTask?.removeListener(_phaseChanged);
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        LinearProgressIndicator(
          value: _action?.progress,
          borderRadius: BorderRadius.circular(2.0),
        ),
        const SizedBox(height: 8.0),
        Text(
          _error != null
              ? (_error is LibraryScanCancelled
                  ? ui('扫描已取消')
                  : ui("刷新失败：{0}", [_error]))
              : _nativeTask?.phase == LibraryRefreshPhase.cancelling
                  ? ui('正在取消扫描')
                  : (_action?.message == 'INDEX_PHASE_COMMITTING'
                      ? ui('正在提交曲库')
                      : _action?.message.isNotEmpty == true
                          ? _action!.message
                          : ui("正在准备扫描")),
          style: TextStyle(color: scheme.onSurface),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (_nativeTask != null && !_nativeTask!.isTerminal) ...[
          const SizedBox(height: 12),
          OutlinedButton(
              onPressed:
                  _nativeTask!.canCancel ? _nativeTask!.requestCancel : null,
              child: Text(ui('取消扫描'))),
        ],
      ],
    );
  }
}
