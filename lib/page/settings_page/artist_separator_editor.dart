import 'package:dan_player/component/app_dialog_content.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/hotkeys_helper.dart';
import 'package:dan_player/library/artist_separators.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:desktop_lyric/ui_language.dart';

class ArtistSeparatorEditor extends StatelessWidget {
  const ArtistSeparatorEditor({super.key, this.persist});

  final Future<void> Function()? persist;

  Future<void> _save(List<String> separators) async {
    final settings = AppSettings.instance;
    final previous = settings.artistSeparator;
    final previousPattern = settings.artistSplitPattern;
    settings.artistSeparator = List.of(separators);
    settings.artistSplitPattern = artistSeparatorPattern(separators);
    try {
      if (persist != null) {
        await persist!();
      } else {
        await settings.saveSettings(
            captureWindowSize: false, throwOnError: true, requireCommit: true);
      }
    } catch (_) {
      settings.artistSeparator = previous;
      settings.artistSplitPattern = previousPattern;
      rethrow;
    }
    // Only the derived grouping changes. Keep audio/queue identities and
    // artwork caches instead of reloading the disk index and every Audio.
    final library = AudioLibrary.instance;
    final pattern = RegExp(settings.artistSplitPattern);
    for (final audio in library.audioCollection) {
      audio.splitedArtists = audio.artist.split(pattern);
    }
    library.rebuildDerivedCollections();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return SettingsTile(
      description: ui('自定义艺术家分隔符'),
      subtitle: ui('将一首歌中的多位艺术家分别归类，不修改音乐文件。'),
      icon: Symbols.artist,
      action: FilledButton.icon(
        icon: const Icon(Symbols.edit),
        label: Text(ui('管理艺术家分隔符')),
        onPressed: () => showAppDialog<void>(
          context: context,
          dialogBottomInset: 0,
          builder: (_) => ArtistSeparatorEditDialog(
            initialSeparators: AppSettings.instance.artistSeparator
                .whereType<String>()
                .toList(),
            onSave: _save,
          ),
        ),
      ),
    );
  }
}

class ArtistSeparatorEditDialog extends StatefulWidget {
  const ArtistSeparatorEditDialog({
    super.key,
    required this.initialSeparators,
    required this.onSave,
  });

  final List<String> initialSeparators;
  final Future<void> Function(List<String>) onSave;

  @override
  State<ArtistSeparatorEditDialog> createState() =>
      _ArtistSeparatorEditDialogState();
}

