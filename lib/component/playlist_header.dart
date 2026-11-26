import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/text_motion_stabilizer.dart';
import 'package:flutter/material.dart';

/// A Material 3 Expressive playlist identity hero card: artwork belongs beside
/// the title, below the breadcrumb strip, while all actions retain full touch
/// and keyboard targets.
class PlaylistHeader extends StatelessWidget {
  const PlaylistHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.coverBuilder,
    required this.breadcrumbs,
    required this.actions,
    this.details,
    this.compact = false,
  });

  final String title;
  final String subtitle;
  final Widget Function(double size) coverBuilder;
  final Widget breadcrumbs;
  final Widget actions;
  final Widget? details;
  final bool compact;

  Widget _framedCard(BuildContext context, Widget child) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color:
            scheme.surfaceContainerLow.withValues(alpha: isDark ? .60 : .78),
        borderRadius: AppShape.cardRadius,
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: isDark ? .34 : .42),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            compact ? 12 : 16, compact ? 8 : 10, compact ? 12 : 16, compact ? 10 : 14),
        child: child,
      ),
    );
  }

  Widget _shadowedCover(BuildContext context, double size) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: .16),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: SizedBox.square(
        key: const ValueKey('playlist-header-cover'),
        dimension: size,
        child: coverBuilder(size),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final innerWidth = (constraints.maxWidth - (compact ? 24 : 32))
              .clamp(0.0, double.infinity);
          if (compact) return _framedCard(context, _compact(context, innerWidth));
          final scheme = Theme.of(context).colorScheme;
          final wide = innerWidth >= 608 &&
              MediaQuery.textScalerOf(context).scale(14) < 23;
          final coverSize = wide
              ? 112.0
              : innerWidth >= 336
                  ? 88.0
                  : 72.0;
          final text = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Tooltip(
                  message: title,
                  child: Text(
                    title,
                    key: const ValueKey('playlist-header-title'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                          color: scheme.onSurface,
                        ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Tooltip(
                message: subtitle,
                child: Text(
                  subtitle,
                  key: const ValueKey('playlist-header-subtitle'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                        fontFeatures: tabularFiguresFeatures,
                      ),
                ),
              ),
              if (details != null) ...[
                const SizedBox(height: 4),
                details!,
              ],
              if (wide) ...[
                const SizedBox(height: 12),
                Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: actions),
              ],
            ],
          );
          return _framedCard(
            context,
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                breadcrumbs,
                const SizedBox(height: 8),
                Row(
                  key: const ValueKey('playlist-header-identity'),
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _shadowedCover(context, coverSize),
                    SizedBox(width: wide ? 20 : 16),
                    Expanded(child: text),
                  ],
                ),
                if (!wide) ...[
                  const SizedBox(height: 12),
                  Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: actions),
                ],
              ],
            ),
          );
        },
      );

  Widget _compact(BuildContext context, double width) {
    final scheme = Theme.of(context).colorScheme;
    final inlineActions =
        width >= 848 && MediaQuery.textScalerOf(context).scale(14) < 23;
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          breadcrumbs,
          const SizedBox(height: 6),
          Row(key: const ValueKey('playlist-header-identity'), children: [
            _shadowedCover(context, 64),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Semantics(
                      header: true,
                      child: Tooltip(
                          message: title,
                          child: Text(title,
                              key: const ValueKey('playlist-header-title'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                      color: scheme.onSurface,
                                      fontWeight: FontWeight.w700)))),
                  const SizedBox(height: 3),
                  Tooltip(
                      message: subtitle,
                      child: Text(subtitle,
                          key: const ValueKey('playlist-header-subtitle'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontFeatures: tabularFiguresFeatures))),
                  if (details != null) ...[
                    const SizedBox(height: 4),
                    details!,
                  ],
                ])),
            if (inlineActions) ...[
              const SizedBox(width: 16),
              ConstrainedBox(
                  // Reserve a useful identity width without permanently
                  // assigning half the header to empty title space.
                  constraints: BoxConstraints(maxWidth: width - 256),
                  child: actions),
            ],
          ]),
          if (!inlineActions) ...[
            const SizedBox(height: 8),
            Align(alignment: AlignmentDirectional.centerStart, child: actions),
          ],
        ]);
  }
}
