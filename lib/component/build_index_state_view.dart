import 'dart:async';
import 'dart:io';

import 'package:dan_player/src/rust/api/tag_reader.dart';
import 'package:dan_player/utils.dart';
import 'package:flutter/material.dart';

class BuildIndexStateView extends StatefulWidget {
  const BuildIndexStateView({
    super.key,
    required this.indexPath,
    required this.folders,
    required this.whenIndexBuilt,
    this.whenIndexFailed,
  });

  final Directory indexPath;
  final List<String> folders;
  final FutureOr<void> Function() whenIndexBuilt;
  final void Function(Object error, StackTrace stackTrace)? whenIndexFailed;

  @override
  State<BuildIndexStateView> createState() => _BuildIndexStateViewState();
}

class _BuildIndexStateViewState extends State<BuildIndexStateView> {
  late final Stream<IndexActionState> buildIndexStream;
  StreamSubscription? _subscription;
  bool _settled = false;

  @override
  void initState() {
    super.initState();
    buildIndexStream = buildIndexFromFoldersRecursively(
      folders: widget.folders,
      indexPath: widget.indexPath.path,
    ).asBroadcastStream();

    _subscription = buildIndexStream.listen(
      (action) {
        LOGGER.i("[build index] ${action.progress}: ${action.message}");
      },
      onDone: () async {
        if (_settled) return;
        _settled = true;
        try {
          await widget.whenIndexBuilt();
        } catch (error, stackTrace) {
          LOGGER.e("[load refreshed index] $error", stackTrace: stackTrace);
          widget.whenIndexFailed?.call(error, stackTrace);
        } finally {
          await _subscription?.cancel();
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (_settled) return;
        _settled = true;
        LOGGER.e("[build index] $error", stackTrace: stackTrace);
        widget.whenIndexFailed?.call(error, stackTrace);
        _subscription?.cancel();
      },
      cancelOnError: true,
    );
  }

  @override
  void dispose() {
    _settled = true;
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return StreamBuilder(
      stream: buildIndexStream,
      builder: (context, snapshot) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            LinearProgressIndicator(
              value: snapshot.data?.progress,
              borderRadius: BorderRadius.circular(2.0),
            ),
            const SizedBox(height: 8.0),
            Text(
              snapshot.hasError
                  ? "刷新失败：${snapshot.error}"
                  : snapshot.data?.message ?? "正在准备扫描",
              style: TextStyle(color: scheme.onSurface),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        );
      },
    );
  }
}
