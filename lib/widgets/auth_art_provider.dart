import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;

/// Limits parallel artwork downloads so scroll doesn't spawn dozens of HTTP+decodes.
class _ArtGate {
  static const max = 2;
  static int _active = 0;
  static final _queue = <Completer<void>>[];

  static Future<void> acquire() async {
    if (_active >= max) {
      final c = Completer<void>();
      _queue.add(c);
      await c.future;
    }
    _active++;
  }

  static void release() {
    _active = (_active - 1).clamp(0, 1000);
    if (_queue.isNotEmpty && _active < max) {
      _queue.removeAt(0).complete();
    }
  }
}

/// Bearer-auth cover art. Requests server thumbnails via `?w=` when possible.
class AuthArtImageProvider extends ImageProvider<AuthArtImageProvider> {
  const AuthArtImageProvider(
    this.url, {
    required this.token,
    required this.cachePx,
  });

  final String url;
  final String? token;
  final int cachePx;

  static final _jpeg = <String, Uint8List>{};
  static final _inFlight = <String, Future<Uint8List>>{};
  static const _jpegMax = 64;

  /// Absolute artwork URL with optional width hint for the player API.
  static String thumbUrl(String absoluteUrl, int width) {
    final u = Uri.parse(absoluteUrl);
    final q = Map<String, String>.from(u.queryParameters);
    q['w'] = '$width';
    return u.replace(queryParameters: q).toString();
  }

  static Uint8List? peekBytes(String url) => _jpeg[url];

  static void putBytes(String url, Uint8List bytes) {
    while (_jpeg.length >= _jpegMax && !_jpeg.containsKey(url)) {
      _jpeg.remove(_jpeg.keys.first);
    }
    _jpeg.remove(url);
    _jpeg[url] = bytes;
  }

  /// Fetch (or reuse) JPEG bytes — shared by UI ImageProvider and notification art.
  static Future<Uint8List> fetchBytes({
    required String url,
    required String? token,
  }) {
    final cached = _jpeg.remove(url);
    if (cached != null) {
      _jpeg[url] = cached;
      return SynchronousFuture(cached);
    }
    // Do not let an early unauthenticated request absorb the request made
    // after bearerTokenProvider resolves. They share a URL but not auth.
    final requestKey = '$url\u0000${token ?? ''}';
    final running = _inFlight[requestKey];
    if (running != null) return running;

    final request = _fetchAndCache(url: url, token: token);
    _inFlight[requestKey] = request;
    void clear() {
      if (identical(_inFlight[requestKey], request)) {
        _inFlight.remove(requestKey);
      }
    }

    request.then<void>((_) => clear(), onError: (_, _) => clear());
    return request;
  }

  static Future<Uint8List> _fetchAndCache({
    required String url,
    required String? token,
  }) async {
    await _ArtGate.acquire();
    try {
      final again = _jpeg[url];
      if (again != null) return again;
      final res = await http.get(
        Uri.parse(url),
        headers: {
          if (token != null && token.isNotEmpty)
            'Authorization': 'Bearer $token',
        },
      );
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) {
        throw StateError('art ${res.statusCode}');
      }
      final bytes = res.bodyBytes;
      putBytes(url, bytes);
      return bytes;
    } finally {
      _ArtGate.release();
    }
  }

  @override
  Future<AuthArtImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  ImageStreamCompleter loadImage(
    AuthArtImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _codec(key, decode),
      scale: 1,
      debugLabel: key.url,
    );
  }

  static Future<ui.Codec> _codec(
    AuthArtImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    final bytes = await fetchBytes(url: key.url, token: key.token);
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(
      buffer,
      getTargetSize: (intrinsicWidth, intrinsicHeight) {
        return ui.TargetImageSize(width: key.cachePx, height: key.cachePx);
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AuthArtImageProvider &&
      other.url == url &&
      other.token == token &&
      other.cachePx == cachePx;

  @override
  int get hashCode => Object.hash(url, token, cachePx);
}
