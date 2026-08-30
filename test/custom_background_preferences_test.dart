import 'dart:convert';

import 'package:dan_player/background_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final imageId = '${'a' * 64}.png';

  test('old maps preserve desktop defaults and leave motion disabled', () {
    final value = BackgroundPreferences.fromMap(const {
      'main': {'source': 'desktop', 'opacity': .7, 'blur': 48},
      'nowPlaying': {'source': 'artwork', 'opacity': .54, 'blur': 64},
    });
    expect(value, const BackgroundPreferences());
    expect(value.main.motion, isFalse);
    expect(value.retainedImageIds, isEmpty);
  });

  test('custom asset and motion round trip independently per scene', () {
    const original = BackgroundPreferences();
    for (final scene in BackgroundScene.values) {
      final value = original.withScene(
          scene,
          original.forScene(scene).copyWith(
                source: BackgroundSource.customImage,
                customImageId: imageId,
                customImageName: '旅行图片.png',
                motion: true,
              ));
      expect(
          BackgroundPreferences.fromMap(jsonDecode(jsonEncode(value.toMap()))),
          value);
      for (final other
          in BackgroundScene.values.where((value) => value != scene)) {
        expect(value.forScene(other), original.forScene(other));
      }
    }
  });

  test(
      'inactive custom selections are retained; explicit removal clears both labels',
      () {
    final image = const BackgroundAppearance().copyWith(
        source: BackgroundSource.customImage,
        customImageId: imageId,
        customImageName: 'picture.png',
        motion: true);
    final off = image.copyWith(source: BackgroundSource.desktop);
    expect(off.customImageId, imageId);
    expect(off.motion, isTrue);
    expect(BackgroundPreferences(main: off).retainedImageIds, {imageId});
    final removed = off.copyWith(clearCustomImage: true);
    expect(removed.customImageId, isNull);
    expect(removed.customImageName, isNull);
    expect(BackgroundPreferences(main: removed).retainedImageIds, isEmpty);
  });

  test('URLs, paths, malformed identifiers and nonboolean motion are ignored',
      () {
    for (final bad in [
      null,
      '../cover.png',
      'C:\\Pictures\\cover.png',
      'https://example.com/a.png',
      'A' * 64 + '.png',
      5,
      {'id': imageId}
    ]) {
      final value = BackgroundPreferences.fromMap({
        'main': {
          'source': 'customImage',
          'customImageId': bad,
          'customImageName': 'should not survive',
          'motion': 'true'
        },
      });
      expect(value.main.customImageId, isNull);
      expect(value.main.customImageName, isNull);
      expect(value.main.motion, isFalse);
      expect(value.retainedImageIds, isEmpty);
    }
  });

  test('image name is display-only and bounded', () {
    final value = BackgroundPreferences.fromMap({
      'main': {
        'customImageId': imageId,
        'customImageName': '${'名' * 250}\u0000'
      },
    });
    expect(value.main.customImageName!.length, 180);
    expect(value.main.customImageName, isNot(contains('\u0000')));
  });

  test(
      'motion does not change native policy or merge image and desktop sources',
      () {
    final value = const BackgroundPreferences().withScene(
        BackgroundScene.main, const BackgroundAppearance(motion: true));
    expect(value.needsNativeGlass, isTrue);
    expect(value.main.source, BackgroundSource.desktop);
    expect(value.main.source.usesImage, isFalse);
    expect(BackgroundSource.customImage.usesImage, isTrue);
    expect(BackgroundSource.solid.usesImage, isFalse);
  });
}
