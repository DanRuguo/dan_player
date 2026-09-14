import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dan_player/library/audio_trim.dart';
import 'package:dan_player/library/audio_trim_sidecar.dart';
import 'package:dan_player/lyric/lyric_text_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const oldText = '[00:12.345]音乐、音楽、음악 🎵\r\n';
const newText = '[00:00.345]音乐、音楽、음악 🎵\r\n';

Uint8List encode(String text, int encoding) {
  if (encoding < 2) {
    return Uint8List.fromList([
      if (encoding == 1) ...[0xef, 0xbb, 0xbf],
      ...utf8.encode(text)
    ]);
  }
  final output = <int>[
    if (encoding == 2) ...[0xff, 0xfe] else ...[0xfe, 0xff]
  ];
  for (final unit in text.codeUnits) {
    output.addAll(
        encoding == 2 ? [unit & 255, unit >> 8] : [unit >> 8, unit & 255]);
  }
  return Uint8List.fromList(output);
}

Future<String> shifted(String text, double start, double end) async {
  expect(text, oldText);
  expect(start, 12);
  expect(end, 20);
  return jsonEncode({'text': newText, 'adjusted': true, 'warning': null});
}

void main() {
  late Directory root;
  late Directory directory;
  late String source;
  late String destination;
  setUp(() async {
    root = await Directory(
            p.absolute('.dart_tool', 'test-data', 'audio-trim-sidecar'))
        .create(recursive: true);
    directory = await root.createTemp('transaction-');
    source = p.join(directory.path, '原曲 & song.mp3');
    destination = p.join(directory.path, '副本 🎵 song.mp3');
  });
  tearDown(() async {
    expect(p.isWithin(root.path, directory.path), isTrue);
    await directory.delete(recursive: true);
  });
  AudioTrimRequest request({bool overwrite = false, bool preserve = true}) =>
      AudioTrimRequest(
          destinationPath: overwrite ? source : destination,
          startSeconds: 12,
          endSeconds: 20,
          overwrite: overwrite,
          preserveMetadata: preserve);
  File lyrics(String audio) => File(p.setExtension(audio, '.lrc'));

  for (final encoding in [0, 1, 2, 3]) {
    test(
        'copy adjusts lyrics and preserves encoding $encoding and original source',
        () async {
      final original = encode(oldText, encoding);
      await lyrics(source).writeAsBytes(original);
      final prepared = (await prepareTrimmedAudioLyrics(source, request(),
          transform: shifted))!;
      expect(await lyrics(destination).exists(), isFalse);
      await prepared.commit();
      expect(
          await lyrics(destination).readAsBytes(), encode(newText, encoding));
      expect(await lyrics(source).readAsBytes(), original);
      expect(await prepared.dispose(), isNull);
      expect(await directory.list().length, 2);
    }, skip: !Platform.isWindows);
  }

  test(
      'overwrite adjusts external lyrics even when embedded metadata is not inherited',
      () async {
    await lyrics(source).writeAsString(oldText);
    final prepared = (await prepareTrimmedAudioLyrics(
        source, request(overwrite: true, preserve: false),
        transform: shifted))!;
    await prepared.commit();
    expect(await lyrics(source).readAsString(), newText);
    final backup = prepared.recoveryPath!;
    expect(await File(backup).readAsString(), oldText);
    expect(await prepared.dispose(), isNull);
    expect(await File(backup).exists(), isFalse);
  }, skip: !Platform.isWindows);

  test('failed audio publication rolls back replaced lyrics byte for byte',
      () async {
    final bytes = encode(oldText, 3);
    await lyrics(source).writeAsBytes(bytes);
    final prepared = (await prepareTrimmedAudioLyrics(
        source, request(overwrite: true),
        transform: shifted))!;
    await prepared.commit();
    expect(await prepared.rollback(), isNull);
    expect(await lyrics(source).readAsBytes(), bytes);
    expect(await prepared.dispose(), isNull);
  }, skip: !Platform.isWindows);

  test('failed audio copy removes only the published lyric copy', () async {
    await lyrics(source).writeAsString(oldText);
    final prepared = (await prepareTrimmedAudioLyrics(source, request(),
        transform: shifted))!;
    await prepared.commit();
    expect(await prepared.rollback(), isNull);
    expect(await lyrics(destination).exists(), isFalse);
    expect(await lyrics(source).readAsString(), oldText);
    await prepared.dispose();
  }, skip: !Platform.isWindows);

  test(
      'rollback preserves user edits and exposes an actual original recovery file',
      () async {
    await lyrics(source).writeAsString(oldText);
    final prepared = (await prepareTrimmedAudioLyrics(
        source, request(overwrite: true),
        transform: shifted))!;
    await prepared.commit();
    await lyrics(source).writeAsString('A new user edit');
    final warning = await prepared.rollback();
    expect(warning, contains(prepared.recoveryPath!));
    expect(await lyrics(source).readAsString(), 'A new user edit');
    expect(await File(prepared.recoveryPath!).readAsString(), oldText);
    expect(await prepared.dispose(), contains(prepared.recoveryPath!));
    expect(await File(prepared.recoveryPath!).exists(), isTrue);
  }, skip: !Platform.isWindows);

  test(
      'keeps recovery backup until requested after successful audio publication',
      () async {
    await lyrics(source).writeAsString(oldText);
    final prepared = (await prepareTrimmedAudioLyrics(
        source, request(overwrite: true),
        transform: shifted))!;
    await prepared.commit();
    final backup = prepared.recoveryPath!;
    expect(await prepared.dispose(keepBackup: true), contains(backup));
    expect(await File(backup).readAsString(), oldText);
  }, skip: !Platform.isWindows);

  test('source changes after preparation reject lyric publication', () async {
    await lyrics(source).writeAsString(oldText);
    final prepared = (await prepareTrimmedAudioLyrics(
        source, request(overwrite: true),
        transform: shifted))!;
    await lyrics(source).writeAsString('Changed while encoding');
    await expectLater(prepared.commit(), throwsA(isA<AudioTrimException>()));
    expect(await lyrics(source).readAsString(), 'Changed while encoding');
    await prepared.dispose();
  }, skip: !Platform.isWindows);

  test(
      'copies refuse both preexisting destinations and destinations created during encoding',
      () async {
    await lyrics(source).writeAsString(oldText);
    await lyrics(destination).writeAsString('Unrelated');
    await expectLater(
        prepareTrimmedAudioLyrics(source, request(), transform: shifted),
        throwsA(isA<AudioTrimException>()));
    await lyrics(destination).delete();
    final prepared = (await prepareTrimmedAudioLyrics(source, request(),
        transform: shifted))!;
    await lyrics(destination).writeAsString('Late unrelated');
    await expectLater(prepared.commit(), throwsA(isA<AudioTrimException>()));
    expect(await lyrics(destination).readAsString(), 'Late unrelated');
    await prepared.dispose();
  }, skip: !Platform.isWindows);

  test(
      'unsupported/plain text keeps exact original bytes and exposes warning state',
      () async {
    final original = encode(oldText, 2);
    await lyrics(source).writeAsBytes(original);
    final prepared = (await prepareTrimmedAudioLyrics(source, request(),
        transform: (text, _, __) async => jsonEncode(
            {'text': text, 'adjusted': false, 'warning': 'unsupported'})))!;
    expect(prepared.unsupported, isTrue);
    await prepared.commit();
    expect(await lyrics(destination).readAsBytes(), original);
    await prepared.dispose();
  }, skip: !Platform.isWindows);

  test('missing sidecar and copy without inheritance do not create work',
      () async {
    expect(
        await prepareTrimmedAudioLyrics(source, request(), transform: shifted),
        isNull);
    await lyrics(source).writeAsString(oldText);
    expect(
        await prepareTrimmedAudioLyrics(source, request(preserve: false),
            transform: shifted),
        isNull);
    expect(await directory.list().length, 1);
  }, skip: !Platform.isWindows);

  test(
      'rejects invalid UTF8, malformed UTF16 and files above 4 MiB before transformation',
      () async {
    for (final bytes in [
      <int>[0xc3, 0x28],
      <int>[0xff, 0xfe, 0x00],
      <int>[0xff, 0xfe, 0x00, 0xd8],
      Uint8List(4 * 1024 * 1024 + 1)
    ]) {
      await lyrics(source).writeAsBytes(bytes);
      await expectLater(
          prepareTrimmedAudioLyrics(source, request(),
              transform: (_, __, ___) async {
            fail('Malformed input reached transformation');
          }),
          throwsA(isA<AudioTrimException>()));
      expect(await directory.list().length, 1);
    }
  }, skip: !Platform.isWindows);

  test('uncommitted disposal removes only its known staging files', () async {
    await lyrics(source).writeAsString(oldText);
    final prepared = (await prepareTrimmedAudioLyrics(source, request(),
        transform: shifted))!;
    await prepared.dispose();
    expect(await directory.list().length, 1);
    expect(decodeLyricText(await lyrics(source).readAsBytes()), oldText);
  }, skip: !Platform.isWindows);
}
