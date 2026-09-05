import 'dart:async';
import 'dart:convert';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/custom_music_source_probe_dialog.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/online/custom_music_source_profile.dart';
import 'package:dan_player/online/custom_music_source_transport.dart';
import 'package:dan_player/utils.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

typedef CustomSourceImportReader = Future<String?> Function();
typedef CustomSourceExportWriter = Future<void> Function(String contents);
typedef CustomSourceProbe = Future<void> Function(
  CustomMusicSourceProfile profile,
);

/// Manages user-supplied HTTP providers without probing them while settings are
/// being viewed. Search and playback resolution remain separate operations in
/// the provider contract, following the bounded provider pattern used by ECHO.
class CustomMusicSourceSettings extends StatefulWidget {
  const CustomMusicSourceSettings({
    super.key,
    this.profiles,
    this.persist,
    this.importReader,
    this.exportWriter,
    this.probe,
  });

  final ValueNotifier<List<CustomMusicSourceProfile>>? profiles;
  final Future<void> Function()? persist;

  /// Test seams also keep picker I/O out of widget tests.
  final CustomSourceImportReader? importReader;
  final CustomSourceExportWriter? exportWriter;
  final CustomSourceProbe? probe;

  @override
  State<CustomMusicSourceSettings> createState() =>
      _CustomMusicSourceSettingsState();
}

class _CustomMusicSourceSettingsState extends State<CustomMusicSourceSettings> {
  int _saveRevision = 0;
  String? _saveError;
  bool _transferring = false;
  String? _testingId;

  ValueNotifier<List<CustomMusicSourceProfile>> get _profiles =>
      widget.profiles ?? AppSettings.instance.customMusicSources;

  Future<void> _commit(List<CustomMusicSourceProfile> next) async {
    final target = _profiles;
    final revision = ++_saveRevision;
    setState(() => _saveError = null);
    target.value = List<CustomMusicSourceProfile>.unmodifiable(
      next.take(CustomMusicSourceProfileCodec.maximumProfiles),
    );
    try {
      await (widget.persist ??
          () => AppSettings.instance.saveSettings(throwOnError: true))();
    } catch (error, trace) {
      LOGGER.e('[custom source settings] save failed',
          error: error, stackTrace: trace);
      if (!mounted ||
          revision != _saveRevision ||
          !identical(target, _profiles)) {
        return;
      }
      setState(() => _saveError = ui('保存自定义歌源失败；当前修改仍对本次会话生效。'));
    }
  }

