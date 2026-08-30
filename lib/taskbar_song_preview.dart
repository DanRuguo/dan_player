import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/library/artwork_size.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:flutter/material.dart';

/// Frozen metadata, separate from playback position and mutable library rows.
/// Only a small rendered card crosses the channel; no file path reaches Shell.
@immutable
class TaskbarPreviewTrack {
  const TaskbarPreviewTrack({
    required this.identity,
    required this.title,
    required this.artist,
    required this.album,
    this.loadArtwork,
  });

  factory TaskbarPreviewTrack.fromAudio(Audio audio) => TaskbarPreviewTrack(
      identity: (audio.path, audio.modified, audio.artworkUrl),
      title: audio.displayTitle,
      artist: audio.artist,
      album: audio.album,
      loadArtwork: () => audio.artworkForSize(const ArtworkSize(192, 192)));

  final Object identity;
  final String title, artist, album;
  final Future<ImageProvider?> Function()? loadArtwork;

  @override
  bool operator ==(Object other) =>
      other is TaskbarPreviewTrack &&
      identity == other.identity &&
      title == other.title &&
      artist == other.artist &&
      album == other.album;
  @override
  int get hashCode => Object.hash(identity, title, artist, album);
}

class TaskbarThumbnail {
  TaskbarThumbnail(this.width, this.height, this.pixels) {
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
  Map<String, Object> toMap() =>
      {'width': width, 'height': height, 'pixels': pixels};
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
        provider.resolve(const ImageConfiguration(size: Size(192, 192)));
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

/// Small, opaque 2:1 song card. Album art reuses the app's bounded cache.
/// Explicit canvas text uses the same bundled/fallback font as the main UI.
Future<TaskbarThumbnail> renderTaskbarSongPreview(
    TaskbarPreviewTrack track, ColorScheme scheme, String fontFamily) async {
  final artwork = await _previewArtwork(track);
  const width = 480, height = 240;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final painters = <TextPainter>[];
  ui.Picture? picture;
  ui.Image? image;
  try {
    canvas.drawColor(scheme.surface.withValues(alpha: 1), BlendMode.src);
    final cover = RRect.fromRectAndRadius(
        const Rect.fromLTWH(24, 32, 176, 176), const Radius.circular(18));
    canvas.save();
    canvas.clipRRect(cover);
    if (artwork != null) {
      paintImage(
          canvas: canvas,
          rect: cover.outerRect,
          image: artwork,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium);
    } else {
      canvas.drawRect(
          cover.outerRect, Paint()..color = scheme.secondaryContainer);
      canvas.drawCircle(const Offset(112, 120), 57,
          Paint()..color = scheme.onSecondaryContainer.withValues(alpha: .18));
      canvas.drawCircle(const Offset(112, 120), 17,
          Paint()..color = scheme.onSecondaryContainer);
      canvas.drawCircle(const Offset(112, 120), 5,
          Paint()..color = scheme.secondaryContainer);
    }
    canvas.restore();
    void text(String value, double y, double size, int lines, Color color,
        {FontWeight weight = FontWeight.w400}) {
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
                  color: color,
                  fontWeight: weight)),
          maxLines: lines,
          ellipsis: '…',
          textDirection: TextDirection.ltr)
        ..layout(maxWidth: 236);
      painters.add(painter);
      painter.paint(canvas, Offset(220, y));
    }

    final foreground = _previewTextColor(scheme);
    text(track.title, 35, 24, 2, foreground, weight: FontWeight.w600);
    text(track.artist, 104, 19, 2, foreground);
    text(track.album, 162, 17, 1, foreground);
    text('Dan Player', 199, 14, 1, foreground, weight: FontWeight.w600);
    picture = recorder.endRecording();
    image = await picture.toImage(width, height);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bytes == null) throw StateError('Unable to render taskbar thumbnail');
    return TaskbarThumbnail(width, height,
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
  } finally {
    for (final painter in painters) {
      painter.dispose();
    }
    artwork?.dispose();
    image?.dispose();
    picture?.dispose();
    if (recorder.isRecording) recorder.endRecording().dispose();
  }
}
