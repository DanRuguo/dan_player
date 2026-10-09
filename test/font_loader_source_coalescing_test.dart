import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_lyric/font_loader.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Original open-font tables remain intact. Only collection-relative table
// offsets change; the loader still has to select and register each real face.
Uint8List _collection(List<Uint8List> faces) {
  final header = (12 + faces.length * 4 + 3) & ~3;
  final result = Uint8List(
      header + faces.fold(0, (sum, face) => sum + ((face.length + 3) & ~3)));
  final out = ByteData.sublistView(result);
  out.setUint32(0, 0x74746366);
  out.setUint32(4, 0x00010000);
  out.setUint32(8, faces.length);
  var offset = header;
  for (final (index, face) in faces.indexed) {
    result.setRange(offset, offset + face.length, face);
    out.setUint32(12 + index * 4, offset);
    final input = ByteData.sublistView(face);
    for (var table = 0; table < input.getUint16(4); table++) {
      final record = 12 + table * 16;
      out.setUint32(offset + record + 8, offset + input.getUint32(record + 8));
    }
    offset += (face.length + 3) & ~3;
  }
  return result;
}

List<double> _metrics(String family) {
  final result = <double>[];
  for (final text in ['WWWWiiii', 'Dan Player 012345', 'AVATAR fj']) {
    final painter = TextPainter(
        text: TextSpan(
            text: text, style: TextStyle(fontFamily: family, fontSize: 32)),
        textDirection: TextDirection.ltr)
      ..layout();
    result.addAll([painter.width, painter.height]);
    painter.dispose();
  }
  return result;
}

List<AppFontFace> _faces(String label, String source, {bool asset = true}) => [
      for (var index = 0; index < 4; index++)
        AppFontFace(
            id: 'custom',
            family: 'QA coalesced $label $index',
            nativeFamily:
                index.isEven ? 'Google Sans Regular' : 'Pretendard Regular',
            asset: asset ? source : null,
            path: asset ? null : source)
    ];

AppFontPolicy _policy(List<AppFontFace> faces) => AppFontPolicy(
    language: UiLanguage.zh,
    mixedScripts: true,
    zh: faces[0],
    en: faces[1],
    ja: faces[2],
    ko: faces[3],
    baseFallback: const AppFontFace(id: 'inherit', family: 'inherit'));

void _checkFaces(List<AppFontFace> faces) {
  final first = _metrics('QA source reference first');
  final second = _metrics('QA source reference second');
  expect(first, isNot(second), reason: 'Real fixture fonts must differ');
  for (final (index, face) in faces.indexed) {
    expect(_metrics(face.family), index.isEven ? first : second,
        reason: 'Source sharing must retain selected face $index');
  }
}

