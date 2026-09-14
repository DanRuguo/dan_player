import 'package:dan_player/component/app_dialog_actions.dart';
import 'package:dan_player/component/app_dialog_content.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/font_preview_loader.dart';
import 'package:dan_player/src/rust/api/installed_font.dart';
import 'package:dan_player/theme_provider.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

class FontSelectorDialog extends StatefulWidget {
  const FontSelectorDialog({
    super.key,
    required this.installedFont,
    this.currentFont,
    this.loader,
  });
  final List<InstalledFont> installedFont;
  final String? currentFont;
  final FontPreviewLoader? loader;

  @override
  State<FontSelectorDialog> createState() => _FontSelectorDialogState();
}

class _FontSelectorDialogState extends State<FontSelectorDialog> {
  final _search = TextEditingController();
  final _sample =
      TextEditingController(text: 'Dan Player  Aa 123\n音乐 · 音楽 · 음악');
  final _scroll = ScrollController();
  late final _current = widget.currentFont ?? ThemeProvider.instance.fontFamily;
  late final List<InstalledFont> _fonts = [...widget.installedFont.toSet()]
    ..sort((a, b) {
      if (a.fullName == _current && b.fullName != _current) return -1;
      if (b.fullName == _current && a.fullName != _current) return 1;
      return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
    });
  InstalledFont? _selected;
  FontPreviewLease? _preview;
  String? _selectedFamily;
  int _selectionGeneration = 0;
  bool _previewFailed = false;

