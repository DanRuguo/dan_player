import 'dart:io';
import 'dart:math' as math;

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/lyric_text_codec.dart';
import 'package:dan_player/src/rust/api/tag_reader.dart' as tag_reader;
import 'package:path/path.dart' as path;

enum SongLanguage {
  chinese('中文'),
  english('英文'),
  japanese('日文'),
  korean('韩文'),
  other('其他语言'),
  unknown('未识别');

  const SongLanguage(this.label);
  final String label;
}

enum LanguageEvidence { tag, lyrics, title, metadata, unknown }

class SongLanguageClassification {
  const SongLanguageClassification(this.language, this.evidence);

  final SongLanguage language;
  final LanguageEvidence evidence;

  bool get isInferred =>
      evidence == LanguageEvidence.lyrics ||
      evidence == LanguageEvidence.title ||
      evidence == LanguageEvidence.metadata;
}

/// Describes text evidence, not the language heard in the audio. Inferred
/// classifications must always remain distinguishable from embedded tags.
SongLanguageClassification classifySongLanguage({
  String? languageTag,
  String? lyrics,
  required String title,
  String? composer,
  String? album,
  bool useMetadataFallback = false,
}) {
  final tagged = _languageFromTag(languageTag);
  if (tagged != null) {
    return SongLanguageClassification(tagged, LanguageEvidence.tag);
  }

  if (lyrics != null && lyrics.trim().isNotEmpty) {
    final lyricTag = RegExp(
      r'^\s*\[(?:lang|language):\s*([^\]]+)\]',
      caseSensitive: false,
      multiLine: true,
    ).firstMatch(lyrics);
    final declared = _languageFromTag(lyricTag?.group(1));
    final text = _originalLyricText(lyrics);
    final inferred = declared ?? _languageFromText(text, allowEnglish: true);
    if (inferred != null) {
      return SongLanguageClassification(inferred, LanguageEvidence.lyrics);
    }
  }

  if (useMetadataFallback) {
    final metadata = _languageFromMetadata(title, composer, album);
    return SongLanguageClassification(
      metadata,
      metadata == SongLanguage.unknown
          ? LanguageEvidence.unknown
          : LanguageEvidence.metadata,
    );
  }
  final fromTitle = _languageFromText(title, allowEnglish: false);
  if (fromTitle != null) {
    return SongLanguageClassification(fromTitle, LanguageEvidence.title);
  }
  return const SongLanguageClassification(
    SongLanguage.unknown,
    LanguageEvidence.unknown,
  );
}

final _lyricTimestamp = RegExp(r'\[(\d+):(\d+(?:\.\d+)?)\]');
final _lyricCredit = RegExp(
  r'^(?:作词|作詞|填词|填詞|作曲|词曲|詞曲|编曲|編曲|曲|词|詞|演唱|歌手|'
  r'制作人|製作人|混音|母带|母帶|录音|錄音|翻译|翻譯|译文|譯文|'
  r'composer|composed\s+by|music\s+by|lyrics?\s+by|arranged\s+by|'
  r'translat(?:ion|ed\s+by)|vocal|singer|作曲者|작곡|작사)\s*[:：]',
  caseSensitive: false,
);

/// LRC convention: the first row at a timestamp is the original; following
/// rows are translations/romanization. Keep that order instead of pooling all
/// scripts. Inline // translations and explicit credits are not sung evidence.
/// This remains an inference, never a claim to have recognized the audio.
String _originalLyricText(String lyrics) {
  final lines = <String>[];
  final seenTimes = <int>{};
  for (final raw in lyrics.split(RegExp(r'\r?\n'))) {
    final timestamps = _lyricTimestamp.allMatches(raw).toList();
    final text = raw
        .replaceAll(RegExp(r'\[[^\]]*\]'), '')
        .replaceAll(RegExp(r'<[\d:.]+>'), '')
        .split(RegExp(r'\s*//\s*'))
        .first
        .trim();
    if (text.isEmpty || _lyricCredit.hasMatch(text)) continue;
    // Metadata-only LRC lines are not part of the lyric body.
    if (timestamps.isEmpty && RegExp(r'^\s*\[[^\]]+:').hasMatch(raw)) {
      continue;
    }
    if (timestamps.isNotEmpty) {
      final times = timestamps
          .map((match) => (int.parse(match.group(1)!) * 60000 +
                  double.parse(match.group(2)!) * 1000)
              .round())
          .toSet();
      if (times.every(seenTimes.contains)) continue;
      seenTimes.addAll(times);
    }
    lines.add(text);
  }
  return lines.join('\n');
}

SongLanguage? _languageFromTag(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final values = value.toLowerCase().trim().split(RegExp(r'[,;/|+\x00]+'));
  final languages = <SongLanguage>{};
  for (final item in values) {
    final normalized = item.trim().replaceAll('_', '-');
    if (normalized.isEmpty) continue;
    final language = _languageFromSingleTag(normalized);
    // A partially understood multi-language tag is not reliable evidence.
    if (language == null) return null;
    languages.add(language);
  }
  if (languages.isEmpty) return null;
  return languages.length == 1 ? languages.single : SongLanguage.other;
}

