import 'package:dan_player/search/settings_search_index.dart';
import 'package:dan_player/search/audio_search_index.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:desktop_lyric/l10n/ui_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('settings titles and Chinese keywords have all four translations', () {
    for (final entry in settingsSearchEntries) {
      for (final label in entry.labels) {
        if (!RegExp(r'[\u3400-\u9fff]').hasMatch(label)) continue;
        expect(uiCatalog[label], hasLength(3), reason: label);
        expect(
            uiCatalog[label]!.every((text) => text.trim().isNotEmpty), isTrue);
      }
    }
  });
  for (final language in UiLanguage.values) {
    test(
        'settings lookup in ${language.name} finds correct destination independent of UI language',
        () {
      final before = uiLanguage.value;
      for (final entry in settingsSearchEntries) {
        final query = translateUi(entry.title, language);
        expect(searchSettings(query).map((e) => e.id), contains(entry.id),
            reason: query);
        final location = Uri.parse(entry.location);
        expect(location.queryParameters['setting'], entry.id);
        expect(location.queryParameters['section'], entry.section);
      }
      expect(uiLanguage.value, before);
      final direct = translateUi('直连', language);
      expect(searchSettings(direct).map((entry) => entry.id),
          contains('network-proxy'),
          reason: direct);
      for (final preset in ['一键省电', '一键高性能', '恢复原设置']) {
        final translated = translateUi(preset, language);
        expect(searchSettings(translated).map((entry) => entry.id),
            contains('performance'),
            reason: translated);
      }
      expect(searchSettings('  '), isEmpty);
    });
  }
  for (final text in ['中文歌曲', 'ENGLISH Song', '日本語の曲', '한국어 노래']) {
    test('library title artist album supports $text', () async {
      final audio = Audio(text, text, text, 1, 120, null, null,
          'J:/fixture/$text.mp3', 0, 0, null);
      final library = AudioLibrary.instance;
      library.audioCollection
        ..clear()
        ..add(audio);
      library.artistCollection
        ..clear()
        ..[text] = (Artist(name: text)..works.add(audio));
      library.albumCollection
        ..clear()
        ..[text] = (Album(name: text)..works.add(audio));
      AudioLibrary.searchRevision++;
      final result =
          await AudioSearchIndex.instance.searchAll(text.toLowerCase());
      expect(result.audios.single, audio);
      expect(result.artists.single.name, text);
      expect(result.albums.single.name, text);
    });
  }
}