class _CountingFile implements File {
  _CountingFile(this.delegate, this.onRead, this.ready);
  final File delegate;
  final VoidCallback onRead;
  final Future<void> ready;
  @override
  Future<Uint8List> readAsBytes() async {
    onRead();
    await ready;
    return delegate.readAsBytes();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Uint8List first, second, collection;
  setUpAll(() async {
    first =
        await File('third_party/desktop_lyric/assets/fonts/GoogleSans-VF.ttf')
            .readAsBytes();
    second = await File(
            'third_party/desktop_lyric/assets/fonts/Pretendard-Regular.otf')
        .readAsBytes();
    collection = _collection([first, second]);
    await (FontLoader('QA source reference first')
          ..addFont(Future.value(ByteData.sublistView(first))))
        .load();
    await (FontLoader('QA source reference second')
          ..addFont(Future.value(ByteData.sublistView(second))))
        .load();
  });
  tearDown(() {
    binding.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  void mockAsset(String source, Future<ByteData?> Function() response) {
    binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',
        (message) {
      final requested = Uri.decodeFull(utf8.decode(message!.buffer
          .asUint8List(message.offsetInBytes, message.lengthInBytes)));
      expect(requested, source);
      return response();
    });
  }

  test('four selected collection faces share one pending asset read', () async {
    const source = 'qa-source-asset.ttc';
    final ready = Completer<ByteData?>();
    var reads = 0;
    mockAsset(source, () {
      reads++;
      return ready.future;
    });
    final faces = _faces('asset', source);
    final loading = ensureAppFontsLoaded(_policy(faces));
    await Future<void>.delayed(Duration.zero);
    ready.complete(ByteData.sublistView(collection));
    await loading;
    _checkFaces(faces);
    expect(reads, 1,
        reason: 'Four registrations must share the same pending source IO');
  });

  test('four selected collection faces share one pending custom file read',
      () async {
    final directory = await Directory.systemTemp.createTemp('dan-source-file-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/open-fonts.ttc');
    await file.writeAsBytes(collection);
    final ready = Completer<void>();
    var reads = 0;
    final faces = _faces('file', file.path, asset: false);
    await IOOverrides.runZoned(() async {
      final loading = ensureAppFontsLoaded(_policy(faces));
      await Future<void>.delayed(Duration.zero);
      ready.complete();
      await loading;
    }, createFile: (path) {
      expect(path, file.path);
      return _CountingFile(file, () => reads++, ready.future);
    });
    _checkFaces(faces);
    expect(reads, 1,
        reason: 'Custom TTC choices must share their actual file read');
  });

  test('asset and file sources with identical strings stay independent',
      () async {
    final directory = await Directory.systemTemp.createTemp('dan-source-kind-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/same-source.ttf');
    await file.writeAsBytes(second);
    final ready = Completer<ByteData?>();
    var reads = 0;
    mockAsset(file.path, () {
      reads++;
      return ready.future;
    });
    final asset = AppFontFace(
        id: 'custom', family: 'QA source kind asset', asset: file.path);
    final path = AppFontFace(
        id: 'custom', family: 'QA source kind file', path: file.path);
    final loading =
        Future.wait([ensureAppFontLoaded(asset), ensureAppFontLoaded(path)]);
    await Future<void>.delayed(Duration.zero);
    ready.complete(ByteData.sublistView(first));
    await loading;
    expect(reads, 1);
    expect(_metrics(asset.family), _metrics('QA source reference first'));
    expect(_metrics(path.family), _metrics('QA source reference second'));
  });

  test('completed source bytes are released while registrations stay cached',
      () async {
    const source = 'qa-source-released.ttf';
    var reads = 0;
    mockAsset(source, () async {
      reads++;
      return ByteData.sublistView(reads == 1 ? first : second);
    });
    const a = AppFontFace(
        id: 'custom', family: 'QA source released A', asset: source);
    const b = AppFontFace(
        id: 'custom', family: 'QA source released B', asset: source);
    await ensureAppFontLoaded(a);
    await ensureAppFontLoaded(b);
    expect(reads, 2, reason: 'Only pending reads may retain raw source bytes');
    expect(_metrics(a.family), _metrics('QA source reference first'));
    expect(_metrics(b.family), _metrics('QA source reference second'));
    await ensureAppFontLoaded(a);
    expect(reads, 2);
    expect(_metrics(a.family), _metrics('QA source reference first'));
  });

  for (final invalidBytes in [false, true]) {
    test(
        '${invalidBytes ? 'invalid bytes' : 'failed IO'} release shared source and registration owners for retry',
        () async {
      final source = 'qa-source-retry-$invalidBytes.ttc';
      final ready = Completer<ByteData?>();
      var reads = 0;
      var restored = false;
      mockAsset(source, () {
        reads++;
        return restored
            ? Future.value(ByteData.sublistView(collection))
            : ready.future;
      });
      final faces = _faces('retry $invalidBytes', source);
      final failures = Future.wait(faces.map((face) async {
        try {
          await ensureAppFontLoaded(face);
          return null;
        } catch (error) {
          return error;
        }
      }));
      await Future<void>.delayed(Duration.zero);
      ready.complete(invalidBytes ? ByteData(16) : null);
      final errors = await failures;
      expect(
          errors, everyElement(invalidBytes ? isFormatException : isNotNull));
      expect(reads, 1);
      restored = true;
      await ensureAppFontsLoaded(_policy(faces));
      expect(reads, 2,
          reason: 'A failed source must allow one fresh shared retry');
      _checkFaces(faces);
    });
  }
}
