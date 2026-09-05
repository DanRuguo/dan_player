import 'package:path/path.dart' as p;

/// CUE positions retain CD frames (75 per second), avoiding millisecond
/// rounding between adjoining tracks. The final track extends to native EOF.
class CueTrackReference {
  const CueTrackReference(
      {required this.cuePath,
      required this.sourcePath,
      required this.number,
      required this.startFrame,
      this.endFrame});
  final String cuePath;
  final String sourcePath;
  final int number;
  final int startFrame;
  final int? endFrame;
  double get startSeconds => startFrame / 75;
  double? get endSeconds => endFrame == null ? null : endFrame! / 75;
  String get identity =>
      'cue://track/${Uri.encodeComponent(p.windows.normalize(cuePath).toLowerCase())}/$number';

  Map<String, Object?> toMap() => {
        'cue_path': cuePath,
        'source_path': sourcePath,
        'number': number,
        'start_frame': startFrame,
        'end_frame': endFrame
      };

  factory CueTrackReference.fromMap(Map map) {
    final cue = map['cue_path'];
    final source = map['source_path'];
    final number = map['number'];
    final start = map['start_frame'];
    final end = map['end_frame'];
    if (cue is! String ||
        source is! String ||
        !p.windows.isAbsolute(cue) ||
        !p.windows.isAbsolute(source) ||
        cue.contains('\u0000') ||
        source.contains('\u0000') ||
        number is! int ||
        number < 1 ||
        number > 99 ||
        start is! int ||
        start < 0 ||
        (end != null && (end is! int || end <= start))) {
      throw const FormatException('CUE 分轨引用无效。');
    }
    return CueTrackReference(
        cuePath: cue,
        sourcePath: source,
        number: number,
        startFrame: start,
        endFrame: end as int?);
  }
}
