import 'dart:async';
import 'dart:io';

/// Transport-facing cancellation without coupling standalone provider parsers
/// to the music service or its presentation error types.
abstract interface class OnlineHttpCancellation {
  void check();
  void Function() onCancel(void Function() listener);
  Future<T> race<T>(Future<T> operation);
}

/// Owns one client from connection through the last response byte. A stream's
/// per-event timeout alone cannot bound a server that keeps sending small chunks.
Future<T> runBoundedOnlineRequest<T>({
  required HttpClient Function() createClient,
  required Duration timeout,
  required Future<T> Function(HttpClient client) request,
  OnlineHttpCancellation? cancellation,
}) async {
  cancellation?.check();
  final client = createClient()..connectionTimeout = timeout;
  final deadline = Completer<void>();
  var expired = false;
  final timer = Timer(timeout, () {
    expired = true;
    deadline.complete();
    client.close(force: true);
  });
  final unlink = cancellation?.onCancel(() => client.close(force: true));
  try {
    cancellation?.check();
    final operation = Future<T>.sync(() => request(client));
    final result = await Future.any<T>([
      cancellation?.race(operation) ?? operation,
      deadline.future.then<T>(
          (_) => throw TimeoutException('Online request timed out', timeout)),
    ]);
    cancellation?.check();
    return result;
  } catch (_) {
    cancellation?.check();
    // force-close may surface as HttpException before the deadline future.
    if (expired) throw TimeoutException('Online request timed out', timeout);
    rethrow;
  } finally {
    timer.cancel();
    unlink?.call();
    client.close(force: true);
  }
}
