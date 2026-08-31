import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A failure never means the caller should quit. Manual installation remains
/// available when Windows does not trust the release certificate.
class InstallerLaunchException implements Exception {
  const InstallerLaunchException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

class InstallerLauncher {
  InstallerLauncher({
    MethodChannel channel =
        const MethodChannel('dan_player/installer_launcher'),
    bool Function()? isWindows,
  })  : _channel = channel,
        _isWindows = isWindows ?? (() => Platform.isWindows);

  static final instance = InstallerLauncher();

  final MethodChannel _channel;
  final bool Function() _isWindows;
  bool _launching = false;

  /// Returns only after the verified installer has opened and validated this
  /// process. The caller can then use shutdownAndExit. This class never exits,
  /// changes trust stores, extracts ZIPs, or accepts an installation target/PID.
  Future<void> launchForUpdate({
    required File installer,
    required String sha256,
    required String version,
  }) async {
    if (!_isWindows()) {
      throw const InstallerLaunchException('unsupported_platform',
          'Automatic installer launch requires Windows.');
    }
    if (_launching) {
      throw const InstallerLaunchException(
          'launch_busy', 'An installer launch is already in progress.');
    }
    final path = installer.absolute.path;
    if (!path.toLowerCase().endsWith('.exe') ||
        path.codeUnits.any((value) => value < 32) ||
        !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha256) ||
        !RegExp(r'^\d+\.\d+\.\d+(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?(?:\+[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?$')
            .hasMatch(version) ||
        version.length > 96) {
      throw const InstallerLaunchException('invalid_request',
          'The installer path, SHA-256 or version is invalid.');
    }
    _launching = true;
    try {
      final accepted = await _channel.invokeMethod<bool>('launchForUpdate', {
        'path': path,
        'sha256': sha256.toLowerCase(),
        'version': version,
      });
      if (accepted != true) {
        throw const InstallerLaunchException('launch_not_confirmed',
            'The installer did not confirm a safe launch.');
      }
    } on PlatformException catch (error) {
      throw InstallerLaunchException(error.code,
          error.message ?? 'Windows could not safely start the installer.');
    } on MissingPluginException {
      throw const InstallerLaunchException('launcher_unavailable',
          'This player does not support installer updates.');
    } finally {
      _launching = false;
    }
  }

  @visibleForTesting
  bool get isLaunching => _launching;
}
