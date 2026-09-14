import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:dan_player/library/ffmpeg_runtime.dart';
import 'package:dan_player/library/ffmpeg_module_install.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory('build/test-data')
        .create(recursive: true)
        .then((d) => d.createTemp('ffmpeg-'));
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  test(
      'complete tools are cached; invalidation and missing executables trigger rediscovery',
      () async {
    for (final name in ffmpegToolNames) {
      await File(p.join(root.path, '$name${Platform.isWindows ? '.exe' : ''}'))
          .writeAsString('fixture');
    }
    var calls = 0;
    final runtime = FfmpegRuntime(probe: (exe, args) async {
      calls++;
      if (args.contains('-version'))
        return '${p.basenameWithoutExtension(exe)} version 7.1.1';
      if (args.contains('-encoders'))
        return 'libmp3lame flac aac alac libvorbis libopus pcm_s16le';
      return '';
    });
    expect(await runtime.ensure(directories: [root.path]), isTrue);
    expect(calls, 5);
    for (var i = 0; i < 5; i++) {
      expect(await runtime.ensure(directories: []), isTrue);
    }
    expect(calls, 5);
    expect(runtime.path('ffmpeg'), contains('ffmpeg'));
    await File(runtime.path('ffprobe')).delete();
    expect(
        await runtime.ensure(force: true, directories: [root.path]), isFalse);
    expect(() => runtime.path('ffmpeg'), throwsA(isA<FfmpegUnavailable>()));
  });
  test('download corruption is rejected before extracting any file', () async {
    final bad = File(p.join(root.path, 'bad.zip'));
    await bad.writeAsString('not the pinned module');
    final target = p.join(root.path, 'output');
    await expectLater(
        extractFfmpegModule(bad.path, target), throwsFormatException);
    expect(Directory(target).existsSync(), isFalse);
  });
  final module = Platform.environment['DAN_PLAYER_FFMPEG_MODULE_ZIP'];
  test('cancelled setup retains existing tools and removes its temporary work',
      () async {
    final target = Directory(p.join(root.path, 'installed'));
    await target.create();
    final original = File(p.join(target.path, 'keep.txt'));
    await original.writeAsString('existing tool');
    final installer = FfmpegModuleInstaller()..cancel();
    await expectLater(
        installer.install(
            runtime: FfmpegRuntime(installRoot: target), progress: (_) {}),
        throwsA(isA<FfmpegUnavailable>()));
    expect(await original.readAsString(), 'existing tool');
    expect(await root.list().length, 1);
  });
  testWidgets(
      'explicit live download uses system proxy and installs only into sandbox',
      (tester) async {
    await tester.runAsync(() async {
      final target = Directory(p.absolute(p.join(root.path, 'installed')));
      final runtime = FfmpegRuntime(installRoot: target);
      var reports = 0;
      await FfmpegModuleInstaller().install(
          runtime: runtime, progress: (_) => reports++, onStage: print);
      expect(runtime.ready, isTrue);
      expect(reports, greaterThan(1));
      expect(
          await target.parent
              .list()
              .where((e) => p.basename(e.path).startsWith('.ffmpeg-download-'))
              .length,
          0);
    });
  },
      skip: Platform.environment['DAN_PLAYER_FFMPEG_LIVE_DOWNLOAD'] != '1',
      timeout: const Timeout(Duration(minutes: 10)));
  test('real optional module extracts and passes executable and encoder probes',
      () async {
    final target = p.join(root.path, 'module');
    await extractFfmpegModule(module!, target);
    final runtime = FfmpegRuntime();
    expect(await runtime.ensure(directories: [p.absolute(target)]), isTrue);
    expect(runtime.ready, isTrue);
  }, skip: module == null, timeout: const Timeout(Duration(minutes: 2)));
}
