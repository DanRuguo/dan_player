import 'dart:async';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/background_image_store.dart';
import 'package:dan_player/background_preferences.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/library/artwork_image_provider.dart';
import 'package:dan_player/library/artwork_size.dart';
import 'package:dan_player/window_backdrop.dart';
import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:desktop_lyric/ui_language.dart';

class BackgroundSettingsPanel extends StatefulWidget {
  const BackgroundSettingsPanel({
    super.key,
    this.preferences,
    this.status,
    this.onSave,
    this.imageStore,
    this.pickImage,
  });

  final ValueNotifier<BackgroundPreferences>? preferences;
  final ValueListenable<WindowBackdropStatus>? status;
  final Future<void> Function()? onSave;
  final BackgroundImageStore? imageStore;
  final FutureOr<String?> Function()? pickImage;

  @override
  State<BackgroundSettingsPanel> createState() =>
      _BackgroundSettingsPanelState();
}

class _BackgroundSettingsPanelState extends State<BackgroundSettingsPanel> {
  BackgroundScene _scene = BackgroundScene.main;
  int _saveRevision = 0;
  int _importRevision = 0;
  bool _imageBusy = false;
  String? _saveError;
  String? _imageMessage;
  bool _imageFailed = false;
  ValueNotifier<BackgroundPreferences> get _preferences =>
      widget.preferences ?? AppSettings.instance.backgrounds;
  BackgroundImageStore get _images =>
      widget.imageStore ?? BackgroundImageStore.instance;

  static String? _pickImage() => (OpenFilePicker()
        ..title = ui("选择自定义背景图片")
        ..filterSpecification = {
          ui("静态图片（PNG / JPEG / WebP / BMP）"):
              '*.png;*.jpg;*.jpeg;*.webp;*.bmp',
        })
      .getFile()
      ?.path;

  void _cancelImport() {
    _importRevision++;
    _imageBusy = false;
  }

  void _selectSource(BackgroundSource source) {
    final value = _preferences.value.forScene(_scene);
    if (source == BackgroundSource.customImage &&
        !isBackgroundImageId(value.customImageId)) {
      unawaited(_chooseImage());
      return;
    }
    setState(_cancelImport);
    _update(value.copyWith(source: source));
  }

  Future<void> _chooseImage() async {
    if (_imageBusy) return;
    final revision = ++_importRevision;
    final scene = _scene;
    final preferences = _preferences;
    setState(() {
      _imageBusy = true;
      _imageMessage = null;
    });
    try {
      final picker = widget.pickImage ?? _pickImage;
      final selected = await picker();
      if (selected == null ||
          !mounted ||
          revision != _importRevision ||
          !identical(preferences, _preferences)) {
        return;
      }
      final image = await _images.importFile(selected);
      if (!mounted ||
          revision != _importRevision ||
          !identical(preferences, _preferences)) {
        return;
      }
      // Commit only after validation and the managed file rename. Keep edits
      // made to this scene's blur/veil while its import was pending.
      preferences.value = preferences.value.withScene(
        scene,
        preferences.value.forScene(scene).copyWith(
              source: BackgroundSource.customImage,
              customImageId: image.id,
              customImageName: image.name,
            ),
      );
      setState(() {
        _imageFailed = false;
        _imageMessage = ui("已为{0}保存背景副本，原图片未修改。", [ui(scene.label)]);
      });
      await _save();
    } catch (error) {
      if (!mounted || revision != _importRevision) return;
      setState(() {
        _imageFailed = true;
        _imageMessage = error is BackgroundImageException
            ? ui(error.message)
            : ui("无法读取或保存图片，请检查文件与目录权限。原背景未改变。");
      });
    } finally {
      if (mounted && revision == _importRevision) {
        setState(() => _imageBusy = false);
      }
    }
  }

  Future<void> _cleanImages() async {
    if (_imageBusy) return;
    final revision = ++_importRevision;
    setState(() => _imageBusy = true);
    try {
      final removed =
          await _images.removeUnused(() => _preferences.value.retainedImageIds);
      if (!mounted || revision != _importRevision) return;
      setState(() {
        _imageFailed = false;
        _imageMessage = ui("已清理 {0} 个未使用的背景副本；当前选择和原图片均保留。", [removed]);
      });
    } catch (_) {
      if (!mounted || revision != _importRevision) return;
      setState(() {
        _imageFailed = true;
        _imageMessage = ui("清理背景副本失败，请检查已保存配置和目录权限。");
      });
    } finally {
      if (mounted && revision == _importRevision) {
        setState(() => _imageBusy = false);
      }
    }
  }

  void _update(BackgroundAppearance value, {bool save = true}) {
    _preferences.value = _preferences.value.withScene(_scene, value);
    if (save) unawaited(_save());
  }