SongLanguage? _languageFromSingleTag(String value) {
  // ISO 639-1/2/3 and common human-readable language tag values. A locale's
  // region is not used to guess the language (e.g. en-JP remains English).
  final primary = value.split('-').first;
  const chinese = {
    'zh',
    'zho',
    'chi',
    'cmn',
    'yue',
    'nan',
    'hak',
    'wuu',
    'chinese',
    'mandarin',
    'cantonese',
    '中文',
    '汉语',
    '漢語',
    '普通话',
    '普通話',
    '国语',
    '國語',
    '粤语',
    '粵語',
  };
  const english = {'en', 'eng', 'english', '英语', '英語', '英文'};
  const japanese = {'ja', 'jpn', 'japanese', '日本語', '日语', '日語', '日文'};
  const korean = {'ko', 'kor', 'korean', '한국어', '韩语', '韓語', '韩文', '韓文'};
  if (chinese.contains(primary)) return SongLanguage.chinese;
  if (english.contains(primary)) return SongLanguage.english;
  if (japanese.contains(primary)) return SongLanguage.japanese;
  if (korean.contains(primary) || korean.contains(value)) {
    return SongLanguage.korean;
  }

  const otherCodes = {
    'af',
    'afr',
    'am',
    'amh',
    'ar',
    'ara',
    'az',
    'aze',
    'be',
    'bel',
    'bg',
    'bul',
    'bn',
    'ben',
    'bo',
    'bod',
    'tib',
    'bs',
    'bos',
    'ca',
    'cat',
    'cs',
    'ces',
    'cze',
    'cy',
    'cym',
    'wel',
    'da',
    'dan',
    'de',
    'deu',
    'ger',
    'el',
    'ell',
    'gre',
    'es',
    'spa',
    'et',
    'est',
    'eu',
    'eus',
    'baq',
    'fa',
    'fas',
    'per',
    'fi',
    'fin',
    'fil',
    'fo',
    'fao',
    'fr',
    'fra',
    'fre',
    'ga',
    'gle',
    'gl',
    'glg',
    'gu',
    'guj',
    'he',
    'heb',
    'hi',
    'hin',
    'hr',
    'hrv',
    'hu',
    'hun',
    'hy',
    'hye',
    'arm',
    'id',
    'ind',
    'is',
    'isl',
    'ice',
    'it',
    'ita',
    'ka',
    'kat',
    'geo',
    'kk',
    'kaz',
    'km',
    'khm',
    'kn',
    'kan',
    'ku',
    'kur',
    'ky',
    'kir',
    'la',
    'lat',
    'lo',
    'lao',
    'lt',
    'lit',
    'lv',
    'lav',
    'mi',
    'mri',
    'mao',
    'mk',
    'mkd',
    'mac',
    'ml',
    'mal',
    'mn',
    'mon',
    'mr',
    'mar',
    'ms',
    'msa',
    'may',
    'mt',
    'mlt',
    'my',
    'mya',
    'bur',
    'ne',
    'nep',
    'nl',
    'nld',
    'dut',
    'no',
    'nor',
    'nb',
    'nob',
    'nn',
    'nno',
    'pa',
    'pan',
    'pl',
    'pol',
    'ps',
    'pus',
    'pt',
    'por',
    'ro',
    'ron',
    'rum',
    'ru',
    'rus',
    'sa',
    'san',
    'si',
    'sin',
    'sk',
    'slk',
    'slo',
    'sl',
    'slv',
    'sq',
    'sqi',
    'alb',
    'sr',
    'srp',
    'sv',
    'swe',
    'sw',
    'swa',
    'ta',
    'tam',
    'te',
    'tel',
    'th',
    'tha',
    'tl',
    'tgl',
    'tr',
    'tur',
    'uk',
    'ukr',
    'ur',
    'urd',
    'uz',
    'uzb',
    'vi',
    'vie',
    'yi',
    'yid',
    'zu',
    'zul',
    'mul',
    'zxx',
  };
  const otherNames = {
    '法语',
    '法語',
    '德语',
    '德語',
    '俄语',
    '俄語',
    '西班牙语',
    '西班牙語',
    'french',
    'français',
    'german',
    'deutsch',
    'spanish',
    'español',
    'italian',
    'portuguese',
    'russian',
    'arabic',
    'hindi',
    'thai',
    'vietnamese',
    'indonesian',
    'swedish',
    'dutch',
    'turkish',
    'multilingual',
    '多语言',
    '多語言',
    '多语种',
    'instrumental',
    '纯音乐',
    '純音樂',
    '无语言',
    '無語言',
  };
  return otherCodes.contains(primary) || otherNames.contains(value)
      ? SongLanguage.other
      : null;
}

SongLanguage? _languageFromText(String text, {required bool allowEnglish}) {
  var kana = 0;
  var hangul = 0;
  var otherScript = 0;
  var bopomofo = 0;
  var han = 0;
  for (final rune in text.runes) {
    if ((rune >= 0x3041 && rune <= 0x3096) ||
        (rune >= 0x30a1 && rune <= 0x30fa) ||
        (rune >= 0xff66 && rune <= 0xff9d)) {
      kana++;
    } else if ((rune >= 0x3105 && rune <= 0x312f) ||
        (rune >= 0x31a0 && rune <= 0x31bf)) {
      bopomofo++;
    } else if ((rune >= 0x3400 && rune <= 0x9fff) ||
        (rune >= 0x20000 && rune <= 0x323af)) {
      han++;
    } else if ((rune >= 0xac00 && rune <= 0xd7a3) ||
        (rune >= 0x1100 && rune <= 0x11ff) ||
        (rune >= 0x3131 && rune <= 0x318e)) {
      hangul++;
    } else if ((rune >= 0x0400 && rune <= 0x052f) ||
        (rune >= 0x0620 && rune <= 0x064a) ||
        (rune >= 0x05d0 && rune <= 0x05ea) ||
        (rune >= 0x0904 && rune <= 0x0939) ||
        (rune >= 0x0e01 && rune <= 0x0e2e) ||
        (rune >= 0x0391 && rune <= 0x03c9)) {
      otherScript++;
    }
  }
  if (kana >= 2 && hangul >= 2) return SongLanguage.other;
  if (otherScript >= 2) return SongLanguage.other;
  if (kana >= 2) return SongLanguage.japanese;
  if (hangul >= 2) return SongLanguage.korean;
  if (bopomofo >= 2) return SongLanguage.chinese;
  // Substantial Han-only original lyric text is useful Chinese evidence, but
  // a short title/credit is not. Latin translations are never pooled into it.
  if (allowEnglish && han >= 12 && !RegExp(r'[A-Za-z]').hasMatch(text)) {
    return SongLanguage.chinese;
  }
  // Do not classify a translation alongside Han lyrics as the vocal language.
  if (!allowEnglish || han > 0 || kana > 0 || hangul > 0 || otherScript > 0) {
    return null;
  }

  final words = RegExp(r"[a-z]+(?:'[a-z]+)?")
      .allMatches(text.toLowerCase())
      .map((match) => match.group(0)!)
      .toList();
  if (words.length < 20) return null;
  const englishMarkers = {
    'the',
    'and',
    'you',
    'your',
    'my',
    'we',
    'our',
    'they',
    'their',
    'are',
    'was',
    'were',
    'this',
    'that',
    'with',
    'without',
    'not',
    "don't",
    "doesn't",
    "it's",
    'have',
    'has',
    'will',
    'would',
    "can't",
    'from',
    'there',
    'when',
    'what',
    'where',
  };
  final matches = words.where(englishMarkers.contains).toList();
  if (matches.toSet().length >= 5 && matches.length / words.length >= 0.25) {
    return SongLanguage.english;
  }
  return null;
}

