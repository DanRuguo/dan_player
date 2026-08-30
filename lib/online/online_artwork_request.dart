import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// One cancellable artwork request. It returns a validated, size-limited PNG
/// preview; it never writes to a music file or changes any of its tags.
class OnlineArtworkRequest {
  OnlineArtworkRequest({HttpClient Function()? httpClientFactory})
      : _httpClientFactory = httpClientFactory ?? HttpClient.new;

  final HttpClient Function() _httpClientFactory;
  HttpClient? _client;
  bool _cancelled = false;
  static const _timeout = Duration(seconds: 20);
  static const _byteLimit = 10 * 1024 * 1024;

  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
  }

  void _checkCancelled() {
    if (_cancelled) throw const HttpException('封面下载已取消');
  }

  Future<Uint8List> loadPng(String address) async {
    _checkCancelled();
    var uri = Uri.tryParse(address);
    if (uri?.scheme == 'http') uri = uri!.replace(scheme: 'https');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('封面来源没有提供有效的 HTTPS 图片地址');
    }
    final client = _httpClientFactory()..connectionTimeout = _timeout;
    _client = client;
    final bytes = BytesBuilder(copy: false);
    try {
      HttpClientResponse? response;
      for (var redirects = 0; redirects <= 5; redirects++) {
        _checkCancelled();
        if (uri!.scheme != 'https' ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty) {
          throw const HttpException('封面下载包含不安全的重定向');
        }
        final request = await client.getUrl(uri).timeout(_timeout);
        request.followRedirects = false;
        request.headers.set(HttpHeaders.userAgentHeader, 'Dan-Player/26.0.3');
        response = await request.close().timeout(_timeout);
        _checkCancelled();
        if (!const [301, 302, 303, 307, 308].contains(response.statusCode)) {
          break;
        }
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location == null) throw const HttpException('封面重定向无效');
        uri = uri.resolve(location);
        await response.listen((_) {}).cancel();
        response = null;
      }
      if (response == null) throw const HttpException('封面重定向次数过多');
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('封面服务器返回 HTTP ${response.statusCode}');
      }
      if (response.contentLength > _byteLimit) {
        throw const FormatException('封面超过 10 MiB，已停止下载');
      }
      await for (final chunk in response.timeout(_timeout)) {
        _checkCancelled();
        if (bytes.length + chunk.length > _byteLimit) {
          throw const FormatException('封面超过 10 MiB，已停止下载');
        }
        bytes.add(chunk);
      }
    } finally {
      client.close(force: true);
      _client = null;
    }
    _checkCancelled();
    if (bytes.isEmpty) throw const FormatException('封面服务器返回了空图片');

    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes.takeBytes());
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? decoded;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width <= 0 ||
          descriptor.height <= 0 ||
          descriptor.width * descriptor.height > 64000000) {
        throw const FormatException('封面图片尺寸异常');
      }
      final scale =
          math.min(1.0, 1600 / math.max(descriptor.width, descriptor.height));
      codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (descriptor.width * scale).round()),
        targetHeight: math.max(1, (descriptor.height * scale).round()),
      );
      decoded = (await codec.getNextFrame()).image;
      final png = await decoded.toByteData(format: ui.ImageByteFormat.png);
      _checkCancelled();
      if (png == null) throw const FormatException('无法解析封面图片');
      return png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
    } finally {
      decoded?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }
}
