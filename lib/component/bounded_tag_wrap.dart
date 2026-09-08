import 'package:flutter/material.dart';

/// Fits complete labels in two lines; omitted labels are available in a tooltip.
class BoundedTagWrap extends StatelessWidget {
  const BoundedTagWrap({super.key, required this.tags});
  final List<String> tags;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style =
        Theme.of(context).textTheme.bodySmall!.copyWith(color: scheme.primary);
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(builder: (context, constraints) {
      final shown = <String>[];
      var line = 0, used = 0.0;
      double width(String text) {
        final p = TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: Directionality.of(context),
            textScaler: scaler)
          ..layout();
        final w = p.width + 20;
        p.dispose();
        return w;
      }

      for (var i = 0; i < tags.length; i++) {
        final w = width(tags[i]);
        if (used + w > constraints.maxWidth) {
          line++;
          used = 0;
        }
        if (w > constraints.maxWidth ||
            line > 1 ||
            (line == 1 &&
                i < tags.length - 1 &&
                used + w + width('…') + 6 > constraints.maxWidth)) {
          shown.add('…');
          break;
        }
        shown.add(tags[i]);
        used += w + 6;
      }
      return Tooltip(
          message: tags.join(' · '),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final tag in shown)
              DecoratedBox(
                  decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: .45),
                      borderRadius: BorderRadius.circular(20)),
                  child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      child: Text(tag, style: style, maxLines: 1)))
          ]));
    });
  }
}
