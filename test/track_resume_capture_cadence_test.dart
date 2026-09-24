import 'package:dan_player/play_service/track_resume_capture_cadence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('4x playback captures as soon as media reaches the first valid point',
      () {
    var elapsed = Duration.zero;
    final cadence = TrackResumeCaptureCadence(elapsed: () => elapsed);
    expect(cadence.due(session: 1, position: 0), isFalse);
    elapsed = const Duration(seconds: 2);
    expect(cadence.due(session: 1, position: 8), isFalse);
    elapsed = const Duration(milliseconds: 2500);
    expect(cadence.due(session: 1, position: 10), isTrue);
    elapsed = const Duration(seconds: 5);
    expect(cadence.due(session: 1, position: 20), isFalse);
    elapsed = const Duration(milliseconds: 12500);
    expect(cadence.due(session: 1, position: 50), isTrue);
  });

  test('a new source captures its resumed position without waiting', () {
    var elapsed = Duration.zero;
    final cadence = TrackResumeCaptureCadence(elapsed: () => elapsed);
    expect(cadence.due(session: 1, position: 85), isTrue);
    elapsed = const Duration(seconds: 1);
    expect(cadence.due(session: 1, position: 86), isFalse);
    expect(cadence.due(session: 2, position: 32), isTrue);
  });
}
