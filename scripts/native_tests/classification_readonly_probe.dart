// Explicit opt-in integration probe, intentionally outside the default tests.
// Reads source tags/lyrics only. Never constructs AppSettings/AudioLibrary,
// calls index builders, writes media, or prints paths/lyrics.
import 'dart:convert';
import 'dart:io';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/music_categories.dart';
import 'package:dan_player/src/rust/api/tag_reader.dart' as tags;
import 'package:dan_player/src/rust/frb_generated.dart';
import 'package:dan_player/statistics/library_statistics.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  final root = Platform.environment['DAN_PLAYER_CLASSIFICATION_ROOT'];
  final nativeLibrary = Platform.environment['DAN_PLAYER_CLASSIFICATION_DLL'];
  test('real local library read-only classification agreement', () async {
    if (root == null || nativeLibrary == null) return;
    // Run the same scoped read-only commands in the command host; do not
    // change the machine's .ps1 execution-policy configuration.
    final descriptorCommands = await File(path.join(Directory.current.path,
            'scripts', 'read_classification_windows_fallback.ps1'))
        .readAsString();
    final descriptorProcess = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          descriptorCommands,
        ],
        environment: {'DAN_PLAYER_CLASSIFICATION_ROOT': root},
        stdoutEncoding: utf8,
        stderrEncoding: utf8);
    expect(descriptorProcess.exitCode, 0,
        reason: 'Read-only metadata subprocess must complete successfully');
    final extracted =
        jsonDecode(descriptorProcess.stdout as String) as Map<String, dynamic>;
    // Windows PowerShell 5 preserves ConvertFrom-Json array wrappers as
    // {value: [...], Count: n}; PowerShell 7 emits the bare JSON array.
    final rawDescriptors = extracted['descriptors'];
    final parsed = rawDescriptors is List
        ? rawDescriptors
        : (rawDescriptors as Map<String, dynamic>)['value'] as List;
    final audios = parsed
        .map((value) => _ReadOnlyAudio(value as Map<String, dynamic>))
        .toList();
    if (Platform.environment['DAN_PLAYER_CLASSIFICATION_METADATA_AUDIT'] ==
        '1') {
      _auditMetadataOnly(audios);
      return;
    }
    await RustLib.init(externalLibrary: ExternalLibrary.open(nativeLibrary));
    var nativeReads = 0;
    var nativeNonEmptyLyrics = 0;
    final reader =
        LocalClassificationLyricsReader(readEmbeddedLyrics: (source) async {
      nativeReads++;
      final result = await tags.getLyricFromPath(path: source);
      if (result?.trim().isNotEmpty == true) nativeNonEmptyLyrics++;
      return result;
    });
    final clock = Stopwatch()..start();
    final snapshot =
        await MusicClassificationScanner(readLyrics: reader.call).scan(audios);
    final categoryElapsed = clock.elapsedMilliseconds;
    final nativeAfterCategories = nativeReads;
    final categories = MusicCategories(audios,
        artistSplitPattern: r'[/、；;]', classifications: snapshot);
    final statistics =
        await LibraryStatisticsScanner(readLyrics: reader.call).scan(audios);
    final languageCounts = {
      for (final language in SongLanguage.values)
        language.label: categories
            .groups(MusicCategoryKind.language)
            .where((group) => group.title == language.label)
            .fold<int>(0, (count, group) => count + group.audios.length)
    };
    final statisticsCounts = {
      for (final language in SongLanguage.values)
        language.label: statistics.languageCounts[language] ?? 0
    };
    final categoryEvidence = {
      for (final evidence in ClassificationEvidence.values)
        if (evidence != ClassificationEvidence.fallback)
          evidence.label: audios
              .where((audio) =>
                  snapshot.forAudio(audio).languageEvidence == evidence)
              .length
    };
    final statisticsEvidence = {
      '标签': statistics.taggedTracks,
      '歌词': statistics.lyricTracks,
      '推断': statistics.metadataInferredTracks,
      '未知': statistics.languageCounts[SongLanguage.unknown] ?? 0,
    };
    final composerEvidence = {
      for (final evidence in ClassificationEvidence.values)
        if (evidence != ClassificationEvidence.inferred)
          evidence.label: audios
              .where((audio) =>
                  snapshot.forAudio(audio).composer.evidence == evidence)
              .length
    };
    expect(languageCounts, statisticsCounts);
    expect(categoryEvidence, statisticsEvidence);
    expect(statistics.totalTracks, audios.length);
    expect(statistics.missingLocalTracks, 0);
    expect(statistics.inaccessibleLocalTracks, 0);
    expect(nativeReads, nativeAfterCategories,
        reason: 'second scanner must reuse verified cached lyric reads');
    // This is the only output containing derived source-library data.
    // ignore: avoid_print
    print('READ_ONLY_CLASSIFICATION_QA ${jsonEncode({
          'tracks': audios.length,
          'windowsArtistRecoveries': extracted['windowsArtistRecoveries'],
          'windowsReadFailures': extracted['windowsReadFailures'],
          'languageCategories': languageCounts,
          'languageStatistics': statisticsCounts,
          'categoryEvidence': categoryEvidence,
          'statisticsEvidence': statisticsEvidence,
          'composerEvidence': composerEvidence,
          'nativeReads': nativeReads,
          'nativeNonEmptyLyrics': nativeNonEmptyLyrics,
          'secondScanNativeReads': nativeReads - nativeAfterCategories,
          'categoryMilliseconds': categoryElapsed,
          'statisticsMilliseconds': clock.elapsedMilliseconds - categoryElapsed,
          'totalBytes': statistics.totalLocalBytes,
        })}');
    RustLib.dispose();
  },
      skip: root == null || nativeLibrary == null,
      timeout: const Timeout(Duration(minutes: 3)));
}

