import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import '../test/folder_tree_first_expand_test.dart' as folders;
import '../test/japanese_reading_visibility_linkage_test.dart' as visibility;
import '../test/japanese_ruby_visible_gap_test.dart' as gap;
import '../test/lyric_render_motion_feedback_test.dart' as motion;
import '../test/lyric_spacing_retarget_geometry_test.dart' as retarget;
import 'support/sampled_lyric_animation_binding.dart';

void main() {
  final binding = SampledLyricAnimationBinding();
  // Readback must not advance the finite animation through wall-clock frames.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  final group = (Platform.environment['DAN_KANA_NATIVE_GROUP'] ??
          const String.fromEnvironment('DAN_KANA_NATIVE_GROUP'))
      .trim();
  final selected = (Platform.environment['DAN_KANA_NATIVE_CASE'] ??
          const String.fromEnvironment('DAN_KANA_NATIVE_CASE'))
      .trim();
  const groups = {'folders', 'visibility', 'gap', 'motion', 'retarget'};
  if (group.isNotEmpty && !groups.contains(group)) {
    throw ArgumentError.value(group, 'DAN_KANA_NATIVE_GROUP');
  }
  // Gap currently exposes group selection only. Reject an ignored
  // case filter rather than describing a whole-group run as one-case resume.
  if (selected.isNotEmpty &&
      group != 'folders' &&
      group != 'visibility' &&
      group != 'motion' &&
      group != 'retarget') {
    throw ArgumentError(
        'DAN_KANA_NATIVE_CASE requires folders, visibility, motion or retarget.');
  }

  final qa = Directory(p.join(Directory.current.parent.path, 'tool', 'qa-local',
      'kana-layout-feedback-oct11', 'native'));
  const provider = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUpAll(() async {
    // Keep mocked path_provider authoritative, including on the real engine.
    expect(Platform.environment['DAN_PLAYER_DATA_DIR']?.trim() ?? '', isEmpty);
    expect(Directory.systemTemp.absolute.path.replaceAll('\\', '/'),
        contains('/tool/qa-local/'));
    final data =
        await Directory(p.join(qa.path, 'data')).create(recursive: true);
    messenger.setMockMethodCallHandler(provider, (_) async => data.path);
    final render = Platform.environment['DAN_PLAYLIST_FEATURE_RENDER_DIR'];
    if (render != null) {
      expect(p.isWithin(qa.absolute.path, Directory(render).absolute.path),
          isTrue);
    }
    await windowManager.ensureInitialized();
    await windowManager.hide();
  });
  tearDownAll(() => messenger.setMockMethodCallHandler(provider, null));

  if (group.isEmpty || group == 'folders') {
    folders.main(onlyRender: true, onlyCase: selected);
  }
  if (group.isEmpty || group == 'visibility') {
    visibility.main(onlyRender: true, onlyCase: selected);
  }
  if (group.isEmpty || group == 'gap') gap.main(onlyRender: true);
  if (group.isEmpty || group == 'motion') {
    motion.main(onlyRender: true, onlyCase: selected);
  }
  if (group.isEmpty || group == 'retarget') {
    retarget.main(onlyRender: true, onlyCase: selected);
  }
}
