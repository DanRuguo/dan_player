import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _source(String relativePath) => File(relativePath).readAsStringSync();

void main() {
  test('persisted exclusive output is applied when playback is constructed',
      () {
    final mainSource = _source('lib/main.dart');
    final settingsRead = mainSource.indexOf('await AppSettings.readFromJson()');
    final runApp = mainSource.indexOf('runApp(Entry(welcome: welcome))');
    expect(settingsRead, greaterThanOrEqualTo(0));
    expect(runApp, greaterThan(settingsRead));

    final serviceSource = _source('lib/play_service/playback_service.dart');
    expect(serviceSource,
        contains('..wasapiExclusive = features.exclusiveOutput'));

    final playerSource = _source('lib/src/bass/bass_player.dart');
    final setter = playerSource.indexOf('set wasapiExclusive(bool value)');
    final prewarm = playerSource.indexOf(
      '_ensureExclusiveOutput(start: true)',
      setter,
    );
    expect(setter, greaterThanOrEqualTo(0));
    expect(prewarm, greaterThan(setter));
  });

  test('every library startup path initializes playback before navigation', () {
    final updating = _source('lib/page/updating_page.dart');
    final restore = updating.indexOf(
      'PlayService.instance.playbackService.restoreLastSessionOnce()',
    );
    final existingLibraryNavigation = updating.indexOf('context.go(', restore);
    expect(restore, greaterThanOrEqualTo(0));
    expect(existingLibraryNavigation, greaterThan(restore));

    final welcoming = _source('lib/page/welcoming_page.dart');
    final initialize = welcoming.indexOf(
      'PlayService.instance.ensurePlaybackInitialized()',
    );
    final firstLibraryNavigation = welcoming.indexOf('context.go(', initialize);
    expect(initialize, greaterThanOrEqualTo(0));
    expect(firstLibraryNavigation, greaterThan(initialize));
  });
}
