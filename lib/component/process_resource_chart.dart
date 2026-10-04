import 'package:dan_player/process_resource_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A static resource chart, shared by the settings surface and compact views.
/// Unknown samples break the line instead of being reported as zero.
class ProcessResourceChart extends StatelessWidget {
  const ProcessResourceChart({
    super.key,
    required this.history,
    required this.value,
    required this.maximum,
    required this.mode,
    required this.color,
    required this.track,
    required this.height,
  });

  final List<double?> history;
  final double? value;
  final double maximum, height;
  final ProcessResourceDisplay mode;
  final Color color, track;

  @override
  Widget build(BuildContext context) => SizedBox(
      width: double.infinity,
      height: height,
      child: CustomPaint(
          painter: _ResourceGraph(
              history: history,
              value: value,
              maximum: maximum,
              mode: mode,
              color: color,
              track: track)));
}

class _ResourceGraph extends CustomPainter {
  const _ResourceGraph({
    required this.history,
    required this.value,
    required this.maximum,
    required this.mode,
    required this.color,
    required this.track,
  });
  final List<double?> history;
  final double? value;
  final double maximum;
  final ProcessResourceDisplay mode;
  final Color color, track;

  double _fraction(double value) =>
      maximum.isFinite && maximum > 0 ? (value / maximum).clamp(0, 1) : 0;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    if (mode == ProcessResourceDisplay.bar) {
      final radius = Radius.circular(size.height / 2);
      canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, radius),
          Paint()..color = track);
      if (value != null && value!.isFinite) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(
                    0, 0, size.width * _fraction(value!), size.height),
                radius),
            Paint()..color = color);
      }
      return;
    }
    canvas.drawLine(Offset(0, size.height - 1),
        Offset(size.width, size.height - 1), Paint()..color = track);
    final compact = size.height <= 14;
    final inset = (compact ? 1.0 : 2.0).clamp(0.0, size.height / 2);
    final path = Path();
    bool connected = false;
    for (var index = 0; index < history.length; index++) {
      final value = history[index];
      if (value == null || !value.isFinite) {
        connected = false;
        continue;
      }
      final x =
          history.length < 2 ? 0.0 : index * size.width / (history.length - 1);
      final y = (size.height - inset * 2).clamp(0, double.infinity) *
              (1 - _fraction(value)) +
          inset;
      if (connected) {
        path.lineTo(x, y);
      } else {
        path.moveTo(x, y);
      }
      final next = index + 1 < history.length ? history[index + 1] : null;
      final isolated = !connected && (next == null || !next.isFinite);
      if (!compact || isolated) {
        canvas.drawCircle(Offset(x, y), inset, Paint()..color = color);
      }
      connected = true;
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = compact ? 1.4 : 2
          ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(covariant _ResourceGraph old) =>
      old.value != value ||
      old.maximum != maximum ||
      old.mode != mode ||
      old.color != color ||
      old.track != track ||
      !listEquals(old.history, history);
}
