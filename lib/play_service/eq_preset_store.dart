import 'dart:convert';
import 'dart:io';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/data/protected_json_store.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:path/path.dart' as p;

class EqPresetStore {
  EqPresetStore(File file)
      : store =
            ProtectedJsonStore(file, validate: validate, maxBytes: 1024 * 1024);
  final ProtectedJsonStore store;
  static Future<EqPresetStore>? _instance;
  static Future<EqPresetStore> get instance =>
      _instance ??= (() async => EqPresetStore(
          File(p.join((await getAppDataDir()).path, 'eq_presets.json'))))();
  static void validatePreset(Map value) {
    final centers = value['frequencies'],
        gains = value['gains'],
        name = value['name'];
    if (value['version'] != 1 ||
        value['kind'] != 'dan-player-eq' ||
        value.keys.any((k) => ![
              'version',
              'kind',
              'id',
              'name',
              'frequencies',
              'gains'
            ].contains(k)) ||
        value['id'] is! String ||
        name is! String ||
        name.trim().isEmpty ||
        name.length > 80 ||
        centers is! List ||
        centers.length != 10 ||
        gains is! List ||
        gains.length != 10) throw const FormatException('Invalid EQ preset');
    for (var i = 0; i < 10; i++) {
      if (centers[i] != BassPlayer.eqBandCenters[i] ||
          gains[i] is! num ||
          !(gains[i] as num).isFinite ||
          (gains[i] as num).abs() > 15)
        throw const FormatException(
            'EQ bands must match and gains must be within ±15 dB');
    }
  }

  static void validate(Map<String, dynamic> root) {
    if (root['version'] != 1 ||
        (root['presets'] != null && root['presets'] is! List))
      throw const FormatException('Invalid EQ store');
    final list = root['presets'] as List? ?? [];
    final ids = <String>{};
    if (list.length > 100) throw const FormatException('最多 100 个用户 EQ 预设');
    for (final v in list) {
      if (v is! Map) throw const FormatException('Invalid EQ preset');
      validatePreset(v);
      if (!ids.add(v['id'])) throw const FormatException('Duplicate EQ preset');
    }
  }

  Future<List<Map<String, dynamic>>> list() async =>
      ((await store.snapshot())['presets'] as List? ?? [])
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList();
  Future<void> add(String name, List<double> gains) => store.update((root) {
        final list = root.putIfAbsent('presets', () => []) as List;
        final names = {for (final p in list) p['name']};
        var next = name.trim();
        var count = 1;
        while (names.contains(next)) {
          next = '${name.trim()} (${count++})';
        }
        list.add({
          'version': 1,
          'kind': 'dan-player-eq',
          'id': 'eq-${DateTime.now().microsecondsSinceEpoch}',
          'name': next,
          'frequencies': BassPlayer.eqBandCenters,
          'gains': List.of(gains)
        });
      });
  Future<void> rename(String id, String name) => store.update((root) {
        for (final v in root['presets'] as List? ?? []) {
          if (v['id'] == id) v['name'] = name.trim();
        }
      });
  Future<void> remove(String id) => store.update((root) {
        (root['presets'] as List? ?? []).removeWhere((p) => p['id'] == id);
      });
  static Future<Map<String, dynamic>> readExchange(File file) async {
    if (await file.length() > 65536)
      throw const FormatException('EQ 文件超过 64 KiB');
    final raw = jsonDecode(await file.readAsString());
    if (raw is! Map) throw const FormatException('Invalid EQ file');
    validatePreset(raw);
    return Map<String, dynamic>.from(raw);
  }
}
