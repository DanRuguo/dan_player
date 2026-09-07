import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/library/artwork_size.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:flutter/material.dart';

/// Frozen metadata, separate from playback position and mutable library rows.
/// Only bounded rendered cards cross the channel; no file path reaches Shell.
@immutable
class TaskbarPreviewTrack {
  const TaskbarPreviewTrack({
    required this.identity,
    required this.title,
    required this.artist,
    required this.album,
    this.loadArtwork,
    this.durationSeconds = 0,
    this.playing = false,
    this.buffering = false,
    this.statusLabel = '',
  });

  factory TaskbarPreviewTrack.fromAudio(Audio audio) => TaskbarPreviewTrack(
          identity: (
            audio.path,
            audio.modified,
            audio.coverFingerprint,
            audio.artworkUrl
          ),
          title: audio.displayTitle,
          artist: audio.artist,
          album: audio.album,
          durationSeconds: audio.duration,
          loadArtwork: () => audio.artworkForSize(const ArtworkSize(448, 448)));

  final Object identity;
  final String title, artist, album;
  final Future<ImageProvider?> Function()? loadArtwork;
  final int durationSeconds;
  final bool playing, buffering;
  final String statusLabel;

  TaskbarPreviewTrack withPlaybackState(
          {required bool playing,
          required bool buffering,
          required String label}) =>
      TaskbarPreviewTrack(
          identity: identity,
          title: title,
          artist: artist,
          album: album,
          loadArtwork: loadArtwork,
          durationSeconds: durationSeconds,
          playing: playing,
          buffering: buffering,
          statusLabel: label);

  @override
  bool operator ==(Object other) =>
      other is TaskbarPreviewTrack &&
      identity == other.identity &&
      title == other.title &&
      artist == other.artist &&
      album == other.album &&
      durationSeconds == other.durationSeconds &&
      playing == other.playing &&
      buffering == other.buffering &&
      statusLabel == other.statusLabel;
  @override
  int get hashCode => Object.hash(identity, title, artist, album,
      durationSeconds, playing, buffering, statusLabel);
}

class TaskbarPeekImage {
  TaskbarPeekImage(this.width, this.height, this.pixels) {
    if (width < 1 ||
        height < 1 ||
        width > 2048 ||
        height > 2048 ||
        pixels.length > 4 * 1024 * 1024 ||
        pixels.length != width * height * 4) {
      throw ArgumentError('Peek must be bounded to 2048px axes and 4MiB RGBA');
    }
  }
  final int width, height;
  final Uint8List pixels;
  Map<String, Object> toMap() =>
      {'width': width, 'height': height, 'pixels': pixels};
}

class TaskbarThumbnail {
  TaskbarThumbnail(this.width, this.height, this.pixels, {this.peek}) {
    if (width < 1 ||
        height < 1 ||
        width > 512 ||
        height > 512 ||
        pixels.length != width * height * 4) {
      throw ArgumentError('Taskbar thumbnail must be bounded, packed RGBA');
    }
  }
  final int width, height;
  final Uint8List pixels;
  final TaskbarPeekImage? peek;
  Map<String, Object> toMap() => {
        'width': width,
        'height': height,
        'pixels': pixels,
        if (peek != null) 'peek': peek!.toMap()
      };
}

typedef TaskbarPreviewRenderer = Future<TaskbarThumbnail> Function(
    TaskbarPreviewTrack track, ColorScheme scheme, String fontFamily);

/// No timers or per-frame capture. One render at a time, latest request wins.
/// Slow artwork must not delay native playback buttons or resurrect on exit.
class TaskbarPreviewPublisher {
  TaskbarPreviewPublisher(
      {required this.invoke,
      this.renderer = renderTaskbarSongPreview,
      this.onError,
      this.onReady});
  final Future<Object?> Function(String, [Map<String, Object>?]) invoke;
  final TaskbarPreviewRenderer renderer;
  final void Function(Object)? onError;
  final VoidCallback? onReady;
  (TaskbarPreviewTrack, ColorScheme, String)? _desired;
  Object? _key;
  int _revision = 0;
  bool _closed = false, _working = false, _hasNative = false;
  Future<void> _sendTail = Future.value();

  void synchronize(
      {required bool enabled,
      TaskbarPreviewTrack? track,
      required ColorScheme scheme,
      String fontFamily = danEmbeddedFontFamily}) {
    if (_closed) return;
    final desired =
        enabled && track != null ? (track, scheme, fontFamily) : null;
    if (_key == desired) return;
    _key = desired;
    _desired = desired;
    final revision = ++_revision;
    // Replace an active card in place. Tearing down DWM's iconic attributes on
    // every song/theme change can invalidate Explorer's open preview session.
    // Keep the last complete frame until the latest frame is ready; disabling
    // or removing the track still restores the system preview immediately.
    if (desired == null && _hasNative) _clear(revision);
    if (desired != null && !_working) unawaited(_renderLatest());
  }