enum _MetadataScript { latin, han, kana, hangul, other }

SongLanguage _languageFromMetadata(
  String title,
  String? composer,
  String? album,
) {
  final titleScripts = _metadataScripts(title);
  // A filename/blank placeholder is not enough evidence to classify a song.
  // The composer argument is explicit composition metadata, or the contributing
  // artist fallback chosen by classifyMusicMetadata under the broad policy.
  // Missing fields stay neutral; all such text remains inferred evidence and
  // mixed Han/Latin metadata does not establish an "other" vocal language.
  if (titleScripts == null) return SongLanguage.unknown;
  final fields = <Set<_MetadataScript>>[
    titleScripts,
    if (_metadataScripts(composer) case final value?) value,
    if (_metadataScripts(album) case final value?) value,
  ];
  final scripts = <_MetadataScript>{
    for (final field in fields) ...field,
  };

  final japanese = scripts.contains(_MetadataScript.kana);
  final korean = scripts.contains(_MetadataScript.hangul);
  final other = scripts.contains(_MetadataScript.other);
  if ((japanese && korean) || (other && (japanese || korean))) {
    return SongLanguage.other;
  }
  if (japanese) return SongLanguage.japanese;
  if (korean) return SongLanguage.korean;
  if (other) return SongLanguage.other;

  // A Han-only main title remains useful Chinese *text* inference even if the
  // contributing artist has a Latin stage name or the album contains "OST".
  // Kana/Hangul/other-script evidence above still takes precedence, and a mixed
  // Han/Latin main title is not promoted by this rule.
  if (titleScripts.length == 1 && titleScripts.contains(_MetadataScript.han)) {
    return SongLanguage.chinese;
  }

  if (fields.length >= 2 &&
      fields.every((field) =>
          field.length == 1 && field.contains(_MetadataScript.latin))) {
    return SongLanguage.english;
  }
  // A Latin title alone is not English evidence. Mixed Han/Latin is common in
  // credits/releases and does not establish a different or multilingual song.
  return SongLanguage.unknown;
}

Set<_MetadataScript>? _metadataScripts(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty || _isMetadataPlaceholder(text)) return null;
  final scripts = <_MetadataScript>{};
  for (final rune in text.runes) {
    if ((rune >= 0x41 && rune <= 0x5a) ||
        (rune >= 0x61 && rune <= 0x7a) ||
        (rune >= 0x00c0 &&
            rune <= 0x024f &&
            rune != 0x00d7 &&
            rune != 0x00f7) ||
        (rune >= 0x1e00 && rune <= 0x1eff)) {
      scripts.add(_MetadataScript.latin);
    } else if ((rune >= 0x3041 && rune <= 0x3096) ||
        (rune >= 0x30a1 && rune <= 0x30fa) ||
        (rune >= 0xff66 && rune <= 0xff9d)) {
      scripts.add(_MetadataScript.kana);
    } else if ((rune >= 0xac00 && rune <= 0xd7a3) ||
        (rune >= 0x1100 && rune <= 0x11ff) ||
        (rune >= 0x3131 && rune <= 0x318e)) {
      scripts.add(_MetadataScript.hangul);
    } else if ((rune >= 0x3400 && rune <= 0x9fff) ||
        (rune >= 0x20000 && rune <= 0x323af)) {
      scripts.add(_MetadataScript.han);
    } else if ((rune >= 0x0370 && rune <= 0x052f) ||
        (rune >= 0x0590 && rune <= 0x08ff) ||
        (rune >= 0x0900 && rune <= 0x0dff) ||
        (rune >= 0x0e00 && rune <= 0x0e7f)) {
      scripts.add(_MetadataScript.other);
    }
  }
  return scripts.isEmpty ? null : scripts;
}

bool _isMetadataPlaceholder(String value) {
  final normalized = value.trim().toLowerCase();
  return const {
    'unknown',
    '未知',
    '未识别',
    '未識別',
    '未知作曲家',
    'unknown composer',
    'n/a',
    'null',
    '-',
    '--',
  }.contains(normalized);
}

enum ClassificationEvidence {
  tag('标签'),
  lyrics('歌词'),
  fallback('艺术家回退'),
  inferred('推断'),
  unknown('未知');

  const ClassificationEvidence(this.label);
  final String label;
}

class SongComposerClassification {
  const SongComposerClassification(this.value, this.evidence);
  final String? value;
  final ClassificationEvidence evidence;
}