class _ArtistSeparatorEditDialogState extends State<ArtistSeparatorEditDialog> {
  late final _separators =
      widget.initialSeparators.where((s) => s.isNotEmpty).toSet().toList();
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  late final _example = TextEditingController(text: ui('艺术家 A / 艺术家 B、艺术家 C'));
  String? _inputError;
  bool _saving = false;
  bool _saveFailed = false;

  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
    _example.dispose();
    super.dispose();
  }

  bool _add() {
    final separator = _input.text;
    final error = separator.isEmpty
        ? '请输入分隔符。'
        : RegExp(r'[\x00-\x1f\x7f]').hasMatch(separator)
            ? '分隔符不能包含换行或控制字符。'
            : _separators.contains(separator)
                ? '此分隔符已添加。'
                : null;
    setState(() {
      _inputError = error;
      if (error == null) {
        _separators.add(separator);
        _input.clear();
      }
    });
    return error == null;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_input.text.isNotEmpty && !_add()) {
      _inputFocus.requestFocus();
      return;
    }
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    try {
      await widget.onSave(List.unmodifiable(_separators));
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveFailed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final artists = _example.text
        .split(RegExp(artistSeparatorPattern(_separators)))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    return PopScope(
      canPop: !_saving,
      child: Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: AppDialogContent(
          width: 540,
          maxHeight: 640,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppDialogTitle(
                  ui('管理艺术家分隔符'),
                  leading: const Icon(Symbols.artist),
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(ui('将一首歌中的多位艺术家分别归类，不修改音乐文件。'),
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                        const SizedBox(height: 18),
                        Text(ui('已启用的分隔符'), style: theme.textTheme.titleSmall),
                        const SizedBox(height: 8),
                        if (_separators.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(ui('未设置分隔符，将保留完整的艺术家名称。'),
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(color: scheme.onSurfaceVariant)),
                          )
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final separator in _separators)
                                InputChip(
                                  label: Text(separator.trim().isEmpty
                                      ? ui('空格 × {0}', [separator.length])
                                      : '“$separator”'),
                                  deleteIcon:
                                      const Icon(Symbols.close, size: 18),
                                  deleteButtonTooltipMessage:
                                      ui('移除分隔符 {0}', [separator]),
                                  onDeleted: _saving
                                      ? null
                                      : () => setState(() {
                                            _separators.remove(separator);
                                            _inputError = null;
                                          }),
                                ),
                            ],
                          ),
                        const SizedBox(height: 12),
                        Focus(
                          onFocusChange: HotkeysHelper.onFocusChanges,
                          child: TextField(
                            key: const ValueKey('artist-separator-input'),
                            controller: _input,
                            focusNode: _inputFocus,
                            enabled: !_saving,
                            maxLength: 32,
                            textInputAction: TextInputAction.done,
                            decoration: InputDecoration(
                              labelText: ui('添加分隔符'),
                              hintText: ui('例如 /、; 或 &'),
                              counterText: '',
                              errorText:
                                  _inputError == null ? null : ui(_inputError!),
                              errorMaxLines: 3,
                              suffixIcon: IconButton(
                                tooltip: ui('添加'),
                                onPressed: _saving ? null : _add,
                                icon: const Icon(Symbols.add),
                              ),
                            ),
                            onChanged: (_) {
                              if (_inputError != null) {
                                setState(() => _inputError = null);
                              }
                            },
                            onSubmitted: (_) => _add(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Material(
                          color: scheme.surfaceContainerLow,
                          shape: AppShape.control.copyWith(
                              side: BorderSide(color: scheme.outlineVariant)),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(children: [
                                  Icon(Symbols.preview,
                                      size: 20, color: scheme.primary),
                                  const SizedBox(width: 8),
                                  Expanded(
                                      child: Text(ui('拆分预览'),
                                          style: theme.textTheme.titleSmall)),
                                ]),
                                const SizedBox(height: 10),
                                Focus(
                                  onFocusChange: HotkeysHelper.onFocusChanges,
                                  child: TextField(
                                    key: const ValueKey(
                                        'artist-separator-example'),
                                    controller: _example,
                                    enabled: !_saving,
                                    maxLength: 500,
                                    decoration: InputDecoration(
                                      labelText: ui('艺术家文本'),
                                      counterText: '',
                                      isDense: true,
                                    ),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),
                                if (artists.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Wrap(spacing: 8, runSpacing: 8, children: [
                                    for (final name in artists)
                                      DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: scheme.secondaryContainer,
                                          borderRadius: AppShape.smallRadius,
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 6),
                                          child: Text(name,
                                              style: theme.textTheme.bodyMedium
                                                  ?.copyWith(
                                                      color: scheme
                                                          .onSecondaryContainer)),
                                        ),
                                      ),
                                  ]),
                                ],
                              ],
                            ),
                          ),
                        ),
                        if (_saveFailed) ...[
                          const SizedBox(height: 12),
                          Text(ui('保存失败，原设置已保留。请重试。'),
                              style: TextStyle(color: scheme.error)),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                        onPressed:
                            _saving ? null : () => Navigator.pop(context),
                        child: Text(ui('取消'))),
                    FilledButton.icon(
                      key: const ValueKey('artist-separator-save'),
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Symbols.check),
                      label: Text(ui(_saving ? '正在保存…' : '保存')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