  Future<void> _openEditor([CustomMusicSourceProfile? profile]) async {
    final result = await showAppDialog<CustomMusicSourceProfile>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _CustomSourceEditorDialog(profile: profile),
    );
    if (!mounted || result == null) return;
    final next = List<CustomMusicSourceProfile>.of(_profiles.value);
    final index = next.indexWhere((item) => item.id == result.id);
    if (index < 0) {
      if (next.length >= CustomMusicSourceProfileCodec.maximumProfiles) {
        showTextOnSnackBar('最多可保存 {0} 个自定义歌源',
            arguments: [CustomMusicSourceProfileCodec.maximumProfiles],
            kind: AppNoticeKind.warning,
            context: context);
        return;
      }
      next.add(result);
    } else {
      next[index] = result;
    }
    await _commit(next);
  }

  Future<void> _setEnabled(CustomMusicSourceProfile profile, bool enabled) =>
      _commit([
        for (final item in _profiles.value)
          if (item.id == profile.id) item.copyWith(enabled: enabled) else item,
      ]);

  Future<void> _addPreset() async {
    final existingIds = _profiles.value.map((profile) => profile.id).toSet();
    final available = CustomMusicSourceProfile.builtInPresets()
        .where((profile) => !existingIds.contains(profile.id))
        .toList(growable: false);
    if (available.isEmpty) return;
    final selected = await showAppDialog<CustomMusicSourceProfile>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title:
            AppDialogTitle(ui('添加内置预设'), leading: const Icon(Symbols.add_box)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(ui('预设添加后可自由编辑；不会覆盖现有的同名或同 ID 配置。')),
              const SizedBox(height: 10),
              for (final profile in available)
                ListTile(
                  key: ValueKey('custom-source-preset-${profile.id}'),
                  leading: const Icon(Symbols.cloud_download),
                  title: Text(_profileDisplayName(profile)),
                  subtitle: Text(_protocolLabel(profile.protocol)),
                  onTap: () => Navigator.pop(context, profile),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: Text(ui('取消'))),
        ],
      ),
    );
    if (!mounted || selected == null) return;
    if (_profiles.value.any((profile) => profile.id == selected.id)) return;
    if (_profiles.value.length >=
        CustomMusicSourceProfileCodec.maximumProfiles) {
      return;
    }
    await _commit([..._profiles.value, selected]);
  }

  Future<void> _delete(CustomMusicSourceProfile profile) async {
    final confirmed = await showAppDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            scrollable: true,
            title: AppDialogTitle(ui('删除自定义歌源')),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Text(ui('只删除“{0}”的配置，不会删除收藏、歌单或歌曲。', [profile.name])),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(ui('取消')),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Symbols.delete),
                label: Text(ui('删除')),
              ),
            ],
          ),
        ) ==
        true;
    if (!mounted || !confirmed) return;
    await _commit([
      for (final item in _profiles.value)
        if (item.id != profile.id) item,
    ]);
  }

  Future<void> _test(CustomMusicSourceProfile profile) async {
    if (_testingId != null) return;
    if (widget.probe == null) {
      setState(() => _testingId = profile.id);
      try {
        await showCustomMusicSourceProbeDialog(
          context,
          profile: profile,
          onApplyCapabilities: (capabilities) {
            if (!mounted) return;
            final current = _profiles.value
                .where((item) => item.id == profile.id)
                .firstOrNull;
            if (!identical(current, profile)) return;
            unawaited(_commit([
              for (final item in _profiles.value)
                if (item.id == profile.id)
                  item.copyWith(capabilities: capabilities)
                else
                  item,
            ]));
          },
        );
      } finally {
        if (mounted) setState(() => _testingId = null);
      }
      return;
    }
    if (!profile.capabilities.contains(CustomMusicSourceCapability.search)) {
      showTextOnSnackBar('该歌源需在实际歌曲上测试',
          kind: AppNoticeKind.warning, context: context);
      return;
    }
    setState(() => _testingId = profile.id);
    try {
      final probe = profile.enabled ? profile : profile.copyWith(enabled: true);
      if (widget.probe case final test?) {
        await test(probe);
      } else {
        await CustomMusicSourceTransport(probe)
            .search('Dan Player Test', limit: 1);
      }
      if (mounted) {
        showTextOnSnackBar('搜索接口连接正常；其他能力需使用实际歌曲验证',
            kind: AppNoticeKind.success, context: context);
      }
    } catch (error, trace) {
      LOGGER.w('[custom source settings] probe failed', stackTrace: trace);
      if (mounted) {
        showTextOnSnackBar('歌源测试失败：{0}',
            arguments: [_localizedProbeFailure(error)],
            kind: AppNoticeKind.error,
            context: context);
      }
    } finally {
      if (mounted) setState(() => _testingId = null);
    }
  }

  Future<String?> _readImportFile() async {
    if (widget.importReader != null) return widget.importReader!();
    final picker = OpenFilePicker()
      ..title = ui('导入自定义歌源')
      ..defaultExtension = 'json'
      ..filterSpecification = {
        ui('Dan Player 歌源配置'): '*.json',
        ui('所有文件'): '*.*',
      };
    final file = picker.getFile();
    return file?.readAsString(encoding: utf8);
  }

  Future<bool> _writeExportFile(String contents) async {
    if (widget.exportWriter != null) {
      await widget.exportWriter!(contents);
      return true;
    }
    final picker = SaveFilePicker()
      ..title = ui('导出自定义歌源')
      ..fileName = 'DanPlayer-music-sources.json'
      ..defaultExtension = 'json'
      ..filterSpecification = {
        ui('Dan Player 歌源配置'): '*.json',
        ui('所有文件'): '*.*',
      };
    final file = picker.getFile();
    if (file == null) return false;
    await file.writeAsString(contents, encoding: utf8);
    return true;
  }

  Future<void> _import() async {
    if (_transferring) return;
    setState(() => _transferring = true);
    try {
      final raw = await _readImportFile();
      if (!mounted || raw == null) return;
      Object? decoded;
      try {
        decoded = jsonDecode(raw);
      } on FormatException {
        final direct = Uri.tryParse(raw.trim());
        if (direct == null ||
            !(direct.scheme == 'http' || direct.scheme == 'https') ||
            direct.host.isEmpty) {
          rethrow;
        }
        decoded = {
          'apis': [
            {'type': 'lyric', 'url': direct.toString()},
          ],
        };
      }
      final imported = CustomMusicSourceProfileCodec.decodeBackup(decoded);
      if (imported.isEmpty) {
        showTextOnSnackBar('文件中没有可用的歌源配置',
            kind: AppNoticeKind.warning, context: context);
        return;
      }

      final existingIds = _profiles.value.map((item) => item.id).toSet();
      final conflicts = imported.where((item) => existingIds.contains(item.id));
      var decision = _ImportDecision.update;
      if (conflicts.isNotEmpty) {
        final selected = await showAppDialog<_ImportDecision>(
          context: context,
          builder: (context) => AlertDialog(
            scrollable: true,
            title: AppDialogTitle(ui('发现重复配置')),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Text(ui('有 {0} 个配置 ID 已存在。你可以更新这些配置并添加其余项目，或只添加全新的项目。',
                  [conflicts.length])),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(ui('取消')),
              ),
              OutlinedButton(
                onPressed: () =>
                    Navigator.pop(context, _ImportDecision.onlyNew),
                child: Text(ui('仅添加新项')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, _ImportDecision.update),
                child: Text(ui('合并并更新')),
              ),
            ],
          ),
        );
        if (!mounted || selected == null) return;
        decision = selected;
      }

      final incoming = {for (final item in imported) item.id: item};
      final candidate = <CustomMusicSourceProfile>[
        for (final current in _profiles.value)
          if (decision == _ImportDecision.update &&
              incoming.containsKey(current.id))
            incoming.remove(current.id)!
          else
            current,
        for (final item in imported)
          if (!existingIds.contains(item.id)) item,
      ];
      final next = candidate
          .take(CustomMusicSourceProfileCodec.maximumProfiles)
          .toList(growable: false);
      await _commit(next);
      if (!mounted) return;
      final resultById = {for (final item in next) item.id: item};
      final added = imported
          .where((item) =>
              !existingIds.contains(item.id) && resultById.containsKey(item.id))
          .length;
      final updated = decision == _ImportDecision.update
          ? imported
              .where((item) =>
                  existingIds.contains(item.id) && resultById[item.id] == item)
              .length
          : 0;
      final skipped = candidate.length - next.length;
      showTextOnSnackBar(
          skipped == 0
              ? '已导入 {0} 个新配置，更新 {1} 个配置'
              : '已导入 {0} 个新配置，更新 {1} 个配置；{2} 个配置因达到上限未导入',
          arguments: [added, updated, skipped],
          kind: AppNoticeKind.success,
          context: context);
    } catch (error, trace) {
      LOGGER.e('[custom source settings] import failed',
          error: error, stackTrace: trace);
      if (mounted) {
        showTextOnSnackBar('导入失败，请选择有效的 Dan Player 歌源配置',
            kind: AppNoticeKind.error, context: context);
      }
    } finally {
      if (mounted) setState(() => _transferring = false);
    }
  }

  Future<void> _export() async {
    if (_transferring) return;
    setState(() => _transferring = true);
    try {
      final json = const JsonEncoder.withIndent('  ').convert(
        CustomMusicSourceProfileCodec.encodeBackup(_profiles.value),
      );
      final written = await _writeExportFile(json);
      if (mounted && written) {
        showTextOnSnackBar('歌源配置已导出；请勿在地址或公开请求头中填写密钥',
            kind: AppNoticeKind.success, context: context);
      }
    } catch (error, trace) {
      LOGGER.e('[custom source settings] export failed',
          error: error, stackTrace: trace);
      if (mounted) {
        showTextOnSnackBar('导出歌源配置失败',
            kind: AppNoticeKind.error, context: context);
      }
    } finally {
      if (mounted) setState(() => _transferring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<List<CustomMusicSourceProfile>>(
      valueListenable: _profiles,
      builder: (context, profiles, _) => SettingsSurface(
        child: Column(
          key: const ValueKey('custom-music-source-settings'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsHeader(
              title: ui('第三方源'),
              icon: Symbols.api,
              subtitle: ui('内置预设和自行添加的服务都可编辑、启用、停用或删除。搜索与播放解析分开进行。'),
            ),
            const SizedBox(height: 12),
            Text(
              ui('能力以接口实际返回为准；需要登录或受限时会提示，不绕过登录、付费或 DRM。'),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Text(
              ui('停用或删除后立即停止该来源的新请求；已保存的收藏、歌单和歌曲信息不会删除。'),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Text(
              ui('搜索会发送关键词；歌词、评论和播放/下载解析会向所选来源发送来源歌曲 ID 或必要的歌曲信息。'),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Text(
              ui('请勿在地址或公开请求头中填写密钥。'),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('custom-source-add-preset'),
                  onPressed: _transferring ||
                          profiles.length >=
                              CustomMusicSourceProfileCodec.maximumProfiles ||
                          CustomMusicSourceProfile.builtInPresets().every(
                              (preset) => profiles
                                  .any((profile) => profile.id == preset.id))
                      ? null
                      : _addPreset,
                  icon: const Icon(Symbols.add_box),
                  label: Text(ui('添加内置预设')),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('custom-source-import'),
                  onPressed: _transferring ? null : _import,
                  icon: const Icon(Symbols.file_open),
                  label: Text(ui('导入')),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('custom-source-export'),
                  onPressed: _transferring ? null : _export,
                  icon: const Icon(Symbols.backup),
                  label: Text(ui('导出')),
                ),
                FilledButton.icon(
                  key: const ValueKey('custom-source-add'),
                  onPressed: profiles.length >=
                          CustomMusicSourceProfileCodec.maximumProfiles
                      ? null
                      : () => _openEditor(),
                  icon: const Icon(Symbols.add),
                  label: Text(ui('添加歌源')),
                ),
              ],
            ),
            if (_saveError != null) ...[
              const SizedBox(height: 10),
              Semantics(
                liveRegion: true,
                child: Text(_saveError!, style: TextStyle(color: scheme.error)),
              ),
            ],
            const SizedBox(height: 12),
            if (profiles.isEmpty)
              _EmptyCustomSources(onAdd: () => _openEditor())
            else
              for (var index = 0; index < profiles.length; index++) ...[
                _CustomSourceCard(
                  profile: profiles[index],
                  onEnabled: (enabled) =>
                      unawaited(_setEnabled(profiles[index], enabled)),
                  testing: _testingId == profiles[index].id,
                  testBusy: _testingId != null,
                  onTest: () => _test(profiles[index]),
                  onEdit: () => _openEditor(profiles[index]),
                  onDelete: () => _delete(profiles[index]),
                ),
                if (index + 1 < profiles.length) const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }
}

enum _ImportDecision { update, onlyNew }

class _EmptyCustomSources extends StatelessWidget {
  const _EmptyCustomSources({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .36),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(Symbols.api, color: scheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(ui('尚未添加自定义歌源')),
          const SizedBox(height: 4),
          Text(
            ui('可恢复内置预设，或添加歌词 API、通用协议和你自行部署的服务。'),
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Symbols.add),
            label: Text(ui('添加歌源')),
          ),
        ],
      ),
    );
  }
}

class _CustomSourceCard extends StatelessWidget {
  const _CustomSourceCard({
    required this.profile,
    required this.onEnabled,
    required this.testing,
    required this.testBusy,
    required this.onTest,
    required this.onEdit,
    required this.onDelete,
  });

  final CustomMusicSourceProfile profile;
  final ValueChanged<bool> onEnabled;
  final bool testing;
  final bool testBusy;
  final VoidCallback onTest;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final host = Uri.tryParse(profile.baseUrl)?.host ?? profile.baseUrl;
    return Container(
      key: ValueKey('custom-source-profile-${profile.id}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .38),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Icon(Symbols.cloud_sync, color: scheme.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _profileDisplayName(profile),
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_protocolLabel(profile.protocol)} · $host',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Switch(
                key: ValueKey('custom-source-enabled-${profile.id}'),
                value: profile.enabled,
                onChanged: onEnabled,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final capability in CustomMusicSourceCapability.values)
                if (profile.capabilities.contains(capability))
                  _CapabilityLabel(capability),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 6,
            runSpacing: 6,
            children: [
              TextButton.icon(
                key: ValueKey('custom-source-test-${profile.id}'),
                onPressed: testBusy ? null : onTest,
                icon: testing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Symbols.network_check),
                label: Text(ui('测试')),
              ),
              TextButton.icon(
                key: ValueKey('custom-source-edit-${profile.id}'),
                onPressed: onEdit,
                icon: const Icon(Symbols.edit),
                label: Text(ui('编辑')),
              ),
              TextButton.icon(
                key: ValueKey('custom-source-delete-${profile.id}'),
                onPressed: onDelete,
                icon: const Icon(Symbols.delete),
                label: Text(ui('删除')),
                style: TextButton.styleFrom(foregroundColor: scheme.error),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CustomSourceEditorDialog extends StatefulWidget {
  const _CustomSourceEditorDialog({this.profile});

  final CustomMusicSourceProfile? profile;

  @override
  State<_CustomSourceEditorDialog> createState() =>
      _CustomSourceEditorDialogState();
}

class _CapabilityLabel extends StatelessWidget {
  const _CapabilityLabel(this.capability);
  final CustomMusicSourceCapability capability;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_capabilityIcon(capability),
              size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 5),
          Flexible(
            child: Text(_capabilityLabel(capability),
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      );
}

class _CustomSourceEditorDialogState extends State<_CustomSourceEditorDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late final Map<CustomMusicSourceCapability, TextEditingController>
      _endpointControllers;
  late CustomMusicSourceProtocol _protocol;
  late Set<CustomMusicSourceCapability> _capabilities;
  String? _nameError;
  String? _urlError;
  String? _capabilityError;
  String? _endpointError;

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    _nameController = TextEditingController(text: profile?.name ?? '');
    _urlController = TextEditingController(
      text: profile?.protocol == CustomMusicSourceProtocol.legacyLyrics
          ? profile
                  ?.endpointFor(CustomMusicSourceCapability.lyrics)
                  ?.toString() ??
              ''
          : profile?.baseUrl ?? '',
    );
    _protocol = profile?.protocol ?? CustomMusicSourceProtocol.danSourceV1;
    _endpointControllers = {
      for (final capability in CustomMusicSourceCapability.values)
        capability: TextEditingController(text: profile?.endpoints[capability]),
    };
    _capabilities = Set.of(profile?.capabilities ??
        const {
          CustomMusicSourceCapability.search,
          CustomMusicSourceCapability.metadata,
          CustomMusicSourceCapability.cover,
          CustomMusicSourceCapability.lyrics,
          CustomMusicSourceCapability.stream,
        });
    _applyProtocolCapabilities();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    for (final controller in _endpointControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _applyProtocolCapabilities({bool reset = false}) {
    final supported = _supportedCapabilities(_protocol);
    if (reset || _protocol == CustomMusicSourceProtocol.legacyLyrics) {
      _capabilities = Set.of(supported);
    } else {
      _capabilities = _capabilities.intersection(supported);
    }
  }

  void _changeProtocol(CustomMusicSourceProtocol value) {
    _protocol = value;
    _applyProtocolCapabilities(reset: true);
    final defaults = switch (value) {
      CustomMusicSourceProtocol.kugou => CustomMusicSourceProfile.kugouPreset(),
      CustomMusicSourceProtocol.neteaseApi =>
        CustomMusicSourceProfile.neteaseApiPreset(),
      _ => null,
    };
    for (final entry in _endpointControllers.entries) {
      entry.value.text = defaults?.endpoints[entry.key] ?? '';
    }
    if (widget.profile == null && _urlController.text.trim().isEmpty) {
      _urlController.text = defaults?.baseUrl ?? '';
      if (_nameController.text.trim().isEmpty && defaults != null) {
        _nameController.text = defaults.name;
      }
    }
    _capabilityError = null;
    _endpointError = null;
  }

  void _save() {
    final name = _nameController.text.trim();
    final url = _urlController.text.trim();
    final uri = Uri.tryParse(url);
    final validUrl = uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
    setState(() {
      _nameError = name.isEmpty ? ui('请输入名称') : null;
      _urlError = validUrl ? null : ui('请输入 http 或 https 接口地址');
      _capabilityError = _capabilities.isEmpty ? ui('至少选择一项能力') : null;
      _endpointError = null;
    });
    if (_nameError != null || _urlError != null || _capabilityError != null) {
      return;
    }

    final result = CustomMusicSourceProfile.tryCreate(
      id: widget.profile?.id,
      name: name,
      baseUrl: _protocol == CustomMusicSourceProtocol.legacyLyrics
          ? uri!.replace(path: '', query: null, fragment: null).toString()
          : url,
      enabled: widget.profile?.enabled ?? true,
      protocol: _protocol,
      capabilities: _capabilities,
      endpoints: _protocol == CustomMusicSourceProtocol.legacyLyrics
          ? {
              CustomMusicSourceCapability.lyrics: url,
            }
          : _editedEndpoints(url),
      publicHeaders: widget.profile?.publicHeaders ?? const {},
      authentication: widget.profile?.authentication,
    );
    if (result == null) {
      setState(() => _urlError = ui('该配置无法保存，请检查名称和地址'));
      return;
    }
    if (_protocol != CustomMusicSourceProtocol.legacyLyrics &&
        result.endpoints.length != _editedEndpoints(url).length) {
      setState(() => _endpointError = ui('接口地址无效，请使用 http(s) 地址或相对路径。'));
      return;
    }
    Navigator.pop(context, result);
  }

  Map<CustomMusicSourceCapability, String> _editedEndpoints(String url) => {
        for (final capability in _capabilities)
          if (_endpointControllers[capability]!.text.trim().isNotEmpty)
            capability: _endpointControllers[capability]!.text.trim()
          else if (_protocol == CustomMusicSourceProtocol.danSourceV1 &&
              capability != CustomMusicSourceCapability.metadata &&
              capability != CustomMusicSourceCapability.cover)
            capability: url,
      };

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return AlertDialog(
      scrollable: true,
      title: AppDialogTitle(
        ui(widget.profile == null ? '添加自定义歌源' : '编辑自定义歌源'),
        leading: const Icon(Symbols.api),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('custom-source-name'),
              controller: _nameController,
              decoration: InputDecoration(
                labelText: ui('名称'),
                errorText: _nameError,
                prefixIcon: const Icon(Symbols.label),
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<CustomMusicSourceProtocol>(
              key: const ValueKey('custom-source-protocol'),
              initialValue: _protocol,
              isExpanded: true,
              itemHeight: null,
              decoration: InputDecoration(
                labelText: ui('协议'),
                prefixIcon: const Icon(Symbols.schema),
              ),
              items: [
                for (final protocol in CustomMusicSourceProtocol.values)
                  DropdownMenuItem(
                    value: protocol,
                    child: Text(_protocolLabel(protocol),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
              ],
              selectedItemBuilder: (context) => [
                for (final protocol in CustomMusicSourceProtocol.values)
                  Text(_protocolLabel(protocol),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _changeProtocol(value));
              },
            ),
            const SizedBox(height: 8),
            Text(
              _protocolDescription(_protocol),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_protocol == CustomMusicSourceProtocol.danSourceV1) ...[
              const SizedBox(height: 6),
              Text(
                ui('歌曲信息和封面留空时使用搜索结果；封面地址应返回图片。'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('custom-source-url'),
              controller: _urlController,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: ui(
                    _protocol == CustomMusicSourceProtocol.legacyLyrics
                        ? '歌词接口地址'
                        : '服务地址'),
                hintText: 'https://example.com/api',
                errorText: _urlError,
                prefixIcon: const Icon(Symbols.link),
              ),
            ),
            const SizedBox(height: 16),
            Text(ui('能力'), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (_protocol == CustomMusicSourceProtocol.legacyLyrics)
              const _CapabilityLabel(CustomMusicSourceCapability.lyrics)
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final capability in CustomMusicSourceCapability.values)
                    if (_supportedCapabilities(_protocol).contains(capability))
                      FilterChip(
                        key: ValueKey('custom-capability-${capability.id}'),
                        selected: _capabilities.contains(capability),
                        onSelected: (selected) => setState(() {
                          if (selected) {
                            _capabilities.add(capability);
                            if (capability ==
                                    CustomMusicSourceCapability.metadata ||
                                capability ==
                                    CustomMusicSourceCapability.cover) {
                              _capabilities
                                  .add(CustomMusicSourceCapability.search);
                            }
                          } else {
                            _capabilities.remove(capability);
                            if (capability ==
                                CustomMusicSourceCapability.search) {
                              _capabilities
                                  .remove(CustomMusicSourceCapability.metadata);
                              _capabilities
                                  .remove(CustomMusicSourceCapability.cover);
                            }
                          }
                          _capabilityError = null;
                        }),
                        label: Text(_capabilityLabel(capability)),
                        avatar: Icon(_capabilityIcon(capability), size: 18),
                      ),
                ],
              ),
            if (_capabilityError != null) ...[
              const SizedBox(height: 6),
              Text(
                _capabilityError!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_protocol != CustomMusicSourceProtocol.legacyLyrics) ...[
              const SizedBox(height: 12),
              ExpansionTile(
                key: const ValueKey('custom-source-endpoints'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                title: Text(ui('独立接口地址（可选）')),
                subtitle: Text(ui('单独填写的地址优先使用；相对路径以服务地址为起点。')),
                children: [
                  for (final capability in CustomMusicSourceCapability.values)
                    if (_capabilities.contains(capability))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: TextField(
                          key: ValueKey('custom-endpoint-${capability.id}'),
                          controller: _endpointControllers[capability],
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          decoration: InputDecoration(
                            labelText: _capabilityLabel(capability),
                            prefixIcon: Icon(_capabilityIcon(capability)),
                          ),
                        ),
                      ),
                ],
              ),
            ],
            if (_endpointError != null)
              Text(_endpointError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (_protocol == CustomMusicSourceProtocol.goMusicApi) ...[
              const SizedBox(height: 12),
              Text(
                ui('此预设需要你自行部署兼容服务；Dan Player 不代为提供服务器或平台凭据。'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(ui('取消')),
        ),
        FilledButton.icon(
          key: const ValueKey('custom-source-save'),
          onPressed: _save,
          icon: const Icon(Symbols.save),
          label: Text(ui('保存')),
        ),
      ],
    );
  }
}

String _localizedProbeFailure(Object error) {
  if (error is! CustomMusicSourceException) return ui('网络请求失败');
  return switch (error.kind) {
    CustomMusicSourceFailureKind.timeout => ui('连接超时'),
    CustomMusicSourceFailureKind.credentialsNotConfigured => ui('凭据尚未配置'),
    CustomMusicSourceFailureKind.unavailable => ui('歌源配置尚不可用'),
    CustomMusicSourceFailureKind.cancelled => ui('测试已取消'),
    CustomMusicSourceFailureKind.http =>
      ui('接口返回 HTTP {0}', [error.statusCode ?? '—']),
    CustomMusicSourceFailureKind.redirect ||
    CustomMusicSourceFailureKind.responseTooLarge ||
    CustomMusicSourceFailureKind.invalidResponse =>
      ui('接口响应格式不可识别'),
    CustomMusicSourceFailureKind.network => ui('网络请求失败'),
  };
}

String _protocolLabel(CustomMusicSourceProtocol protocol) => switch (protocol) {
      CustomMusicSourceProtocol.danSourceV1 => ui('Dan Player 通用 v1'),
      CustomMusicSourceProtocol.legacyLyrics => ui('歌词 API'),
      CustomMusicSourceProtocol.goMusicApi => ui('go-music-api（自托管）'),
      CustomMusicSourceProtocol.kugou => ui('酷狗接口'),
      CustomMusicSourceProtocol.neteaseApi => ui('网易云增强 API（自托管）'),
    };

String _profileDisplayName(CustomMusicSourceProfile profile) {
  if (profile.protocol == CustomMusicSourceProtocol.neteaseApi &&
      profile.name == '网易云增强 API') {
    return ui('网易云增强 API');
  }
  if (profile.protocol == CustomMusicSourceProtocol.legacyLyrics) {
    if (profile.name == 'Legacy lyric API' ||
        profile.name == 'Imported lyric API') {
      return 'LRC API';
    }
  }
  return profile.name;
}

String _protocolDescription(CustomMusicSourceProtocol protocol) =>
    switch (protocol) {
      CustomMusicSourceProtocol.danSourceV1 =>
        ui('通用能力协议：按服务实际支持的内容选择，可分别填写接口地址。'),
      CustomMusicSourceProtocol.legacyLyrics =>
        ui('歌词接口：接收歌曲信息并返回歌词；可更换协议以配置其他能力。'),
      CustomMusicSourceProtocol.goMusicApi => ui('自托管兼容接口：能力按服务实际返回执行。'),
      CustomMusicSourceProtocol.neteaseApi =>
        ui('连接自己部署的网易云增强 API，支持搜索、歌词、评论和歌曲信息；音频以服务实际权限为准。'),
      CustomMusicSourceProtocol.kugou =>
        ui('酷狗兼容接口：可分别配置搜索、歌曲信息、封面、歌词、播放和下载地址。'),
    };

String _capabilityLabel(CustomMusicSourceCapability capability) =>
    switch (capability) {
      CustomMusicSourceCapability.search => ui('搜索'),
      CustomMusicSourceCapability.metadata => ui('歌曲信息'),
      CustomMusicSourceCapability.cover => ui('封面'),
      CustomMusicSourceCapability.lyrics => ui('歌词'),
      CustomMusicSourceCapability.comments => ui('评论'),
      CustomMusicSourceCapability.stream => ui('播放解析'),
      CustomMusicSourceCapability.download => ui('下载'),
    };

IconData _capabilityIcon(CustomMusicSourceCapability capability) =>
    switch (capability) {
      CustomMusicSourceCapability.search => Symbols.search,
      CustomMusicSourceCapability.metadata => Symbols.info,
      CustomMusicSourceCapability.cover => Symbols.image,
      CustomMusicSourceCapability.lyrics => Symbols.lyrics,
      CustomMusicSourceCapability.comments => Symbols.comment,
      CustomMusicSourceCapability.stream => Symbols.play_circle,
      CustomMusicSourceCapability.download => Symbols.download,
    };

Set<CustomMusicSourceCapability> _supportedCapabilities(
        CustomMusicSourceProtocol protocol) =>
    switch (protocol) {
      CustomMusicSourceProtocol.legacyLyrics => const {
          CustomMusicSourceCapability.lyrics,
        },
      CustomMusicSourceProtocol.goMusicApi ||
      CustomMusicSourceProtocol.neteaseApi ||
      CustomMusicSourceProtocol.kugou ||
      CustomMusicSourceProtocol.danSourceV1 =>
        CustomMusicSourceCapability.values.toSet(),
    };
