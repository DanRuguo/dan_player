import 'dart:convert';
import 'dart:io';

import 'package:dan_player/data/cache_backup_service.dart';
import 'package:dan_player/font/font_preferences.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  test('font settings backup rebases shared custom paths and retains all slots',
      () async {
    final sandbox = await Directory.systemTemp.createTemp('dan-font-backup-');
    addTearDown(() => sandbox.delete(recursive: true));
    final source = await Directory(path.join(sandbox.path, 'source')).create();
    final font = File(path.join(sandbox.path, 'font fixture.ttf'));
    final original = [1, 2, 3, 7, 9];
    await font.writeAsBytes(original);
    final choice =
        AppFontChoice.custom(family: 'Fixture Font 世界', path: font.path);
    final preferences = AppFontPreferences(
        mixedScripts: false, shared: choice, zh: choice, ko: choice);
    await File(path.join(source.path, 'settings.json'))
        .writeAsString(jsonEncode({
      'Fonts': preferences.toJson(),
      'FontFamily': choice.family,
      'FontPath': font.path,
    }));
    const service = CacheBackupService();
    const selection = BackupSelection(components: {BackupComponent.settings});
    final backup = File(path.join(sandbox.path, 'fonts.bak'));
    await service.exportBackup(
        source: source, destination: backup, selection: selection);
    await font.delete();
    Directory? staged;
    final destination = Directory(path.join(sandbox.path, 'restored'));
    final current = await Directory(path.join(sandbox.path, 'current')).create();
    await service.restoreBackup(
        backup: backup,
        destination: destination,
        currentData: current,
        selection: selection,
        activateLocation: (_, value) async => staged = value);
    final json = jsonDecode(
            await File(path.join(staged!.path, 'settings.json')).readAsString())
        as Map;
    final restored = AppFontPreferences.decode(json['Fonts']);
    expect(restored.perLanguage, preferences.perLanguage);
    expect(restored.mixedScripts, preferences.mixedScripts);
    expect(restored.en, preferences.en);
    expect(restored.ja, preferences.ja);
    expect(restored.zh.family, choice.family);
    expect(restored.zh.path, isNot(font.path));
    expect(path.isWithin(destination.path, restored.zh.path!), isTrue);
    expect(restored.shared, restored.zh);
    expect(restored.choiceFor(UiLanguage.ko), restored.zh);
    expect(json['FontPath'], restored.zh.path);
    final copied = File(path.join(staged!.path,
        path.relative(restored.zh.path!, from: destination.path)));
    expect(await copied.readAsBytes(), original);
    final assets = await staged!
        .list(recursive: true)
        .where((entry) => entry is File && path.extension(entry.path) == '.ttf')
        .toList();
    expect(assets, hasLength(1));
  });
}
