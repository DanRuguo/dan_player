import 'package:dan_player/library/audio_metadata_update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native metadata errors expose a readable message and stable code', () {
    final error = AudioMetadataEditException.fromNative(
      'AnyhowException(TAG_FORMAT_UNKNOWN|无法根据文件内容识别音频格式)',
    );
    expect(error.code, 'TAG_FORMAT_UNKNOWN');
    expect(error.message, '无法根据文件内容识别音频格式');
    expect(error.toString(), error.message);
  });

  test('unexpected metadata errors remain readable', () {
    final error = AudioMetadataEditException.fromNative(
      StateError('unexpected failure'),
    );
    expect(error.code, 'TAG_UNKNOWN');
    expect(error.message, contains('unexpected failure'));
  });
}
