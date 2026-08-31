import 'dart:async';
import 'dart:io';

import 'package:dan_player/src/rust/api/tag_reader.dart';
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

  Stream<IndexActionState> _scan() =>
      widget.scan?.call(_folders, widget.indexPath, widget.incremental) ??
      (widget.incremental
          ? updateIndex(indexPath: widget.indexPath.path)
          : buildIndexFromFoldersRecursively(
              folders: _folders, indexPath: widget.indexPath.path));

  @override
  void dispose() {
    _settled = true;
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
              ? ui("刷新失败：{0}", [_error])
              : (_action?.message.isNotEmpty == true
                  ? _action!.message
                  : ui("正在准备扫描")),
          style: TextStyle(color: scheme.onSurface),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