/// The broad composer browser includes contributing artists at the user's
/// request. Keep that fallback visibly distinct from actual composer credits.
SongComposerClassification classifySongComposer({
  String? composerTag,
  String? lyrics,
  String? artist,
}) {
  final tag = composerTag?.trim();
  if (tag != null && tag.isNotEmpty && !_isMetadataPlaceholder(tag)) {
    return SongComposerClassification(tag, ClassificationEvidence.tag);
  }
  final names = <String>{};
  final credit = RegExp(
    r'^(?:作曲(?:者)?|词曲|詞曲|曲|composer|composed\s+by|music\s+by|composition|작곡)'
    r'\s*[:：]\s*(.+)$',
    caseSensitive: false,
  );
  for (final line in (lyrics ?? '').split(RegExp(r'\r?\n'))) {
    var text = line.replaceAll(_lyricTimestamp, '').trim();
    if (text.startsWith('[') && text.endsWith(']')) {
      text = text.substring(1, text.length - 1).trim();
    }
    final match = credit.firstMatch(text);
    if (match == null) continue;
    final name = match.group(1)!.trim();
    if (name.isEmpty ||
        name.length > 200 ||
        _isMetadataPlaceholder(name) ||
        RegExp(r'https?://|www\.|[:：]').hasMatch(name)) {
      continue;
    }
    names.add(name);
  }
  if (names.isNotEmpty) {
    return SongComposerClassification(
        names.join(' / '), ClassificationEvidence.lyrics);
  }
  final contributor = artist?.trim();
  if (contributor != null &&
      contributor.isNotEmpty &&
      !_isMetadataPlaceholder(contributor)) {
    return SongComposerClassification(
        contributor, ClassificationEvidence.fallback);
  }
  return const SongComposerClassification(null, ClassificationEvidence.unknown);
}

class SongClassification {
  const SongClassification({required this.language, required this.composer});
  final SongLanguageClassification language;
  final SongComposerClassification composer;

  ClassificationEvidence get languageEvidence => switch (language.evidence) {
        LanguageEvidence.tag => ClassificationEvidence.tag,
        LanguageEvidence.lyrics => ClassificationEvidence.lyrics,
        LanguageEvidence.title ||
        LanguageEvidence.metadata =>
          ClassificationEvidence.inferred,
        LanguageEvidence.unknown => ClassificationEvidence.unknown,
      };
}

SongClassification classifyMusicMetadata({
  required String title,
  String? filePath,
  String? album,
  String? composer,
  String? artist,
  String? language,
  String? lyrics,
}) {
  final composerResult = classifySongComposer(
      composerTag: composer, lyrics: lyrics, artist: artist);
  return SongClassification(
    language: classifySongLanguage(
      title: _classificationTitle(title, filePath),
      album: album,
      // Contributing artists are usable text evidence under the broad policy,
      // but remain metadata inference, never an embedded language tag.
      composer: composerResult.value,
      languageTag: language,
      lyrics: lyrics,
      useMetadataFallback: true,
    ),
    composer: composerResult,
  );
}

String _classificationTitle(String title, String? filePath) {
  final value = title.trim();
  if (filePath == null ||
      RegExp(r'^[a-z][a-z0-9+.-]*://', caseSensitive: false)
          .hasMatch(filePath)) {
    return value;
  }
  // Native metadata readers use the complete filename when a title tag is
  // absent. Container extensions such as .mp3 are not Latin language evidence.
  final filePaths = path.Context(style: path.Style.windows);
  final filename = filePaths.basename(filePath);
  if (value.isEmpty || _isMetadataPlaceholder(value) || value == filename) {
    return filePaths.basenameWithoutExtension(filePath).trim();
  }
  return value;
}

typedef _ClassificationIdentity = (
  String,
  String,
  String?,
  String,
  String?,
  bool,
  String
);

_ClassificationIdentity _classificationIdentity(Audio audio) => (
      audio.path,
      audio.title,
      audio.composer,
      audio.album,
      audio.language,
      audio.isOnline ||
          RegExp(r'^(?:online|https?)://', caseSensitive: false)
              .hasMatch(audio.path),
      audio.artist,
    );

SongClassification _classifyIdentity(_ClassificationIdentity value,
        [String? lyrics]) =>
    classifyMusicMetadata(
      title: value.$2,
      filePath: value.$1,
      composer: value.$3,
      artist: value.$7,
      album: value.$4,
      language: value.$5,
      lyrics: lyrics,
    );

/// Read-only derived data. No Audio object, embedded tag, lyric or index is
/// modified; a changed descriptor automatically falls back until refreshed.
class MusicClassificationSnapshot {
  const MusicClassificationSnapshot.empty() : _entries = const {};
  MusicClassificationSnapshot._(
      Map<_ClassificationIdentity, SongClassification> entries)
      : _entries = Map.unmodifiable(entries);

  final Map<_ClassificationIdentity, SongClassification> _entries;

  SongClassification forAudio(Audio audio) {
    final identity = _classificationIdentity(audio);
    return _entries[identity] ?? _classifyIdentity(identity);
  }
}

class MusicClassificationScanner {
  MusicClassificationScanner({LocalLyricsReader? readLyrics})
      : _readLyrics = readLyrics ?? readLocalClassificationLyrics;

  static final shared = MusicClassificationScanner();
  final LocalLyricsReader _readLyrics;