  void _clear(int revision) {
    unawaited(_enqueue(() async {
      if (_closed || revision != _revision || !_hasNative) return;
      await invoke('clearThumbnail');
      _hasNative = false;
    }).catchError((Object error) {
      if (!_closed && revision == _revision) onError?.call(error);
    }));
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _sendTail.then((_) => operation());
    // Keep the shared queue fulfilled even when a call fails after native
    // mutation. A newer clear must still execute, and an older error handler
    // must never replace a tail to which newer work has already been appended.
    _sendTail =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> _renderLatest() async {
    _working = true;
    try {
      while (!_closed && _desired != null) {
        final request = _desired!;
        final revision = _revision;
        try {
          final image = await renderer(request.$1, request.$2, request.$3);
          if (_closed) return;
          if (revision != _revision) continue;
          final send = _enqueue(() async {
            if (_closed || revision != _revision) return;
            // Even a transport error can occur after native mutation.
            _hasNative = true;
            await invoke('setThumbnail', image.toMap());
            if (!_closed && revision == _revision) onReady?.call();
          });
          try {
            await send;
          } catch (error) {
            if (!_closed && revision == _revision) {
              onError?.call(error);
              _clear(revision);
            }
          }
        } catch (error) {
          if (!_closed && revision == _revision) {
            onError?.call(error);
            _clear(revision);
          }
        }
        if (revision == _revision) break;
      }
    } finally {
      _working = false;
    }
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    _revision++;
    _desired = null;
    // Deliberately don't wait for an image/network read to close the player.
    try {
      await _sendTail;
    } catch (_) {}
    if (_hasNative) {
      try {
        await invoke('clearThumbnail');
      } catch (_) {}
      _hasNative = false;
    }
  }
}

Future<ui.Image?> _previewArtwork(TaskbarPreviewTrack track) async {
  try {
    final provider =
        await track.loadArtwork?.call().timeout(const Duration(seconds: 3));
    if (provider == null) return null;
    final completer = Completer<ui.Image?>();
    final stream =
        provider.resolve(const ImageConfiguration(size: Size(448, 448)));
    final listener = ImageStreamListener((info, _) {
      if (!completer.isCompleted) completer.complete(info.image.clone());
      info.dispose();
    }, onError: (Object _, StackTrace? __) {
      if (!completer.isCompleted) completer.complete(null);
    });
    stream.addListener(listener);
    try {
      return await completer.future.timeout(const Duration(seconds: 3),
          onTimeout: () {
        completer.complete(null);
        return null;
      });
    } finally {
      stream.removeListener(listener);
    }
  } catch (_) {
    return null;
  }
}

Color _previewTextColor(ColorScheme scheme) {
  // Match the app's artwork/theme accent, not the nearly neutral onSurface.
  // Generated Material schemes already pass; protect custom/damaged palettes
  // on this opaque card by darkening/lightening the accent toward black/white.
  // Quantize before checking so the actual 8-bit thumbnail also passes.
  final primary = Color(scheme.primary.toARGB32() | 0xff000000);
  final background = scheme.surface.computeLuminance();
  double contrast(Color color) {
    final foreground = color.computeLuminance();
    return foreground > background
        ? (foreground + .05) / (background + .05)
        : (background + .05) / (foreground + .05);
  }

  if (contrast(primary) >= 4.5) return primary;
  final target = background > .179 ? Colors.black : Colors.white;
  var lower = 0.0, upper = 1.0;
  for (var i = 0; i < 12; i++) {
    final fraction = (lower + upper) / 2;
    final candidate = Color(Color.lerp(primary, target, fraction)!.toARGB32());
    if (contrast(candidate) >= 4.5) {
      upper = fraction;
    } else {
      lower = fraction;
    }
  }
  return Color(Color.lerp(primary, target, upper)!.toARGB32());
}

/// Independent compositions: the 480px thumbnail stays legible in Explorer,
/// while Peek uses a spacious cover and typography at its actual raster size.
/// Neither source animates or observes position ticks. Both share one bounded
/// artwork read and are published atomically by [TaskbarPreviewPublisher].
Future<TaskbarThumbnail> renderTaskbarSongPreview(
    TaskbarPreviewTrack track, ColorScheme scheme, String fontFamily) async {
  final artwork = await _previewArtwork(track);
  final painter = _SongPreviewPainter(track, scheme, fontFamily, artwork);
  try {
    final small = await painter.render(peek: false);
    final large = await painter.render(peek: true);
    return TaskbarThumbnail(480, 240, small,
        peek: TaskbarPeekImage(1280, 800, large));
  } finally {
    artwork?.dispose();
    painter.dispose();
  }
}

class _SongPreviewPainter {
  _SongPreviewPainter(this.track, this.scheme, this.fontFamily, this.artwork);
  final TaskbarPreviewTrack track;
  final ColorScheme scheme;
  final String fontFamily;
  final ui.Image? artwork;
  final _paragraphs = <TextPainter>[];
  late final Color foreground = _previewTextColor(scheme);