  FontPreviewLoader get _loader => widget.loader ?? FontPreviewLoader.instance;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _select(_fonts.where((font) => font.fullName == _current).firstOrNull,
        explicit: false);
  }

  void _select(InstalledFont? font, {bool explicit = true}) {
    if (font == null || (font == _selected && _selectedFamily != null)) return;
    _preview?.release();
    final generation = ++_selectionGeneration;
    _selected = font;
    _selectedFamily = null;
    _previewFailed = false;
    final request = _preview = _loader.acquire(font, explicit: explicit);
    request.family.then((family) {
      if (!mounted || generation != _selectionGeneration) return;
      setState(() {
        _selectedFamily = family;
        _previewFailed = family == null && !request.deferred;
      });
    });
  }

  @override
  void dispose() {
    _preview?.release();
    _search.dispose();
    _sample.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final query = _search.text.trim().toLowerCase();
    final visible = _fonts
        .where((font) =>
            query.isEmpty || font.fullName.toLowerCase().contains(query))
        .toList(growable: false);
    return Dialog(
      child: AppDialogContent(
        width: 640,
        maxHeight: 660,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              child: CustomScrollView(
                key: const ValueKey('font-selector-scroll'),
                controller: _scroll,
                shrinkWrap: true,
                scrollCacheExtent: const ScrollCacheExtent.pixels(0),
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppDialogTitle(ui('选择字体'),
                            style: theme.textTheme.titleLarge
                                ?.copyWith(color: scheme.onSurface),
                            leading:
                                Icon(Icons.text_fields, color: scheme.primary)),
                        const SizedBox(height: 10),
                        Text(ui('字体名称使用自身样式显示；选择后可预览，点击应用才会更改界面。'),
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                        const SizedBox(height: 16),
                        TextField(
                          key: const ValueKey('font-selector-search'),
                          controller: _search,
                          decoration: InputDecoration(
                            labelText: ui('搜索字体'),
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: query.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: ui('清除搜索'),
                                    onPressed: _search.clear,
                                    icon: const Icon(Icons.close),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerLow,
                            borderRadius: AppShape.controlRadius,
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                    ui('当前字体：{0}',
                                        [danFontDisplayName(_current)]),
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                            color: scheme.onSurfaceVariant)),
                                const SizedBox(height: 8),
                                Text(_selected?.fullName ?? ui('选择字体以预览'),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                            color: scheme.primary,
                                            fontFamily: _selectedFamily,
                                            fontFamilyFallback:
                                                danFontFamilyFallback)),
                                const SizedBox(height: 8),
                                TextField(
                                  key: const ValueKey('font-selector-preview'),
                                  controller: _sample,
                                  minLines: 2,
                                  maxLines: 3,
                                  // Let the dialog retain vertical drag/wheel
                                  // scrolling instead of trapping it in this sample.
                                  scrollPhysics:
                                      const NeverScrollableScrollPhysics(),
                                  style: TextStyle(
                                    fontFamily: _selectedFamily ?? _current,
                                    fontFamilyFallback: danFontFamilyFallback,
                                    fontSize: 22,
                                    fontWeight: FontWeight.normal,
                                    height: 1.4,
                                  ),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    border: InputBorder.none,
                                    labelText: ui('预览文字（可编辑）'),
                                    errorText: _previewFailed
                                        ? ui('此字体无法加载，请选择其他字体。')
                                        : null,
                                    errorMaxLines: 3,
                                  ),
                                ),
                              ]),
                        ),
                        const SizedBox(height: 16),
                        Text(ui('已安装字体 · {0}', [visible.length]),
                            style: theme.textTheme.labelLarge
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                  if (visible.isEmpty)
                    SliverToBoxAdapter(
                        child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(ui('没有匹配的字体'), textAlign: TextAlign.center),
                    )),
                  SliverList.builder(
                    itemCount: visible.length,
                    itemBuilder: (_, index) {
                      final font = visible[index];
                      return _FontRow(
                        key: ValueKey(font),
                        font: font,
                        loader: _loader,
                        current: font.fullName == _current,
                        selected: font == _selected,
                        selectedFamily:
                            font == _selected ? _selectedFamily : null,
                        onSelected: () => setState(() => _select(font)),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppDialogActions(children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(ui('取消')),
              ),
              FilledButton.icon(
                key: const ValueKey('font-selector-apply'),
                onPressed: _selectedFamily == null
                    ? null
                    : () => Navigator.pop(context, _selected),
                icon: const Icon(Icons.check),
                label: Text(ui('应用')),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _FontRow extends StatefulWidget {
  const _FontRow(
      {super.key,
      required this.font,
      required this.loader,
      required this.current,
      required this.selected,
      required this.selectedFamily,
      required this.onSelected});
  final InstalledFont font;
  final FontPreviewLoader loader;
  final bool current;
  final bool selected;
  final String? selectedFamily;
  final VoidCallback onSelected;

  @override
  State<_FontRow> createState() => _FontRowState();
}

class _FontRowState extends State<_FontRow> {
  late final _lease = widget.loader.acquire(widget.font);

  @override
  void dispose() {
    _lease.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
        future: _lease.family,
        initialData: widget.loader.loadedFamilyFor(widget.font),
        builder: (context, snapshot) {
          final scheme = Theme.of(context).colorScheme;
          final family = widget.selectedFamily ??
              widget.loader.loadedFamilyFor(widget.font) ??
              snapshot.data;
          final failed = snapshot.connectionState == ConnectionState.done &&
              family == null &&
              !_lease.deferred;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Material(
              color: widget.selected
                  ? scheme.secondaryContainer
                  : scheme.surfaceContainerLowest,
              shape: AppShape.control.copyWith(
                  side: BorderSide(
                      color: widget.selected
                          ? scheme.primary
                          : scheme.outlineVariant.withValues(alpha: .5))),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                key: ValueKey(('font-row', widget.font)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                selected: widget.selected,
                selectedColor: scheme.onSecondaryContainer,
                leading: Icon(
                    widget.selected ? Icons.check_circle : Icons.text_fields,
                    color: scheme.primary),
                title: Text(widget.font.fullName,
                    key: ValueKey(('font-name', widget.font)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: family,
                        fontFamilyFallback: danFontFamilyFallback,
                        fontSize: 17,
                        fontWeight: FontWeight.normal)),
                subtitle: failed
                    ? Text(ui('无法预览此字体'))
                    : family == null && _lease.deferred
                        ? Text(ui('选中以预览'))
                        : null,
                trailing: widget.current
                    ? Text(ui('当前'),
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(color: scheme.primary))
                    : null,
                onTap: widget.onSelected,
              ),
            ),
          );
        },
      );
}