  Future<MusicClassificationSnapshot> scan(
    Iterable<Audio> audios, {
    bool includeComposer = true,
    bool Function()? isCancelled,
    void Function(int completed, int total)? onProgress,
  }) async {
    void checkCancelled() {
      if (isCancelled?.call() == true) throw const LibraryScanCancelled();
    }

    checkCancelled();
    final tracks = audios.map(_classificationIdentity).toSet().toList();
    final entries = <_ClassificationIdentity, SongClassification>{};
    for (var offset = 0; offset < tracks.length; offset += 8) {
      checkCancelled();
      final batch = tracks.skip(offset).take(8);
      final results = await Future.wait(batch.map((track) async {
        String? lyrics;
        // Language browsing must not read every lyric merely because the
        // hidden legacy composer projection is missing a tag. Statistics and
        // explicit composer deep links keep the former behaviour by leaving
        // [includeComposer] enabled.
        final needsLanguageLyrics = _languageFromTag(track.$5) == null;
        final needsComposerLyrics = includeComposer &&
            classifySongComposer(composerTag: track.$3).value == null;
        if (!track.$6 && (needsLanguageLyrics || needsComposerLyrics)) {
          try {
            lyrics = await _readLyrics(track.$1);
          } catch (_) {
            // Optional local evidence cannot invalidate a library descriptor.
          }
        }
        checkCancelled();
        return (track, _classifyIdentity(track, lyrics));
      }));
      for (final result in results) {
        entries[result.$1] = result.$2;
      }
      onProgress?.call(math.min(offset + 8, tracks.length), tracks.length);
    }
    checkCancelled();
    return MusicClassificationSnapshot._(entries);
  }
}

/// The same bounded local reader is used by categories and statistics. Sidecar
/// edits take precedence, otherwise use the existing native embedded-lyric API.
/// It never requests online lyrics, writes files, or persists inferred metadata.
Future<String?> readLocalClassificationLyrics(String audioPath) =>
    _sharedClassificationLyricsReader.call(audioPath);

final _sharedClassificationLyricsReader = LocalClassificationLyricsReader();

typedef _LyricSourceSignature = (int, int, int, int);

class _CachedClassificationLyrics {
  const _CachedClassificationLyrics(this.signature, this.text, this.readAt);
  final _LyricSourceSignature signature;
  final String? text;
  final DateTime readAt;
  int get bytes => (text?.length ?? 0) * 2;
}

/// Process-local LRU: no cache files or user settings are written. Every hit
/// first validates audio AND sidecar size/mtime. Identical in-flight source
/// reads are shared across statistics, category pages and deep links.
class LocalClassificationLyricsReader {
  LocalClassificationLyricsReader({
    LocalLyricsReader? readEmbeddedLyrics,
    this.maximumEntries = 1024,
    this.maximumBytes = 4 * 1024 * 1024,
    this.negativeCacheLifetime = const Duration(seconds: 30),
    DateTime Function()? now,
  })  : _readEmbedded = readEmbeddedLyrics ?? _readNativeLyrics,
        _now = now ?? DateTime.now;

  final LocalLyricsReader _readEmbedded;
  final int maximumEntries;
  final int maximumBytes;
  final Duration negativeCacheLifetime;
  final DateTime Function() _now;
  final _cache = <String, _CachedClassificationLyrics>{};
  final _pending = <(String, _LyricSourceSignature), Future<String?>>{};
  var _cachedBytes = 0;
  static const _limit = 256 * 1024;

  static Future<String?> _readNativeLyrics(String audioPath) =>
      tag_reader.getLyricFromPath(path: audioPath);

  Future<String?> call(String audioPath) async {
    if (RegExp(r'^[a-z][a-z0-9+.-]*://', caseSensitive: false)
        .hasMatch(audioPath)) {
      return null;
    }
    try {
      final source = path.normalize(path.absolute(audioPath));
      final key = Platform.isWindows ? source.toLowerCase() : source;
      final sidecar = path.setExtension(source, '.lrc');
      final stats =
          await Future.wait([File(source).stat(), File(sidecar).stat()])
              .timeout(const Duration(seconds: 3));
      if (stats.first.type != FileSystemEntityType.file) {
        _remove(key);
        return null;
      }
      final hasSidecar = stats.last.type == FileSystemEntityType.file;
      final signature = (
        stats.first.size,
        stats.first.modified.microsecondsSinceEpoch,
        hasSidecar ? stats.last.size : -1,
        hasSidecar ? stats.last.modified.microsecondsSinceEpoch : -1,
      );
      final cached = _cache[key];
      if (cached != null &&
          cached.signature == signature &&
          (cached.text != null ||
              _now().difference(cached.readAt) < negativeCacheLifetime)) {
        // Move a verified hit to the most-recently-used position.
        _cache.remove(key);
        _cache[key] = cached;
        return cached.text;
      }
      _remove(key);
      final request = (key, signature);
      final inFlight = _pending[request];
      if (inFlight != null) return await inFlight;
      final reading = _load(source, sidecar, key, signature);
      _pending[request] = reading;
      try {
        return await reading;
      } finally {
        if (identical(_pending[request], reading)) _pending.remove(request);
      }
    } catch (_) {
      // A permission error, timeout or native initialization failure is not
      // cached. A later explicit refresh can recover immediately.
      return null;
    }
  }

  Future<String?> _load(String source, String sidecar, String key,
      _LyricSourceSignature signature) async {
    String? text;
    if (signature.$3 >= 0) {
      final length = signature.$3;
      if (length > 0 && length <= _limit) {
        final bytes = await File(sidecar).openRead(0, length).fold<List<int>>(
            [],
            (buffer, chunk) =>
                buffer..addAll(chunk)).timeout(const Duration(seconds: 3));
        text = decodeLyricText(bytes);
      }
    } else {
      text = await _readEmbedded(source).timeout(const Duration(seconds: 5));
      if (text != null && text.length > _limit) text = null;
    }
    if (text?.trim().isEmpty ?? false) text = null;
    _remember(key, _CachedClassificationLyrics(signature, text, _now()));
    return text;
  }

  void _remove(String key) {
    final removed = _cache.remove(key);
    if (removed != null) _cachedBytes -= removed.bytes;
  }