void _auditMetadataOnly(List<_ReadOnlyAudio> audios) {
  const snapshot = MusicClassificationSnapshot.empty();
  final unknown = audios
      .where((audio) =>
          snapshot.forAudio(audio).language.language == SongLanguage.unknown)
      .toList();
  final reasons = <String, int>{};
  final filenameCandidates = <Map<String, String>>[];
  var kanaOrHangulUnknown = 0;
  String scripts(String text) {
    return [
      if (RegExp(r'[\u3400-\u9fff]').hasMatch(text)) 'Han',
      if (RegExp(r'[A-Za-z]').hasMatch(text)) 'Latin',
      if (RegExp(r'[\u3041-\u30fa\uff66-\uff9d]').hasMatch(text)) 'Kana',
      if (RegExp(r'[\uac00-\ud7a3\u1100-\u11ff\u3131-\u318e]').hasMatch(text))
        'Hangul',
    ].join('/');
  }

  final examples = <String, Map<String, String>>{};
  for (final audio in unknown) {
    final fromFilename = audio.title == path.basename(audio.path);
    final titleScripts = scripts(audio.title);
    final otherScripts =
        scripts('${audio.composer ?? audio.artist} ${audio.album}');
    if ('$titleScripts/$otherScripts'.contains('Kana') ||
        '$titleScripts/$otherScripts'.contains('Hangul')) {
      kanaOrHangulUnknown++;
    }
    final reason =
        '${fromFilename ? 'filename' : 'tag'} title $titleScripts / credits-album $otherScripts';
    reasons.update(reason, (value) => value + 1, ifAbsent: () => 1);
    examples.putIfAbsent(
        reason,
        () => {
              'title': audio.title,
              'artist': audio.artist,
              'album': audio.album
            });
    if (fromFilename) {
      final normalized = classifyMusicMetadata(
        title: path.basenameWithoutExtension(audio.path),
        artist: audio.artist,
        composer: audio.composer,
        album: audio.album,
        language: audio.language,
      );
      if (normalized.language.language != SongLanguage.unknown) {
        filenameCandidates.add({
          'title': audio.title,
          'resultAfterExtensionRemoval': normalized.language.language.label
        });
      }
    }
  }
  // ignore: avoid_print
  print('READ_ONLY_METADATA_AUDIT ${jsonEncode({
        'tracks': audios.length,
        'metadataOnlyUnknownLanguage': unknown.length,
        'unknownWithKanaOrHangul': kanaOrHangulUnknown,
        'unknownLanguageReasons': reasons,
        'filenameExtensionNormalizationCandidates': filenameCandidates.length,
        'filenameExamples': filenameCandidates.take(3).toList(),
        'reasonExamples': examples.values.take(5).toList(),
        'metadataOnlyUnknownComposer': audios
            .where((audio) => snapshot.forAudio(audio).composer.value == null)
            .length,
      })}');
}

/// Implements only the frozen metadata consumed by these read-only projections.
/// Avoid Audio's constructor, which consults the AppSettings singleton.
class _ReadOnlyAudio implements Audio {
  _ReadOnlyAudio(Map<String, dynamic> value)
      : title = value['title'] as String,
        artist = value['artist'] as String,
        album = value['album'] as String,
        composer = value['composer'] as String?,
        albumArtist = value['album_artist'] as String?,
        language = value['language'] as String?,
        path = value['path'] as String;

  @override
  String title;
  @override
  String artist;
  @override
  String album;
  @override
  String? composer;
  @override
  String? albumArtist;
  @override
  String? language;
  @override
  String path;
  @override
  bool get isOnline => false;
  @override
  bool get isLocal => true;
  @override
  String? get onlineProvider => null;
  @override
  String? get onlineId => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
