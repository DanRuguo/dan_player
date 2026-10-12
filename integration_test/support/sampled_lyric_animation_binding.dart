import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Native pixel fixtures with the same explicit animation samples as software
/// tests. Live binding normally uses wall time, including screenshot readbacks;
/// onlyPumps controls frame requests, but does not freeze that animation clock.
/// Rendering remains on the real Windows engine. This is not a frame-rate probe.
class SampledLyricAnimationBinding
    extends IntegrationTestWidgetsFlutterBinding {
  Duration _sampleTime = Duration.zero;

  @override
  void handleBeginFrame(Duration? rawTimeStamp) =>
      super.handleBeginFrame(_sampleTime);

  @override
  Future<void> pump([Duration? duration,
      EnginePhase newPhase = EnginePhase.sendSemanticsUpdate]) {
    _sampleTime += duration ?? Duration.zero;
    return super.pump(null, newPhase);
  }
}
