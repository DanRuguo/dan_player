import 'package:desktop_lyric/l10n/ui_catalog.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('menu and online lyric actions are translated in every UI language', () {
    const keys = {
      '填入联网歌词',
      '选择歌词来源',
      '删除',
      '搜索歌词候选失败，请检查网络后重试。',
      '没有找到相关歌词候选，可检查歌曲标签后重试。',
    };
    for (final key in keys) {
      expect(uiCatalog[key], hasLength(3), reason: key);
      for (final language in UiLanguage.values.skip(1)) {
        expect(translateUi(key, language), isNot(key),
            reason: '$key/$language');
      }
    }
  });
}