  Future<void> _save() async {
    final revision = ++_saveRevision;
    final preferences = _preferences;
    if (mounted) setState(() => _saveError = null);
    try {
      await (widget.onSave?.call() ??
          AppSettings.instance.saveSettings(throwOnError: true));
    } catch (_) {
      if (!mounted ||
          revision != _saveRevision ||
          !identical(preferences, _preferences)) {
        return;
      }
      setState(() => _saveError = ui("保存背景设置失败；当前选择仍对本次会话生效。"));
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return ValueListenableBuilder<BackgroundPreferences>(
      valueListenable: _preferences,
      builder: (context, preferences, _) {
        final value = preferences.forScene(_scene);
        final enabled = value.source != BackgroundSource.solid;
        final scheme = Theme.of(context).colorScheme;
        return SettingsSurface(
          key: const ValueKey('background-settings'),
          padding: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SettingsHeader(
                    title: ui("背景与毛玻璃"),
                    icon: Icons.wallpaper_outlined,
                    subtitle: ui("三个界面独立设置。主窗口的标题栏、侧栏和边缘共用背景；主内容面板保持清晰。")),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final scene in BackgroundScene.values)
                    ChoiceChip(
                      key: ValueKey('background-scene-${scene.name}'),
                      label: Text(ui(scene.label)),
                      selected: _scene == scene,
                      onSelected: (_) => setState(() => _scene = scene),
                    ),
                ]),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final source in BackgroundSource.values)
                    ChoiceChip(
                      key: ValueKey('background-source-${source.name}'),
                      showCheckmark: false,
                      avatar: Icon(
                          switch (source) {
                            BackgroundSource.solid => Icons.blur_off_rounded,
                            BackgroundSource.desktop =>
                              Icons.desktop_windows_outlined,
                            BackgroundSource.artwork => Icons.album_outlined,
                            BackgroundSource.customImage =>
                              Icons.image_outlined,
                          },
                          size: 20),
                      label: Text(ui(source.label)),
                      selected: value.source == source,
                      onSelected: (_) => _selectSource(source),
                    ),
                ]),
                const SizedBox(height: 12),
                Text(switch (value.source) {
                  BackgroundSource.solid =>
                    ui("使用实色背景，不显示桌面或专辑图片；再次开启会保留原来的参数。"),
                  BackgroundSource.desktop =>
                    ui("随窗口后方的真实桌面变化，不随歌曲换封面。模糊半径由 Windows 管理。"),
                  BackgroundSource.artwork =>
                    ui("随当前歌曲的专辑封面变化。仅模糊背景，歌曲封面、文字和按钮保持清晰。"),
                  BackgroundSource.customImage =>
                    ui("使用已导入的图片副本，不随歌曲切换；移动或删除原图片不影响此背景。"),
                }),
                const SizedBox(height: 12),
                _imageControls(value),
                const SizedBox(height: 12),
                _slider(
                  icon: Icons.opacity,
                  name: ui("背景透明度"),
                  suffix: '${((1 - value.opacity) * 100).round()}%',
                  hint: ui("数值越大，背景越明显；文字和按钮本身不会变透明。"),
                  slider: Slider(
                    key: const ValueKey('background-opacity'),
                    value: (1 - value.opacity).clamp(.05, .75),
                    min: .05,
                    max: .75,
                    divisions: 70,
                    label: '${((1 - value.opacity) * 100).round()}%',
                    semanticFormatterCallback: (v) =>
                        ui("背景透明度 {0}%", [(v * 100).round()]),
                    onChanged: enabled
                        ? (v) =>
                            _update(value.copyWith(opacity: 1 - v), save: false)
                        : null,
                    onChangeEnd: enabled ? (_) => unawaited(_save()) : null,
                  ),
                ),
                if (value.source.usesImage) ...[
                  const SizedBox(height: 8),
                  _slider(
                    icon: Icons.blur_on,
                    name: value.source == BackgroundSource.customImage
                        ? ui("图片模糊强度")
                        : ui("封面模糊强度"),
                    suffix: value.blur.round().toString(),
                    hint: ui("数值越大越柔和；调整不会降低前景专辑封面的清晰度。"),
                    slider: Slider(
                      key: const ValueKey('background-blur'),
                      value: value.blur.clamp(BackgroundAppearance.minBlur,
                          BackgroundAppearance.maxBlur),
                      min: BackgroundAppearance.minBlur,
                      max: BackgroundAppearance.maxBlur,
                      divisions: 46,
                      label: value.blur.round().toString(),
                      semanticFormatterCallback: (v) =>
                          ui("封面模糊强度 {0}", [v.round()]),
                      onChanged: (v) =>
                          _update(value.copyWith(blur: v), save: false),
                      onChangeEnd: (_) => unawaited(_save()),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                SettingsSwitchTile(
                  surface: false,
                  icon: Icons.animation,
                  controlKey: const ValueKey('background-motion'),
                  contentPadding: SettingsSurface.embeddedRowPadding,
                  title: Text(ui("轻缓动态背景")),
                  subtitle: Text(value.source.usesImage
                      ? ui("让背景图片缓慢漂移。暂停、窗口隐藏或减少动态效果时停止；不会移动文字与按钮。")
                      : ui("仅适用于专辑封面或自定义图片，不改变真实窗后背景。")),
                  value: value.motion,
                  onChanged: value.source.usesImage
                      ? (motion) => _update(value.copyWith(motion: motion))
                      : null,
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<WindowBackdropStatus>(
                  valueListenable:
                      widget.status ?? WindowBackdropService.instance,
                  builder: (_, status, __) => Text(
                    value.source == BackgroundSource.desktop
                        ? ui("{0}。高对比度或系统不支持时自动使用实色。", [ui(status.description)])
                        : ui("背景来源与“专辑封面动态配色”分别控制。高对比度模式会关闭模糊。"),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (_saveError != null) ...[
                  const SizedBox(height: 8),
                  Semantics(
                    liveRegion: true,
                    child: Text(_saveError!,
                        key: const ValueKey('background-save-error'),
                        style: TextStyle(color: scheme.error)),
                  ),
                ],
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    key: const ValueKey('background-reset'),
                    onPressed: () {
                      setState(_cancelImport);
                      _update(const BackgroundPreferences().forScene(_scene));
                    },
                    icon: const Icon(Icons.restore_rounded, size: 20),
                    label: Text(ui("还原{0}默认背景", [ui(_scene.label)])),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _imageControls(BackgroundAppearance value) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isBackgroundImageId(value.customImageId)) ...[
            _BackgroundPreview(
              imageId: value.customImageId!,
              name: value.customImageName ?? ui("已导入的背景"),
              store: _images,
            ),
            const SizedBox(height: 8),
          ],
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.tonalIcon(
              key: const ValueKey('background-pick-image'),
              onPressed: _imageBusy ? null : _chooseImage,
              icon: _imageBusy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.image_outlined, size: 20),
              label: Text(isBackgroundImageId(value.customImageId)
                  ? ui("更换自定义图片")
                  : ui("选择自定义图片")),
            ),
            if (isBackgroundImageId(value.customImageId))
              TextButton.icon(
                key: const ValueKey('background-clear-image'),
                onPressed: _imageBusy
                    ? null
                    : () {
                        setState(_cancelImport);
                        _update(value.copyWith(
                          clearCustomImage: true,
                          source: value.source == BackgroundSource.customImage
                              ? const BackgroundPreferences()
                                  .forScene(_scene)
                                  .source
                              : value.source,
                        ));
                      },
                icon: const Icon(Icons.hide_image_outlined, size: 20),
                label: Text(ui("移除图片选择")),
              ),
            TextButton.icon(
              key: const ValueKey('background-clean-images'),
              onPressed: _imageBusy ? null : _cleanImages,
              icon: const Icon(Icons.cleaning_services_outlined, size: 20),
              label: Text(ui("清理未使用副本")),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            ui("支持静态 PNG、JPEG、WebP、BMP，最多 20 MiB / 4000 万像素。背景副本最长边 2048 像素，不修改原图或前景封面。"),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_imageMessage != null) ...[
            const SizedBox(height: 6),
            Semantics(
              liveRegion: true,
              child: Text(_imageMessage!,
                  key: const ValueKey('background-image-message'),
                  style: TextStyle(
                      color: _imageFailed
                          ? Theme.of(context).colorScheme.error
                          : null)),
            ),
          ],
        ],
      );

  Widget _slider(
          {required IconData icon,
          required String name,
          required String suffix,
          required String hint,
          required Widget slider}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              runSpacing: 4,
              children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon,
                      size: 22, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 12),
                  Flexible(child: Text(name)),
                ]),
                Text(suffix),
              ]),
          slider,
          Text(hint, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

class _BackgroundPreview extends StatefulWidget {
  const _BackgroundPreview(
      {required this.imageId, required this.name, required this.store});
  final String imageId;
  final String name;
  final BackgroundImageStore store;

  @override
  State<_BackgroundPreview> createState() => _BackgroundPreviewState();
}

class _BackgroundPreviewState extends State<_BackgroundPreview> {
  late Future<ImageProvider?> _image;
  @override
  void initState() {
    super.initState();
    _image = widget.store.imageFor(widget.imageId);
  }

  @override
  void didUpdateWidget(covariant _BackgroundPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageId != widget.imageId ||
        oldWidget.store != widget.store) {
      _image = widget.store.imageFor(widget.imageId);
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    Widget unavailable() => Center(child: Text(ui("背景副本不可用，请重新选择图片。")));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ClipRRect(
        borderRadius: AppShape.controlRadius,
        child: SizedBox(
          height: 112,
          child: LayoutBuilder(
            builder: (context, constraints) => FutureBuilder<ImageProvider?>(
              future: _image,
              builder: (_, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return Center(child: Text(ui("正在读取背景副本…")));
                }
                final image = snapshot.data;
                return image == null
                    ? unavailable()
                    : Image(
                        image: ArtworkImageProvider(
                            image,
                            ArtworkSize.forDisplay(
                              logicalWidth: constraints.maxWidth,
                              logicalHeight: constraints.maxHeight,
                              devicePixelRatio:
                                  MediaQuery.devicePixelRatioOf(context),
                            )),
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.high,
                        gaplessPlayback: true,
                        excludeFromSemantics: true,
                        errorBuilder: (_, __, ___) => unavailable(),
                      );
              },
            ),
          ),
        ),
      ),
      const SizedBox(height: 4),
      Tooltip(message: widget.name, child: Text(widget.name)),
    ]);
  }
}
