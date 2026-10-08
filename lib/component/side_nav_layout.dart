import 'package:desktop_lyric/font_policy.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:flutter/material.dart';

TextStyle sideNavLabelStyle(BuildContext context,
        {Color? color, bool selected = false}) =>
    Theme.of(context).textTheme.bodyMedium!.merge(danCjkTextStyle(
          fontFamily: AppFontScope.of(context).uiFamily,
          color: color,
          fontSize: 16,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ));

/// Keep the icon/label group between equal 26-pixel outer margins. Measure the
/// widest translated label, including accessibility scaling and selected weight.
double sideNavCompactThreshold(BuildContext context, Iterable<String> labels) {
  final painter = TextPainter(
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  );
  var widest = 0.0;
  try {
    for (final label in labels) {
      painter.text = TextSpan(
        text: label,
        style: sideNavLabelStyle(context, selected: true),
      );
      painter.layout();
      if (painter.width > widest) widest = painter.width;
    }
    return 26 + 28 + 12 + widest + 26;
  } finally {
    painter.dispose();
  }
}
