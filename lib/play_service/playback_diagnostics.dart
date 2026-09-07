import 'dart:async';
import 'package:path/path.dart' as p;

/// Rebind a verified successful local rename without touching its open handle.
/// No filesystem probing occurs here: the metadata commit owns that check.
String? relinkedLocalPlaybackPath({
  required String? currentPath,
  required bool isUrl,
  required String oldPath,
  required String newPath,
}) {
  if (isUrl ||
      currentPath == null ||
      !p.windows.equals(currentPath, oldPath) ||
      newPath.isEmpty ||
      newPath.length > 32767 ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(newPath) ||
      !p.windows.isAbsolute(newPath) ||
      p.windows.isRootRelative(newPath) ||
      newPath.endsWith('\\') ||
      newPath.endsWith('/')) {
    return null;
  }
  final normalized = p.windows.normalize(newPath);
  if (p.windows.dirname(normalized) == normalized) return null;
  return normalized;
}

String sourcePathAfterLocalRelink({
  required String requested,
  required String? previousCurrent,
  required String? current,
  required bool isUrl,
}) =>
    !isUrl &&
            previousCurrent != null &&
            current != null &&
            p.windows.equals(previousCurrent, requested)
        ? current
        : requested;

/// Small, backend-independent contracts shared by playback and diagnostics.
enum PlaybackEndReason {
  naturalEnd,
  segmentEnd,
  userStop,
  sourceReplaced,
  invalidHandle,
  deviceUnavailable,
  unexpectedStop,
}

enum PlaybackProblemKind {
  sourceUnavailable,
  decodeFailure,
  deviceInitialization,
  exclusiveDenied,
  deviceDisconnected,
  invalidHandle,
  unexpectedStop,
  unknown,
}

class PlaybackProblem implements Exception {
  const PlaybackProblem(this.kind, this.message, {this.nativeCode});
  final PlaybackProblemKind kind;
  final String message;
  final int? nativeCode;

  String get suggestion => switch (kind) {
        PlaybackProblemKind.sourceUnavailable => '检查来源、文件位置或网络后重试。',
        PlaybackProblemKind.decodeFailure => '尝试其他音频文件，检查文件是否完整。',
        PlaybackProblemKind.exclusiveDenied => '关闭占用设备的程序，或手动切换共享输出。',
        PlaybackProblemKind.deviceInitialization ||
        PlaybackProblemKind.deviceDisconnected =>
          '检查 Windows 输出设备，连接后手动恢复播放。',
        PlaybackProblemKind.invalidHandle ||
        PlaybackProblemKind.unexpectedStop =>
          '重新打开歌曲；若再次出现，请导出播放诊断。',
        PlaybackProblemKind.unknown => '重试；若再次出现，请导出播放诊断。',
      };

  /// Deliberately exclude raw exception messages: URLs, paths and tokens may
  /// be present in upstream errors. Export only the controlled category/code.
  Map<String, Object?> toSafeJson() => {
        'category': kind.name,
        'nativeCode': nativeCode,
      };

  @override
  String toString() => '$message $suggestion';
}

class PlaybackStamp {
  const PlaybackStamp(this.session, this.operation);
  final int session;
  final int operation;
}

/// A path is not a session: returning to A after B still creates a new stamp.
/// Commands invalidate queued events, without invalidating an unrelated open.
class PlaybackEventBoundary {
  int _session = 0;
  int _operation = 0;
  bool _settled = false;
  PlaybackStamp get stamp => PlaybackStamp(_session, _operation);

  void replace() {
    _session++;
    command(rearm: true);
  }

  void command({bool rearm = false}) {
    _operation++;
    if (rearm) _settled = false;
  }

  bool accepts(PlaybackStamp stamp) =>
      stamp.session == _session && stamp.operation == _operation;

  Stream<T> currentEvents<T>(
          Stream<T> events, PlaybackStamp Function(T) stampOf) =>
      events.where((event) => accepts(stampOf(event)));

  bool settle(PlaybackStamp stamp) {
    if (!accepts(stamp) || _settled) return false;
    _settled = true;
    return true;
  }
}

/// A stopped channel alone is not evidence of completion. The position is a
/// backend media boundary, not proof that the physical endpoint has drained.
PlaybackEndReason classifyPlaybackStop({
  required bool validHandle,
  required bool deviceAvailable,
  required double position,
  required double duration,
  bool segment = false,
}) {
  if (!validHandle) return PlaybackEndReason.invalidHandle;
  if (!deviceAvailable) return PlaybackEndReason.deviceUnavailable;
  if (duration.isFinite &&
      duration > 0 &&
      position.isFinite &&
      position >= duration - 0.001) {
    return segment
        ? PlaybackEndReason.segmentEnd
        : PlaybackEndReason.naturalEnd;
  }
  return PlaybackEndReason.unexpectedStop;
}