  void _remember(String key, _CachedClassificationLyrics value) {
    _remove(key);
    if (maximumEntries <= 0 ||
        maximumBytes <= 0 ||
        value.bytes > maximumBytes) {
      return;
    }
    _cache[key] = value;
    _cachedBytes += value.bytes;
    while (_cache.length > maximumEntries || _cachedBytes > maximumBytes) {
      _remove(_cache.keys.first);
    }
  }
}

enum LocalFileAvailability { available, missing, inaccessible }

class LocalAudioFileInfo {
  const LocalAudioFileInfo.available(this.bytes, {this.resolvedPath})
      : availability = LocalFileAvailability.available;

  const LocalAudioFileInfo.missing()
      : availability = LocalFileAvailability.missing,
        bytes = 0,
        resolvedPath = null;

  const LocalAudioFileInfo.inaccessible()
      : availability = LocalFileAvailability.inaccessible,
        bytes = 0,
        resolvedPath = null;

  final LocalFileAvailability availability;
  final int bytes;
  final String? resolvedPath;
}

class FormatStorageUsage {
  const FormatStorageUsage({
    required this.format,
    required this.fileCount,
    required this.bytes,
  });

  final String format;
  final int fileCount;
  final int bytes;
}

/// A directly containing directory, not a recursive folder scan. [path] is the
/// normalized absolute directory recorded in the library. Missing/unreadable
/// entries count as songs, but only successfully measured files add bytes.
class FolderStorageUsage {
  const FolderStorageUsage({
    required this.path,
    required this.fileCount,
    required this.measuredFileCount,
    required this.missingFileCount,
    required this.inaccessibleFileCount,
    required this.bytes,
  });

  final String path;
  final int fileCount;
  final int measuredFileCount;
  final int missingFileCount;
  final int inaccessibleFileCount;
  final int bytes;
}

enum FolderDistributionMetric { songCount, storageBytes }

/// At most one directory or the sum of the directories outside the top N.
/// A null [path] explicitly denotes "other", never a filesystem location.
class FolderDistributionEntry {
  FolderDistributionEntry._(List<FolderStorageUsage> folders,
      {required bool isOther})
      : path = isOther ? null : folders.single.path,
        folderCount = folders.length,
        fileCount = folders.fold(0, (sum, item) => sum + item.fileCount),
        measuredFileCount =
            folders.fold(0, (sum, item) => sum + item.measuredFileCount),
        missingFileCount =
            folders.fold(0, (sum, item) => sum + item.missingFileCount),
        inaccessibleFileCount =
            folders.fold(0, (sum, item) => sum + item.inaccessibleFileCount),
        bytes = folders.fold(0, (sum, item) => sum + item.bytes);

  final String? path;
  final int folderCount;
  final int fileCount;
  final int measuredFileCount;
  final int missingFileCount;
  final int inaccessibleFileCount;
  final int bytes;

  bool get isOther => path == null;
  int value(FolderDistributionMetric metric) =>
      metric == FolderDistributionMetric.songCount ? fileCount : bytes;
}

class FolderDistribution {
  FolderDistribution._({
    required this.metric,
    required this.total,
    required List<FolderDistributionEntry> entries,
  }) : entries = List.unmodifiable(entries);

  final FolderDistributionMetric metric;
  final int total;
  final List<FolderDistributionEntry> entries;

  double percentageOf(FolderDistributionEntry entry) =>
      total <= 0 ? 0 : 100 * entry.value(metric) / total;
}

class TrackStorageUsage {
  const TrackStorageUsage({
    required this.title,
    required this.path,
    required this.bytes,
  });

  final String title;
  final String path;
  final int bytes;
}

class LibraryStatisticsSnapshot {
  LibraryStatisticsSnapshot({
    required this.localTracks,
    required this.onlineTracks,
    required this.measuredLocalTracks,
    required this.missingLocalTracks,
    required this.inaccessibleLocalTracks,
    required this.totalLocalBytes,
    required this.duplicateEntries,
    required Map<SongLanguage, int> languageCounts,
    required Map<SongLanguage, int> taggedLanguageCounts,
    required Map<SongLanguage, int> inferredLanguageCounts,
    Map<SongLanguage, int> lyricLanguageCounts = const {},
    required List<FormatStorageUsage> formats,
    List<FolderStorageUsage> folders = const [],
    required List<TrackStorageUsage> largestFiles,
    required this.scannedAt,
  })  : languageCounts = Map.unmodifiable(languageCounts),
        taggedLanguageCounts = Map.unmodifiable(taggedLanguageCounts),
        inferredLanguageCounts = Map.unmodifiable(inferredLanguageCounts),
        lyricLanguageCounts = Map.unmodifiable(lyricLanguageCounts),
        formats = List.unmodifiable(formats),
        folders = List.unmodifiable(folders),
        largestFiles = List.unmodifiable(largestFiles);

  final int localTracks;
  final int onlineTracks;
  final int measuredLocalTracks;
  final int missingLocalTracks;
  final int inaccessibleLocalTracks;
  final int totalLocalBytes;
  final int duplicateEntries;
  final Map<SongLanguage, int> languageCounts;
  final Map<SongLanguage, int> taggedLanguageCounts;
  final Map<SongLanguage, int> inferredLanguageCounts;
  final Map<SongLanguage, int> lyricLanguageCounts;
  final List<FormatStorageUsage> formats;
  final List<FolderStorageUsage> folders;
  final List<TrackStorageUsage> largestFiles;
  final DateTime scannedAt;

