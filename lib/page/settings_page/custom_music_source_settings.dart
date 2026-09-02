import 'dart:async';
import 'dart:convert';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/online/custom_music_source_profile.dart';
import 'package:dan_player/utils.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

typedef CustomSourceImportReader = Future<String?> Function();
typedef CustomSourceExportWriter = Future<void> Function(String contents);

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
  });

  final ValueNotifier<List<CustomMusicSourceProfile>>? profiles;
  final Future<void> Function()? persist;

  /// Test seams also keep picker I/O out of widget tests.
  final CustomSourceImportReader? importReader;
  final CustomSourceExportWriter? exportWriter;

  @override
  State<CustomMusicSourceSettings> createState() =>
      _CustomMusicSourceSettingsState();
}

class _CustomMusicSourceSettingsState extends State<CustomMusicSourceSettings> {
  int _saveRevision = 0;
  String? _saveError;
  bool _transferring = false;

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
        showTextOnSnackBar('歌源配置已导出；文件不包含密钥',
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
              title: ui('自定义歌源 API'),
              icon: Symbols.api,
              subtitle: ui('可同时保留多个服务；搜索只返回候选，播放时再解析地址。'),
            ),
            const SizedBox(height: 12),
            Text(
              ui('能力声明不代表永久可用或获得下载授权。不会绕过登录、付费或 DRM；搜索信息会发送到已启用的服务。'),
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
            ui('可添加 Dan Player 通用协议、旧版歌词接口或你自行部署的兼容服务。'),
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
    required this.onEdit,
    required this.onDelete,
  });

  final CustomMusicSourceProfile profile;
  final ValueChanged<bool> onEnabled;
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
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(_capabilityLabel(capability)),
                  ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 6,
            runSpacing: 6,
            children: [
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

class _CustomSourceEditorDialogState extends State<_CustomSourceEditorDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late CustomMusicSourceProtocol _protocol;
  late Set<CustomMusicSourceCapability> _capabilities;
  String? _nameError;
  String? _urlError;
  String? _capabilityError;

  bool get _protocolLocked =>
      widget.profile?.protocol == CustomMusicSourceProtocol.legacyLyrics;

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
    super.dispose();
  }

  void _applyProtocolCapabilities() {
    _capabilities = switch (_protocol) {
      CustomMusicSourceProtocol.legacyLyrics => {
          CustomMusicSourceCapability.lyrics,
        },
      CustomMusicSourceProtocol.goMusicApi => {
          CustomMusicSourceCapability.search,
          CustomMusicSourceCapability.metadata,
          CustomMusicSourceCapability.cover,
          CustomMusicSourceCapability.lyrics,
          CustomMusicSourceCapability.stream,
          CustomMusicSourceCapability.download,
        },
      CustomMusicSourceProtocol.danSourceV1 => _capabilities,
    };
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
      endpoints: switch (_protocol) {
        CustomMusicSourceProtocol.goMusicApi => const {},
        _ => {
            for (final capability in _capabilities) capability: url,
          },
      },
    );
    if (result == null) {
      setState(() => _urlError = ui('该配置无法保存，请检查名称和地址'));
      return;
    }
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final fixedCapabilities =
        _protocol != CustomMusicSourceProtocol.danSourceV1;
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
              decoration: InputDecoration(
                labelText: ui('协议'),
                prefixIcon: const Icon(Symbols.schema),
              ),
              items: [
                for (final protocol in CustomMusicSourceProtocol.values)
                  DropdownMenuItem(
                    value: protocol,
                    child: Text(_protocolLabel(protocol)),
                  ),
              ],
              onChanged: _protocolLocked
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() {
                        _protocol = value;
                        _applyProtocolCapabilities();
                        _capabilityError = null;
                      });
                    },
            ),
            const SizedBox(height: 8),
            Text(
              _protocolDescription(_protocol),
              style: Theme.of(context).textTheme.bodySmall,
            ),
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
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final capability in CustomMusicSourceCapability.values)
                  FilterChip(
                    key: ValueKey('custom-capability-${capability.id}'),
                    selected: _capabilities.contains(capability),
                    onSelected: fixedCapabilities
                        ? null
                        : (selected) => setState(() {
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
                                  _capabilities.remove(
                                      CustomMusicSourceCapability.metadata);
                                  _capabilities.remove(
                                      CustomMusicSourceCapability.cover);
                                }
                              }
                              _capabilityError = null;
                            }),
                    label: Text(_capabilityLabel(capability)),
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

String _protocolLabel(CustomMusicSourceProtocol protocol) => switch (protocol) {
      CustomMusicSourceProtocol.danSourceV1 => ui('Dan Player 通用 v1'),
      CustomMusicSourceProtocol.legacyLyrics => ui('旧版歌词 API'),
      CustomMusicSourceProtocol.goMusicApi => ui('go-music-api（自托管）'),
    };

String _profileDisplayName(CustomMusicSourceProfile profile) {
  if (profile.protocol == CustomMusicSourceProtocol.legacyLyrics) {
    if (profile.name == 'Legacy lyric API') return ui('旧版歌词 API');
    if (profile.name == 'Imported lyric API') return ui('导入的歌词 API');
  }
  return profile.name;
}

String _protocolDescription(CustomMusicSourceProtocol protocol) =>
    switch (protocol) {
      CustomMusicSourceProtocol.danSourceV1 =>
        ui('通用能力协议：按服务实际支持的内容选择；歌曲信息和封面随搜索结果返回。'),
      CustomMusicSourceProtocol.legacyLyrics => ui('兼容原有歌词接口，仅提供歌词候选。'),
      CustomMusicSourceProtocol.goMusicApi =>
        ui('自托管兼容预设：搜索、歌曲信息、封面、歌词、播放解析与授权下载。'),
    };

String _capabilityLabel(CustomMusicSourceCapability capability) =>
    switch (capability) {
      CustomMusicSourceCapability.search => ui('搜索'),
      CustomMusicSourceCapability.metadata => ui('歌曲信息（随搜索）'),
      CustomMusicSourceCapability.cover => ui('封面（随搜索）'),
      CustomMusicSourceCapability.lyrics => ui('歌词'),
      CustomMusicSourceCapability.comments => ui('评论'),
      CustomMusicSourceCapability.stream => ui('播放解析'),
      CustomMusicSourceCapability.download => ui('下载'),
    };
