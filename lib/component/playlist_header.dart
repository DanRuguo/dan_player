import 'package:flutter/material.dart';

/// A compact playlist identity block: artwork belongs beside the title, not in
/// the breadcrumb strip. All actions keep their normal touch/keyboard targets.
class PlaylistHeader extends StatelessWidget {
  const PlaylistHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.coverBuilder,
    required this.breadcrumbs,
    required this.actions,
    this.compact = false,
  });

  final String title;
  final String subtitle;
  final Widget Function(double size) coverBuilder;
  final Widget breadcrumbs;
  final Widget actions;
  final bool compact;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          if (compact) return _compact(context, constraints.maxWidth);
          final wide = constraints.maxWidth >= 640 &&
              MediaQuery.textScalerOf(context).scale(14) < 23;
          final coverSize = wide
              ? 112.0
              : constraints.maxWidth >= 360
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
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
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
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
              if (wide) ...[
                const SizedBox(height: 12),
                Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: actions),
              ],
            ],
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              breadcrumbs,
              const SizedBox(height: 6),
              Row(
                key: const ValueKey('playlist-header-identity'),
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox.square(
                    key: const ValueKey('playlist-header-cover'),
                    dimension: coverSize,
                    child: coverBuilder(coverSize),
                  ),
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
          );
        },
      );

  Widget _compact(BuildContext context, double width) {
    final scheme = Theme.of(context).colorScheme;
    final inlineActions =
        width >= 880 && MediaQuery.textScalerOf(context).scale(14) < 23;
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          breadcrumbs,
          const SizedBox(height: 4),
          Row(key: const ValueKey('playlist-header-identity'), children: [
            SizedBox.square(
                key: const ValueKey('playlist-header-cover'),
                dimension: 64,
                child: coverBuilder(64)),
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
                                      fontWeight: FontWeight.w600)))),
                  const SizedBox(height: 4),
                  Tooltip(
                      message: subtitle,
                      child: Text(subtitle,
                          key: const ValueKey('playlist-header-subtitle'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant))),
                ])),
            if (inlineActions) ...[
              const SizedBox(width: 16),
              ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: width * .52),
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
