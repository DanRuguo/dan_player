import 'package:dan_player/library/audio_library.dart';

/// Descriptor-only summary: no decoder access or periodic timer. Unknown
/// durations remain explicitly unknown rather than being advertised as zero.
class QueueDurationSummary {
  const QueueDurationSummary(this.seconds, this.unknownCount);
  final double seconds;
  final int unknownCount;

  factory QueueDurationSummary.of(Iterable<Audio> items) {
    var seconds = 0.0;
    var unknown = 0;
    for (final audio in items) {
      final value = audio.duration;
      if (value.isFinite && value > 0) {
        seconds += value;
      } else {
        unknown++;
      }
    }
    return QueueDurationSummary(seconds, unknown);
  }

  String get clock {
    final rounded = seconds.ceil();
    final hours = rounded ~/ 3600;
    final minutes = (rounded % 3600) ~/ 60;
    final tail = (rounded % 60).toString().padLeft(2, '0');
    return hours > 0
        ? '$hours:${minutes.toString().padLeft(2, '0')}:$tail'
        : '$minutes:$tail';
  }
}