  int get totalTracks => localTracks + onlineTracks;
  int get localFolderCount => folders.length;
  int get taggedTracks => taggedLanguageCounts.values.fold(0, (a, b) => a + b);
  int get inferredTracks =>
      inferredLanguageCounts.values.fold(0, (a, b) => a + b);
  int get lyricTracks => lyricLanguageCounts.values.fold(0, (a, b) => a + b);
  int get metadataInferredTracks => inferredTracks - lyricTracks;

  int metadataInferredCount(SongLanguage language) =>
      (inferredLanguageCounts[language] ?? 0) -
      (lyricLanguageCounts[language] ?? 0);

  /// Sort and aggregate this immutable snapshot only; switching chart metrics
  /// never stats files, reads lyrics, or walks directory contents again.
  FolderDistribution folderDistribution(
    FolderDistributionMetric metric, {
    int maxFolders = 7,
  }) {
    if (maxFolders < 1) {
      throw RangeError.range(maxFolders, 1, null, 'maxFolders');
    }
    int value(FolderStorageUsage item) =>
        metric == FolderDistributionMetric.songCount
            ? item.fileCount
            : item.bytes;
    final ordered = List<FolderStorageUsage>.of(folders)
      ..sort((a, b) {
        final byValue = value(b).compareTo(value(a));
        return byValue != 0 ? byValue : a.path.compareTo(b.path);
      });
    return FolderDistribution._(
      metric: metric,
      total: metric == FolderDistributionMetric.songCount
          ? localTracks
          : totalLocalBytes,
      entries: [
        for (final folder in ordered.take(maxFolders))
          FolderDistributionEntry._([folder], isOther: false),
        if (ordered.length > maxFolders)
          FolderDistributionEntry._(ordered.sublist(maxFolders), isOther: true),
      ],
    );
  }
}

class LibraryScanCancelled implements Exception {
  const LibraryScanCancelled();
}

typedef LocalAudioFileInspector = Future<LocalAudioFileInfo> Function(String);
typedef LocalLyricsReader = Future<String?> Function(String);

/// A read-only, bounded-concurrency snapshot. File sizes are measured afresh;
/// cached index sizes, durations, bitrates and remote URLs are never estimates
/// of local storage. The caller controls refresh, independently of playback.
class LibraryStatisticsScanner {
  LibraryStatisticsScanner({
    LocalAudioFileInspector? inspectFile,
    LocalLyricsReader? readLyrics,
    bool? windowsPaths,
  })  : _inspectFile = inspectFile ?? _inspectLocalFile,
        _readLyrics = readLyrics ?? readLocalClassificationLyrics,
        _windowsPaths = windowsPaths ?? Platform.isWindows,
        _paths = path.Context(
          style: (windowsPaths ?? Platform.isWindows)
              ? path.Style.windows
              : path.Style.posix,
        );

  final LocalAudioFileInspector _inspectFile;
  final LocalLyricsReader _readLyrics;
  final bool _windowsPaths;
  final path.Context _paths;

  String _localKey(String value) {
    final normalized = _paths.normalize(_paths.absolute(value));
    return _windowsPaths ? normalized.toLowerCase() : normalized;
  }

