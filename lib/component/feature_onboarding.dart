import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';

/// A self-contained, interactive introduction. Preview actions deliberately do
/// not create library entries, initialize audio or overwrite user preferences.
class FeatureOnboarding extends StatefulWidget {
  const FeatureOnboarding({super.key, required this.onComplete});
  final VoidCallback onComplete;

  @override
  State<FeatureOnboarding> createState() => _FeatureOnboardingState();
}

class _FeatureOnboardingState extends State<FeatureOnboarding> {
  int _step = 0;
  bool _playing = false;
  double _position = .32;
  int _rating = 3;
  bool _tagged = false;
  bool _grid = false;
  double _lyricSize = 22;
  Color _accent = Colors.teal;
  final _scroll = ScrollController();

  static const _titles = ['从一首歌开始', '把喜欢的音乐放在一起', '让歌词与界面合你心意'];
  static const _descriptions = [
    '点击播放按钮、拖动进度条，熟悉播放控制。正式使用时，还能切换迷你播放器和桌面歌词。',
    '试试切换视图、评分和标签。歌单支持子歌单、拖动整理与自定义顺序。',
    '试试文字大小和主题颜色。歌词校准、背景、频谱与刷新率都可以在设置中调整。',
  ];

  void _move(int step) {
    setState(() => _step = step);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: Column(children: [
          Expanded(
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Column(children: [
                Text(ui('欢迎使用 Dan Player'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (index, label)
                          in ['播放', '整理', '歌词与外观'].indexed)
                        ChoiceChip(
                          key: ValueKey('onboarding-step-$index'),
                          selected: _step == index,
                          showCheckmark: false,
                          avatar: Text('${index + 1}'),
                          label: Text(ui(label)),
                          onSelected: (_) => _move(index),
                        ),
                    ]),
                const SizedBox(height: 24),
                Text(ui(_titles[_step]),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(ui(_descriptions[_step]),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 24),
                AnimatedSwitcher(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : AppMotion.standard,
                  child: Container(
                    key: ValueKey('onboarding-preview-$_step'),
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: switch (_step) {
                      0 => _playbackPreview(context),
                      1 => _libraryPreview(context),
                      _ => _appearancePreview(context),
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Text(ui('交互预览：不会播放声音，也不会修改曲库或设置。'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton(
                      onPressed: widget.onComplete, child: Text(ui('跳过引导'))),
                  if (_step > 0)
                    OutlinedButton(
                        onPressed: () => _move(_step - 1),
                        child: Text(ui('上一步'))),
                  FilledButton.icon(
                    key: const ValueKey('onboarding-next'),
                    onPressed:
                        _step == 2 ? widget.onComplete : () => _move(_step + 1),
                    icon: Icon(
                        _step == 2 ? Icons.folder_open : Icons.arrow_forward),
                    label: Text(ui(_step == 2 ? '添加我的音乐' : '下一步')),
                  ),
                ]),
          ),
        ]),
      ),
    );
  }

  Widget _cover(BuildContext context) => Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12)),
        child: Icon(Icons.music_note,
            size: 36, color: Theme.of(context).colorScheme.onPrimaryContainer),
      );

  Widget _playbackPreview(BuildContext context) => Column(children: [
        _cover(context),
        const SizedBox(height: 12),
        Text(ui('你的第一首歌'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Slider(
            value: _position,
            label: '${(_position * 180).round()} s',
            onChanged: (value) => setState(() => _position = value)),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(
              '${(_position * 3).floor()}:${((_position * 180).floor() % 60).toString().padLeft(2, '0')}'),
          const Text('3:00'),
        ]),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
            key: const ValueKey('onboarding-play'),
            onPressed: () => setState(() => _playing = !_playing),
            icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
            label: Text(ui(_playing ? '暂停' : '播放'))),
      ]);

  Widget _libraryPreview(BuildContext context) => Column(children: [
        AppSegmentedControl<bool>(
            value: _grid,
            onChanged: (value) => setState(() => _grid = value),
            options: [
              AppSegmentOption(
                  value: false, label: ui('列表'), icon: Icons.view_list),
              AppSegmentOption(
                  value: true, label: ui('网格'), icon: Icons.grid_view),
            ]),
        const SizedBox(height: 20),
        if (_grid) ...[
          _cover(context),
          const SizedBox(height: 8),
          Text(ui('你的第一首歌'))
        ] else
          Row(children: [
            _cover(context),
            const SizedBox(width: 16),
            Expanded(child: Text(ui('你的第一首歌')))
          ]),
        const SizedBox(height: 12),
        Wrap(alignment: WrapAlignment.center, children: [
          for (var star = 1; star <= 5; star++)
            IconButton(
                tooltip: ui('评分 {0} 星', ['$star']),
                onPressed: () => setState(() => _rating = star),
                color: Theme.of(context).colorScheme.primary,
                icon: Icon(star <= _rating ? Icons.star : Icons.star_border)),
        ]),
        FilterChip(
            selected: _tagged,
            label: Text(ui('喜欢的音乐')),
            avatar: const Icon(Icons.label_outline, size: 18),
            onSelected: (value) => setState(() => _tagged = value)),
      ]);

  Widget _appearancePreview(BuildContext context) {
    final localScheme = ColorScheme.fromSeed(
        seedColor: _accent, brightness: Theme.of(context).brightness);
    return Column(children: [
      Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
              color: localScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12)),
          child: Text(ui('让每一段旋律，都有自己的颜色'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontSize: _lyricSize,
                  color: localScheme.onPrimaryContainer))),
      const SizedBox(height: 16),
      Text(ui('歌词字号')),
      Slider(
          value: _lyricSize,
          min: 16,
          max: 32,
          divisions: 8,
          label: '${_lyricSize.round()}',
          onChanged: (value) => setState(() => _lyricSize = value)),
      Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (color, label) in [
              (Colors.teal, '青绿'),
              (Colors.purple, '紫色'),
              (Colors.orange, '橙色')
            ])
              ChoiceChip(
                  selected: _accent == color,
                  label: Text(ui(label)),
                  avatar: Icon(Icons.circle, size: 14, color: color),
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _accent = color)),
          ]),
    ]);
  }
}
