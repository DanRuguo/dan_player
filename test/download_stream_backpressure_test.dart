import 'dart:async';
import 'dart:io';

import 'package:dan_player/data/stream_file_transfer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a slow file pauses the response instead of buffering the download',
      () async {
    final disk = _SlowConsumer();
    final sink = IOSink(disk);
    var produced = 0;
    final progress = <int>[];
    Stream<List<int>> response() async* {
      for (var i = 0; i < 128; i++) {
        produced++;
        yield List<int>.filled(8192, i);
      }
    }

    final pending = writeStreamToFileSink(response(), sink,
        checkCurrent: () {}, total: 128 * 8192, onProgress: (received, total) {
      expect(total, 128 * 8192);
      progress.add(received);
    });
    try {
      await disk.started.future;
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(produced, lessThanOrEqualTo(2),
          reason: 'The response must respect the file consumer pause.');
    } finally {
      disk.release.complete();
      expect(await pending, 128 * 8192);
      await sink.flush();
      await sink.close();
    }
    expect(disk.bytes, 128 * 8192);
    expect(progress.last, disk.bytes);
    expect(progress, orderedEquals(List.generate(128, (i) => (i + 1) * 8192)));
  });

  test('profile invalidation stops source delivery while a write is paused',
      () async {
    final disk = _SlowConsumer();
    final sink = IOSink(disk);
    var invalid = false;
    var produced = 0;
    var cancelled = false;
    Stream<List<int>> response() async* {
      try {
        for (var i = 0; i < 128; i++) {
          produced++;
          yield [i];
        }
      } finally {
        cancelled = true;
      }
    }

    final pending = writeStreamToFileSink(response(), sink, checkCurrent: () {
      if (invalid) throw const _Invalidated();
    });
    final result = expectLater(pending, throwsA(isA<_Invalidated>()));
    await disk.started.future;
    await Future<void>.delayed(Duration.zero);
    invalid = true;
    disk.release.complete();
    await result;
    try {
      await sink.close();
    } catch (_) {}
    expect(cancelled, isTrue);
    expect(produced, lessThan(128));
  });

  test('a file write error cancels the response and remains observable',
      () async {
    final disk = _FailingConsumer();
    final sink = IOSink(disk);
    var cancelled = false;
    var produced = 0;
    Stream<List<int>> response() async* {
      try {
        for (var i = 0; i < 128; i++) {
          produced++;
          yield [i];
        }
      } finally {
        cancelled = true;
      }
    }

    await expectLater(
      writeStreamToFileSink(response(), sink, checkCurrent: () {}),
      throwsA(isA<FileSystemException>()),
    );
    await sink.close();
    expect(cancelled, isTrue);
    expect(produced, 1);
    expect(disk.closed, isTrue);
  });

  test('response errors retain partial progress and never report completion',
      () async {
    final disk = _SlowConsumer()..release.complete();
    final sink = IOSink(disk);
    final progress = <int>[];
    Stream<List<int>> response() async* {
      yield [1, 2, 3];
      throw const HttpException('Synthetic connection closed');
    }

    await expectLater(
      writeStreamToFileSink(response(), sink,
          checkCurrent: () {},
          total: 10,
          onProgress: (received, _) => progress.add(received)),
      throwsA(isA<HttpException>()),
    );
    await sink.close();
    expect(progress, [3]);
    expect(disk.bytes, 3);
  });
}

class _Invalidated implements Exception {
  const _Invalidated();
}

class _SlowConsumer implements StreamConsumer<List<int>> {
  final started = Completer<void>();
  final release = Completer<void>();
  int bytes = 0;

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      bytes += chunk.length;
      if (!started.isCompleted) {
        started.complete();
        await release.future;
      }
    }
  }

  @override
  Future<void> close() async {}
}

class _FailingConsumer implements StreamConsumer<List<int>> {
  bool closed = false;

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final _ in stream) {
      throw const FileSystemException('Synthetic disk full');
    }
  }

  @override
  Future<void> close() async => closed = true;
}
