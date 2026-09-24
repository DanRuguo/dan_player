import 'package:dan_player/online/network_proxy_preferences.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('single native URL slot drops a superseded open and samples new proxy',
      () async {
    final gate = BassUrlOpenGate();
    final target = Uri.https('music.example', '/song.mp3');
    var generation = 1;
    var preferences = const NetworkProxyPreferences(
        mode: NetworkProxyMode.custom,
        customProxyUrl: 'http://first-proxy:7890');

    expect(await gate.acquire(() => generation == 1), isTrue);
    generation = 2;
    final stale = gate.acquire(() => generation == 2);
    await Future<void>.delayed(Duration.zero);
    generation = 3;
    preferences = const NetworkProxyPreferences(
        mode: NetworkProxyMode.custom, customProxyUrl: 'http://new-proxy:8080');
    gate.cancelStaleWaiters();
    final latest = gate.acquire(() => generation == 3).then((acquired) {
      if (!acquired) return null;
      try {
        return bassProxyForUrl(target, preferences);
      } finally {
        gate.release();
      }
    });

    expect(await stale, isFalse);
    gate.release();
    expect(await latest, 'new-proxy:8080');
  });

  test('two live players wait in FIFO order without waking one another',
      () async {
    final gate = BassUrlOpenGate();
    expect(await gate.acquire(() => true), isTrue);
    final second = gate.acquire(() => true);
    final third = gate.acquire(() => true);
    var thirdFinished = false;
    third.then((_) => thirdFinished = true);
    await Future<void>.delayed(Duration.zero);
    expect(thirdFinished, isFalse);

    gate.release();
    expect(await second, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(thirdFinished, isFalse);
    gate.release();
    expect(await third, isTrue);
    gate.release();
  });
}
