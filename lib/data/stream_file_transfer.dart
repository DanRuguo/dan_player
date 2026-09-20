import 'dart:io';

/// Copies one response with disk backpressure. Validation/progress belong to
/// the active response; the caller owns file flush, close and atomic commit.
Future<int> writeStreamToFileSink(
  Stream<List<int>> source,
  IOSink sink, {
  required void Function() checkCurrent,
  int? total,
  void Function(int received, int? total)? onProgress,
}) async {
  var received = 0;
  // addStream propagates the file consumer's pause upstream. Calling add in
  // an await-for loop only waits for the network; a slow/cloud disk could
  // otherwise queue the complete response in the sink's memory buffer.
  await sink.addStream(source.map((chunk) {
    checkCurrent();
    received += chunk.length;
    onProgress?.call(received, total);
    return chunk;
  }));
  return received;
}
