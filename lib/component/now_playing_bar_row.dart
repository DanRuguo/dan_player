import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:flutter/material.dart';

/// Shared, native-free presentation for the home playback bar.
class NowPlayingBarRow extends StatelessWidget {
  const NowPlayingBarRow(
      {super.key,
      required this.leading,
      required this.title,
      required this.subtitle,
      required this.identity,
      required this.controlsBuilder,
      this.spectrum});

  final Widget leading;
  final String title;
  final String subtitle;
  final Object identity;
  final Widget? spectrum;
  final Widget Function(bool showQueue) controlsBuilder;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: LayoutBuilder(
          builder: (context, bounds) => Row(children: [
                leading,
                const SizedBox(width: 12),
                Expanded(
                    child: AnimatedSwitcher(
                  duration: appToolbarReduceMotion(context)
                      ? Duration.zero
                      : AppMotion.standard,
                  switchInCurve: AppMotion.standardCurve,
                  switchOutCurve: Curves.easeInCubic,
                  child: Column(
                    key: ValueKey(identity),
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(
                            child: Text(title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: scheme.primary,
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w600))),
                        if (spectrum != null && bounds.maxWidth >= 400) ...[
                          const SizedBox(width: 8),
                          spectrum!,
                        ],
                      ]),
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: scheme.onSurfaceVariant, fontSize: 12.5)),
                    ],
                  ),
                )),
                const SizedBox(width: 8),
                controlsBuilder(bounds.maxWidth >= 520),
              ])),
    );
  }
}