  Future<Uint8List> render({required bool peek}) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    ui.Picture? picture;
    ui.Image? image;
    final width = peek ? 1280 : 480, height = peek ? 800 : 240;
    try {
      final bounds = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
      // Opaque edges are also native Peek's letterbox gradient endpoints.
      canvas.drawRect(
          bounds,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(scheme.surface, scheme.primaryContainer, .40)!,
                scheme.surfaceContainerLow,
                Color.lerp(scheme.surface, scheme.secondaryContainer, .55)!
              ],
            ).createShader(bounds));
      if (peek) {
        _large(canvas);
      } else {
        _small(canvas);
      }
      picture = recorder.endRecording();
      image = await picture.toImage(width, height);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bytes == null) throw StateError('Unable to render taskbar preview');
      return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
    } finally {
      image?.dispose();
      picture?.dispose();
      if (recorder.isRecording) recorder.endRecording().dispose();
    }
  }

  void _text(Canvas canvas, String value, Offset offset, double width,
      double size, int lines,
      {FontWeight weight = FontWeight.w400,
      TextAlign alignment = TextAlign.left}) {
    _paragraph(value, width, size, lines, weight: weight, alignment: alignment)
        .paint(canvas, offset);
  }

  TextPainter _paragraph(String value, double width, double size, int lines,
      {FontWeight weight = FontWeight.w400,
      TextAlign alignment = TextAlign.left}) {
    final bounded = value.characters
        .take(160)
        .toString()
        .replaceAll(RegExp(r'[\r\n\t]'), ' ');
    final painter = TextPainter(
      text: TextSpan(
          text: bounded,
          style: TextStyle(
              fontFamily: fontFamily,
              fontFamilyFallback: danFontFamilyFallback,
              fontSize: size,
              height: 1.2,
              color: foreground,
              fontWeight: weight)),
      maxLines: lines,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
      textAlign: alignment,
    )..layout(
        minWidth: alignment == TextAlign.left ? 0 : width, maxWidth: width);
    _paragraphs.add(painter);
    return painter;
  }

  void _surface(Canvas canvas, Rect rect, double radius) {
    canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)),
        Paint()..color = scheme.surface.withValues(alpha: 1));
  }

  void _cover(Canvas canvas, Rect rect, double radius) {
    final round = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    canvas.drawShadow(Path()..addRRect(round),
        scheme.shadow.withValues(alpha: .28), rect.width * .035, true);
    canvas.save();
    canvas.clipRRect(round);
    if (artwork != null) {
      paintImage(
          canvas: canvas,
          rect: rect,
          image: artwork!,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high);
    } else {
      canvas.drawRect(
          rect,
          Paint()
            ..shader = LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [scheme.primaryContainer, scheme.tertiaryContainer])
                .createShader(rect));
      final center = rect.center;
      canvas.drawCircle(center, rect.width * .36,
          Paint()..color = scheme.onPrimaryContainer.withValues(alpha: .12));
      for (final fraction in [.23, .28, .33]) {
        canvas.drawCircle(
            center,
            rect.width * fraction,
            Paint()
              ..color = scheme.onPrimaryContainer.withValues(alpha: .10)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5);
      }
      canvas.drawCircle(center, rect.width * .10,
          Paint()..color = scheme.onPrimaryContainer.withValues(alpha: .84));
      canvas.drawCircle(
          center, rect.width * .035, Paint()..color = scheme.primaryContainer);
    }
    canvas.restore();
    canvas.drawRRect(
        round,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = scheme.outlineVariant.withValues(alpha: .35));
  }

  String get _duration {
    final seconds = track.durationSeconds;
    if (seconds <= 0 || seconds > 86400) return '—:—';
    final minutes = seconds ~/ 60,
        remainder = (seconds % 60).toString().padLeft(2, '0');
    return minutes < 60
        ? '$minutes:$remainder'
        : '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}:$remainder';
  }

  void _state(Canvas canvas, Rect bounds, {required bool large}) {
    canvas.drawRRect(
        RRect.fromRectAndRadius(bounds, const Radius.circular(30)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = large ? 1.6 : 1
          ..color = foreground.withValues(alpha: .28));
    final unit = large ? 1.6 : 1.0;
    final label = _paragraph(
        track.statusLabel, bounds.width - 52 * unit, large ? 21 : 13, 1,
        weight: FontWeight.w500);
    final contentWidth = 26 * unit + label.width;
    final contentLeft = bounds.center.dx - contentWidth / 2;
    final center = Offset(contentLeft + 8 * unit, bounds.center.dy);
    final paint = Paint()..color = foreground;
    if (track.buffering) {
      for (var index = -1; index <= 1; index++) {
        canvas.drawCircle(
            center + Offset(index * 5 * unit, 0), 1.5 * unit, paint);
      }
    } else if (track.playing) {
      for (var index = 0; index < 4; index++) {
        final barHeight = [8.0, 16.0, 12.0, 6.0][index] * unit;
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(center.dx + (index - 1.5) * 4 * unit - unit,
                    center.dy - barHeight / 2, 2 * unit, barHeight),
                Radius.circular(unit)),
            paint);
      }
    } else {
      for (final x in [-4.0, 2.0]) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(center.dx + x * unit, center.dy - 6 * unit,
                    3 * unit, 12 * unit),
                Radius.circular(unit)),
            paint);
      }
    }
    label.paint(canvas,
        Offset(contentLeft + 26 * unit, bounds.center.dy - label.height / 2));
  }

  void _small(Canvas canvas) {
    _cover(canvas, const Rect.fromLTWH(16, 24, 192, 192), 22);
    _surface(canvas, const Rect.fromLTWH(216, 12, 252, 216), 24);
    _text(canvas, 'Dan Player', const Offset(232, 24), 216, 12, 1,
        weight: FontWeight.w600);
    _text(canvas, track.title, const Offset(232, 51), 216, 22, 2,
        weight: FontWeight.w600);
    _text(canvas, track.artist, const Offset(232, 115), 216, 16, 1);
    _text(canvas, track.album, const Offset(232, 144), 216, 14, 1);
    _state(canvas, const Rect.fromLTWH(232, 181, 135, 31), large: false);
    _text(canvas, _duration, const Offset(384, 189), 68, 13, 1,
        weight: FontWeight.w500);
  }

  void _large(Canvas canvas) {
    final halo = Paint()..color = scheme.primary.withValues(alpha: .06);
    canvas.drawCircle(const Offset(264, 368), 302, halo);
    canvas.drawCircle(const Offset(1180, 790), 230,
        Paint()..color = scheme.tertiary.withValues(alpha: .055));
    // Brand and content surfaces use the same opaque contrast reference.
    _surface(canvas, const Rect.fromLTWH(64, 48, 208, 56), 28);
    _text(canvas, 'Dan Player', const Offset(80, 62), 176, 24, 1,
        weight: FontWeight.w600, alignment: TextAlign.center);
    _cover(canvas, const Rect.fromLTWH(72, 160, 440, 440), 40);
    _surface(canvas, const Rect.fromLTWH(552, 140, 656, 484), 40);
    _text(canvas, track.title, const Offset(592, 180), 576, 56, 2,
        weight: FontWeight.w600, alignment: TextAlign.center);
    _text(canvas, track.artist, const Offset(592, 344), 576, 30, 1,
        alignment: TextAlign.center);
    _text(canvas, track.album, const Offset(592, 404), 576, 23, 2,
        alignment: TextAlign.center);
    _state(canvas, const Rect.fromLTWH(670, 530, 252, 50), large: true);
    _text(canvas, _duration, const Offset(950, 540), 140, 25, 1,
        weight: FontWeight.w500, alignment: TextAlign.center);
    // A static sound motif, never an imitation seek bar or animated spectrum.
    const bars = [
      8.0,
      16.0,
      28.0,
      18.0,
      40.0,
      24.0,
      12.0,
      32.0,
      46.0,
      22.0,
      34.0,
      18.0,
      12.0,
      28.0,
      36.0,
      16.0,
      8.0,
      22.0,
      34.0,
      16.0,
      28.0,
      42.0,
      24.0,
      12.0,
      18.0,
      30.0,
      14.0,
      8.0
    ];
    for (var i = 0; i < bars.length; i++) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(80 + i * 40, 696 - bars[i] / 2, 18, bars[i]),
              const Radius.circular(9)),
          Paint()..color = scheme.primary.withValues(alpha: .12));
    }
  }

  void dispose() {
    for (final painter in _paragraphs) {
      painter.dispose();
    }
  }
}