  Future<LibraryStatisticsSnapshot> scan(
    Iterable<Audio> audios, {
    bool Function()? isCancelled,
    void Function(int completed, int total)? onProgress,
  }) async {
    void checkCancelled() {
      if (isCancelled?.call() == true) throw const LibraryScanCancelled();
    }

    checkCancelled();
    final seen = <String>{};
    final tracks = <_StatisticsTrack>[];
    var duplicates = 0;
    // Freeze descriptors before the first await: metadata may be edited while
    // the filesystem is being read, but one snapshot should remain coherent.
    for (final audio in audios) {
      final online = audio.isOnline ||
          RegExp(r'^(?:online|https?)://', caseSensitive: false)
              .hasMatch(audio.path);
      final key = online
          ? 'online:${audio.onlineProvider}/${audio.onlineId ?? audio.path}'
          : 'local:${_localKey(audio.path)}';
      if (!seen.add(key)) {
        duplicates++;
        continue;
      }
      tracks.add(_StatisticsTrack(
        path: audio.path,
        title: audio.title,
        composer: audio.composer,
        artist: audio.artist,
        album: audio.album,
        language: audio.language,
        online: online,
      ));
    }

    var local = 0;
    var online = 0;
    var measured = 0;
    var missing = 0;
    var inaccessible = 0;
    var totalBytes = 0;
    final physicalPaths = <String>{};
    final languageCounts = {for (final item in SongLanguage.values) item: 0};
    final taggedCounts = {for (final item in SongLanguage.values) item: 0};
    final inferredCounts = {for (final item in SongLanguage.values) item: 0};
    final lyricCounts = {for (final item in SongLanguage.values) item: 0};
    final formatBytes = <String, int>{};
    final formatCounts = <String, int>{};
    final folderCounts = <String, _FolderAccumulator>{};
    final files = <TrackStorageUsage>[];

    for (var offset = 0; offset < tracks.length; offset += 8) {
      checkCancelled();
      final batch = tracks.sublist(offset, math.min(offset + 8, tracks.length));
      final results = await Future.wait(batch.map((track) async {
        LocalAudioFileInfo? info;
        String? lyrics;
        if (!track.online) {
          try {
            info = await _inspectFile(track.path);
          } catch (_) {
            info = const LocalAudioFileInfo.inaccessible();
          }
          checkCancelled();
          if (info.bytes < 0) info = const LocalAudioFileInfo.inaccessible();
          if (info.availability == LocalFileAvailability.available &&
              _languageFromTag(track.language) == null) {
            try {
              lyrics = await _readLyrics(track.path);
            } catch (_) {
              // A missing/unreadable lyric must not invalidate an audio file.
            }
          }
        }
        checkCancelled();
        return (
          track: track,
          info: info,
          classification: classifyMusicMetadata(
            language: track.language,
            lyrics: lyrics,
            title: track.title,
            filePath: track.path,
            composer: track.composer,
            artist: track.artist,
            album: track.album,
          ).language,
        );
      }));
      checkCancelled();
      for (final result in results) {
        final track = result.track;
        final info = result.info;
        if (info != null &&
            info.availability == LocalFileAvailability.available &&
            !physicalPaths.add(_localKey(info.resolvedPath ?? track.path))) {
          duplicates++;
          continue;
        }
        if (track.online) {
          online++;
        } else {
          local++;
          final directory =
              _paths.dirname(_paths.normalize(_paths.absolute(track.path)));
          // Reuse the exact result used for all other totals. Alias duplicates
          // have already been removed, keeping the first library descriptor.
          folderCounts
              .putIfAbsent(
                  _localKey(directory), () => _FolderAccumulator(directory))
              .add(info!);
          switch (info.availability) {
            case LocalFileAvailability.available:
              measured++;
              totalBytes += info.bytes;
              final extension = _paths.extension(track.path).toUpperCase();
              final format =
                  extension.isEmpty ? '无扩展名' : extension.substring(1);
              formatBytes.update(format, (value) => value + info.bytes,
                  ifAbsent: () => info.bytes);
              formatCounts.update(format, (value) => value + 1,
                  ifAbsent: () => 1);
              files.add(TrackStorageUsage(
                title: track.title,
                path: track.path,
                bytes: info.bytes,
              ));
            case LocalFileAvailability.missing:
              missing++;
            case LocalFileAvailability.inaccessible:
              inaccessible++;
          }
        }
        final classification = result.classification;
        languageCounts[classification.language] =
            languageCounts[classification.language]! + 1;
        if (classification.evidence == LanguageEvidence.tag) {
          taggedCounts[classification.language] =
              taggedCounts[classification.language]! + 1;
        } else if (classification.isInferred) {
          inferredCounts[classification.language] =
              inferredCounts[classification.language]! + 1;
          if (classification.evidence == LanguageEvidence.lyrics) {
            lyricCounts[classification.language] =
                lyricCounts[classification.language]! + 1;
          }
        }
      }
      onProgress?.call(math.min(offset + 8, tracks.length), tracks.length);
    }
    final formats = [
      for (final entry in formatBytes.entries)
        FormatStorageUsage(
          format: entry.key,
          fileCount: formatCounts[entry.key]!,
          bytes: entry.value,
        ),
    ]..sort((a, b) => b.bytes.compareTo(a.bytes));
    files.sort((a, b) => b.bytes.compareTo(a.bytes));
    checkCancelled();
    return LibraryStatisticsSnapshot(
      localTracks: local,
      onlineTracks: online,
      measuredLocalTracks: measured,
      missingLocalTracks: missing,
      inaccessibleLocalTracks: inaccessible,
      totalLocalBytes: totalBytes,
      duplicateEntries: duplicates,
      languageCounts: languageCounts,
      taggedLanguageCounts: taggedCounts,
      inferredLanguageCounts: inferredCounts,
      lyricLanguageCounts: lyricCounts,
      formats: formats,
      folders: folderCounts.values.map((item) => item.snapshot()).toList()
        ..sort((a, b) => a.path.compareTo(b.path)),
      largestFiles: files.take(6).toList(),
      scannedAt: DateTime.now(),
    );
  }

  static Future<LocalAudioFileInfo> _inspectLocalFile(String audioPath) async {
    try {
      final file = File(audioPath);
      final length = await file.length().timeout(const Duration(seconds: 5));
      String? resolvedPath;
      try {
        resolvedPath = await file
            .resolveSymbolicLinks()
            .timeout(const Duration(seconds: 5));
      } catch (_) {
        // The exact path can still be counted if symlink resolution is denied.
      }
      return LocalAudioFileInfo.available(length, resolvedPath: resolvedPath);
    } on FileSystemException catch (error) {
      final code = error.osError?.errorCode;
      final missing =
          Platform.isWindows ? code == 2 || code == 3 : code == 2 || code == 20;
      return missing
          ? const LocalAudioFileInfo.missing()
          : const LocalAudioFileInfo.inaccessible();
    } catch (_) {
      return const LocalAudioFileInfo.inaccessible();
    }
  }
}

class _FolderAccumulator {
  _FolderAccumulator(this.path);

  final String path;
  int fileCount = 0;
  int measuredFileCount = 0;
  int missingFileCount = 0;
  int inaccessibleFileCount = 0;
  int bytes = 0;

  void add(LocalAudioFileInfo info) {
    fileCount++;
    switch (info.availability) {
      case LocalFileAvailability.available:
        measuredFileCount++;
        bytes += info.bytes;
      case LocalFileAvailability.missing:
        missingFileCount++;
      case LocalFileAvailability.inaccessible:
        inaccessibleFileCount++;
    }
  }

  FolderStorageUsage snapshot() => FolderStorageUsage(
        path: path,
        fileCount: fileCount,
        measuredFileCount: measuredFileCount,
        missingFileCount: missingFileCount,
        inaccessibleFileCount: inaccessibleFileCount,
        bytes: bytes,
      );
}

class _StatisticsTrack {
  const _StatisticsTrack({
    required this.path,
    required this.title,
    required this.composer,
    required this.artist,
    required this.album,
    required this.language,
    required this.online,
  });

  final String path;
  final String title;
  final String? composer;
  final String artist;
  final String album;
  final String? language;
  final bool online;
}

String formatLibraryBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KiB', 'MiB', 'GiB', 'TiB'];
  var value = bytes.toDouble();
  var index = -1;
  do {
    value /= 1024;
    index++;
  } while (value >= 1024 && index < units.length - 1);
  return '${value.toStringAsFixed(value >= 100 ? 1 : 2)} ${units[index]}';
}
