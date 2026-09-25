import 'package:dan_player/app_settings.dart';
import 'package:flutter/material.dart';

/// Keeps an optimistic choice active in this session and reports a failed write.
/// A newer choice supersedes the outcome of an older write.
mixin SettingsChoicePersistence<T extends StatefulWidget> on State<T> {
  bool _saveFailed = false;
  int _saveRevision = 0;

  bool get saveFailed => _saveFailed;

  Future<void> saveChoice(Future<void> Function()? persist) async {
    final revision = ++_saveRevision;
    if (_saveFailed) setState(() => _saveFailed = false);
    try {
      await (persist ??
          () => AppSettings.instance
              .saveSettings(throwOnError: true, captureWindowSize: false))();
    } catch (_) {
      if (mounted && revision == _saveRevision) {
        setState(() => _saveFailed = true);
      }
    }
  }
}
