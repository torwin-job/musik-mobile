import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// One in-flight artwork download. Extra listeners share it; the last
/// listener to leave before it finishes aborts the HTTP call.
class ArtSubscription {
  ArtSubscription._(this._load);

  final _ArtLoad _load;
  var _cancelled = false;

  bool get cancelled => _cancelled;

  Future<Uint8List> get future => _load.future;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _load.release();
  }
}

class _ArtLoad {
  _ArtLoad(this.url, this.token);

  final String url;
  final String? token;
  int users = 0;
  var started = false;
  var finished = false;
  http.Client? client;
  final completer = Completer<Uint8List>();

  Future<Uint8List> get future => completer.future;

  void release() {
    if (finished) return;
    users--;
    if (users > 0) return;
    AuthArtImageProvider._drop(this);
  }
}

/// Bearer artwork: one file per cover size on disk, network only while
/// something on screen still wants it.
class AuthArtImageProvider {
  static final _memory = <String, Uint8List>{};
  static const _memoryMax = 48;
  static final _loads = <String, _ArtLoad>{};
  static final _queue = <_ArtLoad>[];
  static var _active = 0;
  static const _maxActive = 4;
  static Directory? _dir;

  /// Lists, cards and the mini-player share `w=256`. The large player uses 640.
  static int bucketForSize(double logicalSize) =>
      logicalSize >= 180 ? 640 : 256;

  /// Absolute artwork URL snapped to a server thumbnail width.
  static String thumbUrl(String absoluteUrl, int width) {
    final snapped = width >= 448 ? 640 : (width >= 176 ? 256 : 96);
    final u = Uri.parse(absoluteUrl);
    final q = Map<String, String>.from(u.queryParameters);
    q['w'] = '$snapped';
    return u.replace(queryParameters: q).toString();
  }

  static Uint8List? peekBytes(String url) => _memory[url];

  static void putBytes(String url, Uint8List bytes) => _remember(url, bytes);

  static Future<Uint8List> fetchBytes({
    required String url,
    required String? token,
  }) {
    final cached = _memory[url];
    if (cached != null) return SynchronousFuture(cached);
    return subscribe(url: url, token: token).future;
  }

  static ArtSubscription subscribe({
    required String url,
    required String? token,
  }) {
    final cached = _memory[url];
    if (cached != null) {
      final done = _ArtLoad(url, token)
        ..users = 1
        ..finished = true
        ..started = true;
      done.completer.complete(cached);
      return ArtSubscription._(done);
    }

    final existing = _loads[url];
    if (existing != null && !existing.finished) {
      existing.users++;
      return ArtSubscription._(existing);
    }

    final load = _ArtLoad(url, token)..users = 1;
    _loads[url] = load;
    _queue.add(load);
    _pump();
    return ArtSubscription._(load);
  }

  static void _drop(_ArtLoad load) {
    if (!_queue.remove(load)) {
      load.client?.close();
    }
    if (!load.completer.isCompleted) {
      load.finished = true;
      load.completer.completeError(StateError('cancelled'));
    }
    if (identical(_loads[load.url], load)) {
      _loads.remove(load.url);
    }
  }

  static void _pump() {
    while (_active < _maxActive && _queue.isNotEmpty) {
      final load = _queue.removeAt(0);
      if (load.finished || load.users <= 0) continue;
      load.started = true;
      _active++;
      unawaited(_run(load));
    }
  }

  static Future<void> _run(_ArtLoad load) async {
    try {
      final bytes = await _fromDiskOrNet(load);
      if (load.finished || load.users <= 0) {
        if (!load.completer.isCompleted) {
          load.finished = true;
          load.completer.completeError(StateError('cancelled'));
        }
        return;
      }
      load.finished = true;
      _remember(load.url, bytes);
      if (!load.completer.isCompleted) load.completer.complete(bytes);
    } catch (e, st) {
      load.finished = true;
      if (!load.completer.isCompleted) load.completer.completeError(e, st);
    } finally {
      _active--;
      if (identical(_loads[load.url], load)) _loads.remove(load.url);
      _pump();
    }
  }

  static Future<Uint8List> _fromDiskOrNet(_ArtLoad load) async {
    final disk = await _readDisk(load.url);
    if (disk != null) return disk;
    // Skip a fling: only covers that stay on screen reach the network.
    await Future<void>.delayed(const Duration(milliseconds: 90));
    if (load.users <= 0 || load.finished) throw StateError('cancelled');
    final client = http.Client();
    load.client = client;
    try {
      final res = await client.get(
        Uri.parse(load.url),
        headers: {
          if (load.token != null && load.token!.isNotEmpty)
            'Authorization': 'Bearer ${load.token}',
        },
      );
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) {
        throw StateError('art ${res.statusCode}');
      }
      final bytes = res.bodyBytes;
      await _writeDisk(load.url, bytes);
      return bytes;
    } finally {
      client.close();
      if (identical(load.client, client)) load.client = null;
    }
  }

  static void _remember(String url, Uint8List bytes) {
    _memory.remove(url);
    _memory[url] = bytes;
    while (_memory.length > _memoryMax) {
      _memory.remove(_memory.keys.first);
    }
  }

  static Future<File?> _file(String url) async {
    final dir = await _cacheDir();
    if (dir == null) return null;
    return File('${dir.path}/${_fileKey(url)}.jpg');
  }

  static Future<Directory?> _cacheDir() async {
    if (_dir != null) return _dir;
    try {
      final root = await getApplicationCacheDirectory();
      final dir = Directory('${root.path}/artwork');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _dir = dir;
      return dir;
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> _readDisk(String url) async {
    try {
      final file = await _file(url);
      if (file == null || !file.existsSync()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeDisk(String url, Uint8List bytes) async {
    try {
      final file = await _file(url);
      if (file == null) return;
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(file.path);
    } catch (_) {}
  }

  static String _fileKey(String url) {
    final uri = Uri.parse(url);
    final id = uri.pathSegments.isEmpty ? 'x' : uri.pathSegments.last;
    final width = uri.queryParameters['w'] ?? '0';
    final safe = id.replaceAll(RegExp(r'[^0-9A-Za-z_-]'), '');
    return '${safe}_w$width';
  }
}
