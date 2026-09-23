import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/play_service/lyric_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('old settings default off and opt-in survives disk reload', () async {
    final settings = AppSettings.instance;
    expect(settings.automaticOnlineLyrics.value, isFalse);
    final file = File('${(await getAppDataDir()).path}/settings.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode({'Version': '26.0.5'}));
    await AppSettings.readFromJson();
    expect(settings.automaticOnlineLyrics.value, isFalse);
    settings.automaticOnlineLyrics.value = true;
    await settings.saveSettings(captureWindowSize: false, throwOnError: true);
    settings.automaticOnlineLyrics.value = false;
    await AppSettings.readFromJson();
    expect(settings.automaticOnlineLyrics.value, isTrue);
    settings.automaticOnlineLyrics.value = false;
  });
  for (final enabled in [false, true]) {
    for (final savedSource in ['missing', 'local', 'cached']) {
      test('$savedSource with automatic networking $enabled', () async {
        var calls = 0;
        final saved = savedSource == 'missing'
            ? null
            : Lrc.fromLrcText('[00:01.00]saved', LrcSource.local);
        final online = Lrc.fromLrcText('[00:01.00]online', LrcSource.local);
        final result = await resolveMissingLyricOnline(
          saved: resolveAutomaticLyricSources(
              localFirst: true,
              local: () async => savedSource == 'local' ? saved : null,
              cachedOnline: () async => savedSource == 'cached' ? saved : null),
          allowed: () => enabled,
          search: () async {
            calls++;
            return online;
          },
        );
        final shouldSearch = enabled && saved == null;
        expect(calls, shouldSearch ? 1 : 0);
        expect(result, same(shouldSearch ? online : saved));
      });
    }
  }
  test('revoking permission during disk lookup prevents networking', () async {
    var allowed = true;
    var calls = 0;
    final disk = Completer<Lyric?>();
    final result = resolveMissingLyricOnline(
        saved: disk.future,
        allowed: () => allowed,
        search: () async {
          calls++;
          return null;
        });
    allowed = false;
    disk.complete(null);
    expect(await result, isNull);
    expect(calls, 0);
  });
}
