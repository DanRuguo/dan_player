import 'dart:io';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/krc_decoder.dart';
import 'package:dan_player/lyric/local_lyric_parser.dart';
import 'package:dan_player/lyric/local_lyric_reader.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:dan_player/lyric/lyric_edit_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

String _ttml(String original, {String roles = ''}) =>
    '<tt xmlns="http://www.w3.org/ns/ttml" '
    'xmlns:m="http://www.w3.org/ns/ttml#metadata" '
    'xmlns:a="http://music.apple.com/lyric-ttml-internal">'
    '<body><div><p begin="1s" end="2s">'
    '<span begin="1s" end="1.5s">$original</span>'
    '<span begin="1.5s" end="2s"> 🌙</span>$roles'
    '</p></div></body></tt>';

SyncLyricLine _line(Lyric lyric) => lyric.lines
    .whereType<SyncLyricLine>()
    .firstWhere((line) => line.content.trim().isNotEmpty);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory fixture;
  late Audio audio;
  setUp(() async {
    final root = Platform.environment['DAN_PLAYER_DATA_DIR'];
    final qa = path.join(Directory.current.parent.path, 'tool', 'qa-local');
    if (root == null || !path.isWithin(qa, root)) {
      throw StateError('Use independent workspace QA data');
    }
    fixture = await Directory(root).createTemp('ttml-lyrics-');
    audio = Audio('Example', 'Artist', 'Album', 0, 60, null, null,
        path.join(fixture.path, 'Example.flac'), 0, 0, null);
    await File(audio.localFilePath).writeAsBytes([0]);
    clearLocalLyricMemoryCache();
  });
  tearDown(() async {
    clearLocalLyricMemoryCache();
    final qa = path.join(Directory.current.parent.path, 'tool', 'qa-local');
    if (!path.isWithin(qa, fixture.absolute.path)) {
      throw StateError('QA cleanup escaped workspace');
    }
    await fixture.delete(recursive: true);
  });
  File sidecar(String suffix) => File(path.setExtension(audio.path, suffix));
  Future<void> write(String suffix, String value) =>
      sidecar(suffix).writeAsString(value);

  test('TTML sidecars precede line formats while existing word priority stays',
      () async {
    await write('.ttml', _ttml('TTML'));
    await write('.elrc', '[00:01.000]<00:01.000>ELRC<00:02.000>');
    await write('.lrc', '[00:01.000]LRC');
    for (final order in LocalLyricLineOrder.values) {
      final lyric = (await readLocalLyric(audio, lineOrder: order))!;
      expect(_line(lyric).content, 'TTML 🌙');
      expect(localLyricOrigin(lyric), endsWith('.ttml'));
    }
    await sidecar('.krc')
        .writeAsBytes(encodeKrcContainer('[1000,1000]<0,1000,0>KRC'));
    expect(_line((await readLocalLyric(audio))!).content, 'KRC');
    await write('.yrc', '[1000,1000](1000,1000,0)YRC');
    expect(_line((await readLocalLyric(audio))!).content, 'YRC');
    await write('.qrc', '[1000,1000]QRC(1000,1000)');
    expect(_line((await readLocalLyric(audio))!).content, 'QRC');
    await sidecar('.qrc').delete();
    await sidecar('.yrc').delete();
    await sidecar('.krc').delete();
    await sidecar('.ttml').delete();
    final fallback = (await readLocalLyric(audio))!;
    expect(_line(fallback).content, 'ELRC');
    expect(localLyricOrigin(fallback), endsWith('.elrc'));
  });

  test('TTML cache clones all axes and file revisions invalidate its model',
      () async {
    await write('.ttml', _ttml('First', roles: '''
<span m:role="x-translation">译文</span><span m:role="x-roman">roma</span>'''));
    await write('.lrc', '[00:01.000]fallback');
    final first = (await readLocalLyric(audio))!;
    final editable = _line(first);
    editable.words.first.content = 'Edited';
    editable.translation = 'Edited';
    editable.romanization = 'Edited';
    final copy = _line((await readLocalLyric(audio))!);
    expect(copy.content, 'First 🌙');
    expect(copy.translation, '译文');
    expect(copy.romanization, 'roma');
    expect(copy.words.map((word) => word.start.inMilliseconds), [1000, 1500]);
    await write('.ttml', _ttml('Fresh file revision'));
    expect(_line((await readLocalLyric(audio))!).content,
        'Fresh file revision 🌙');
    await sidecar('.ttml').delete();
    expect(
        lyricLineText((await readLocalLyric(audio))!.lines.single), 'fallback');
    expect(await readLocalLyric(audio, stillCurrent: () => false), isNull);
  });

  test('invalid or oversized TTML warns and continues through local sources',
      () async {
    await write('.lrc', '[00:01.000]fallback');
    for (final invalid in [
      '<!DOCTYPE tt SYSTEM "file:///private.txt">${_ttml('unsafe')}',
      _ttml('unresolved &missing;'),
      'x' * (LyricEditDraft.maxBytes + 1),
    ]) {
      await write('.ttml', invalid);
      final warnings = <String>[];
      final lyric = (await readLocalLyric(audio, onWarning: warnings.add))!;
      expect(lyricLineText(lyric.lines.single), 'fallback');
      expect(warnings, hasLength(1));
      expect(warnings.single, contains('本地歌词读取失败'));
    }
  });

  test('explicit TTML roles survive companion fallback and editor file import',
      () async {
    await write('.ttml', _ttml('Original', roles: '''
<span m:role="x-translation">内嵌译文</span><span m:role="x-roman">inline roma</span>'''));
    await write('.ttml.translation.lrc', '[00:01.000]external translation');
    await write('.ttml.romanization.lrc', '[00:01.000]external roma');
    await write('.lrc', '[00:01.000]generic fallback');
    final local = _line((await readLocalLyric(audio))!);
    final imported = await readLyricEditFile(sidecar('.ttml'));
    expect(imported.format, LyricEditFormat.qrc);
    final editor = _line(imported.parse());
    for (final line in [local, editor]) {
      expect(line.content, 'Original 🌙');
      expect(line.translation, '内嵌译文');
      expect(line.romanization, 'inline roma');
    }
  });

  test('companions fill missing TTML tracks and export into existing formats',
      () async {
    await write('.ttml', _ttml('Original'));
    await write('.ttml.translation.lrc', '[00:01.000]译文');
    await write('.ttml.romanization.lrc', '[00:01.000]roma');
    final source = await sidecar('.ttml').readAsBytes();
    final imported = await readLyricEditFile(sidecar('.ttml'));
    expect(imported.format, LyricEditFormat.qrc);
    final local = _line((await readLocalLyric(audio))!);
    expect(local.translation, '译文');
    expect(local.romanization, 'roma');
    final output =
        path.join(fixture.path, 'Edited.${imported.format.extension}');
    final exports = imported.exportFiles(output);
    expect(exports.keys.any((name) => name.endsWith('.ttml')), isFalse);
    await writeLyricExport(exports);
    final saved = await readLyricEditFile(File(output));
    expect(LyricSnapshot.capture(saved.parse()).toJson(),
        LyricSnapshot.capture(imported.parse()).toJson());
    expect(await sidecar('.ttml').readAsBytes(), source);
  });

  test(
      'line breaks use the existing lossless draft and preserve embedded roles',
      () async {
    await write('.ttml', _ttml('one<br/>two', roles: '''
<span m:role="x-translation">译文<br/>第二行</span>'''));
    final imported = await readLyricEditFile(sidecar('.ttml'));
    expect(imported.format, LyricEditFormat.lossless);
    expect(_line(imported.parse()).content, 'one\ntwo 🌙');
    expect(_line(imported.parse()).translation, '译文\n第二行');
    final output =
        path.join(fixture.path, 'Edited.${imported.format.extension}');
    await writeLyricExport(imported.exportFiles(output));
    final saved = await readLyricEditFile(File(output));
    expect(LyricSnapshot.capture(saved.parse()).toJson(),
        LyricSnapshot.capture(imported.parse()).toJson());
    final documents = LyricDocumentStore(storageDirectory: fixture);
    final reloaded = LyricDocumentStore(storageDirectory: fixture);
    try {
      await documents.saveDraft(audio, imported.parse(), expectedRevision: 0);
      await documents.useDraft(audio, expectedRevision: 1);
      await reloaded.load();
      expect(reloaded.forAudio(audio)!.locked, isTrue);
      expect(reloaded.forAudio(audio)!.effective!.toJson(),
          LyricSnapshot.capture(imported.parse()).toJson());
    } finally {
      documents.dispose();
      reloaded.dispose();
    }
  });
}
