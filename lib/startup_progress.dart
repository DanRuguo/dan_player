import 'package:flutter/foundation.dart';

enum StartupStage {
  preferences(.08, '正在读取界面设置'),
  window(.18, '正在准备播放器窗口'),
  checkingLibrary(.24, '正在检查音乐索引'),
  loadingLibrary(.68, '正在载入曲库'),
  playlists(.80, '正在载入歌单与歌词'),
  playback(.92, '正在恢复播放状态'),
  ready(1, '等待开屏动画结束');

  const StartupStage(this.progress, this.label);
  final double progress;
  final String label;
}

@immutable
class StartupProgressValue {
  const StartupProgressValue({
    this.stage = StartupStage.ready,
    this.scanProgress = 0,
    this.failed = false,
    this.cancelScan,
    this.cancelling = false,
  });

  final StartupStage stage;
  final double scanProgress;
  final bool failed;
  final VoidCallback? cancelScan;
  final bool cancelling;
  bool get ready => stage == StartupStage.ready;
  double get progress => stage == StartupStage.checkingLibrary
      ? stage.progress + scanProgress * .40
      : stage.progress;
  String get label => cancelling ? '正在取消扫描' : stage.label;
}

/// Milestones come from completed initialization work, never elapsed time.
/// This is only a presentation observer: it does not own startup or scanning.
class StartupProgress extends ValueNotifier<StartupProgressValue> {
  StartupProgress() : super(const StartupProgressValue());
  static final instance = StartupProgress();

  void begin() => value = const StartupProgressValue(
        stage: StartupStage.preferences,
      );

  void advance(StartupStage stage) {
    if (value.failed || stage.index < value.stage.index) return;
    if (stage == value.stage && value.cancelScan == null) return;
    value = StartupProgressValue(stage: stage);
  }

  void scan(double progress, {VoidCallback? cancel, bool cancelling = false}) {
    if (value.failed || value.stage != StartupStage.checkingLibrary) return;
    final next = progress.isFinite
        ? progress.clamp(value.scanProgress, 1.0)
        : value.scanProgress;
    // Quantize native file-level messages to meaningful visible changes.
    if ((next - value.scanProgress).abs() < .005 &&
        (cancel != null) == (value.cancelScan != null) &&
        cancelling == value.cancelling) {
      return;
    }
    value = StartupProgressValue(
      stage: StartupStage.checkingLibrary,
      scanProgress: next,
      cancelScan: cancel,
      cancelling: cancelling,
    );
  }

  void fail() => value = StartupProgressValue(stage: value.stage, failed: true);
}
