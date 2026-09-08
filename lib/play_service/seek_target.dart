class SeekTarget {
  const SeekTarget(this.seconds, {this.relative = false});
  final double seconds;
  final bool relative;
  static SeekTarget parse(String input) {
    final text = input.trim();
    final relative = text.startsWith('+') || text.startsWith('-');
    final value = relative ? text.substring(1) : text;
    if (!RegExp(r'^\d+(?::\d{1,2}){0,2}(?:\.\d{1,3})?$').hasMatch(value))
      throw const FormatException('请输入 mm:ss、hh:mm:ss 或 +30 / -10');
    final parts = value.split(':').map(double.parse).toList();
    if (parts.skip(1).any((p) => p >= 60))
      throw const FormatException('分和秒必须小于 60');
    final result = parts.fold<double>(0, (total, p) => total * 60 + p) *
        (text.startsWith('-') ? -1 : 1);
    if (!result.isFinite || result.abs() > 315360000)
      throw const FormatException('时间超出范围');
    return SeekTarget(result, relative: relative);
  }

  double resolve(double position, double duration) {
    final target = relative ? position + seconds : seconds;
    if (!position.isFinite ||
        !duration.isFinite ||
        duration <= 0 ||
        !target.isFinite ||
        target < 0 ||
        target >= duration) throw const FormatException('目标必须在当前歌曲时长以内');
    return target;
  }
}
