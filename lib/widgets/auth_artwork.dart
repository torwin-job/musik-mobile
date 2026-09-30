import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../providers/providers.dart';
import 'auth_art_provider.dart';

/// Cover art. Network starts only after the cover is actually painted,
/// and the JPEG is stored on disk so the same cover is downloaded once.
class AuthArtwork extends ConsumerStatefulWidget {
  const AuthArtwork({
    super.key,
    required this.pathOrUrl,
    this.size = 56,
    this.borderRadius = 10,
  });

  final String? pathOrUrl;
  final double size;
  final double borderRadius;

  @override
  ConsumerState<AuthArtwork> createState() => _AuthArtworkState();
}

class _AuthArtworkState extends ConsumerState<AuthArtwork> {
  Uint8List? _bytes;
  ArtSubscription? _sub;
  var _failed = false;

  @override
  void didUpdateWidget(covariant AuthArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pathOrUrl != widget.pathOrUrl ||
        oldWidget.size != widget.size) {
      _reset();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _reset() {
    _sub?.cancel();
    _sub = null;
    _bytes = null;
    _failed = false;
  }

  /// True when a load is running, done, or permanently failed.
  bool _startLoad() {
    if (!mounted || _failed || _bytes != null || _sub != null) return true;
    final path = widget.pathOrUrl;
    final api = ref.read(musikApiProvider);
    if (path == null || path.isEmpty || api == null) return false;
    final tokenAsync = ref.read(bearerTokenProvider);
    if (tokenAsync.isLoading) return false;

    final url = AuthArtImageProvider.thumbUrl(
      api.absoluteUrl(path),
      AuthArtImageProvider.bucketForSize(widget.size),
    );
    final cached = AuthArtImageProvider.peekBytes(url);
    if (cached != null) {
      setState(() => _bytes = cached);
      return true;
    }

    final sub = AuthArtImageProvider.subscribe(
      url: url,
      token: tokenAsync.asData?.value,
    );
    _sub = sub;
    sub.future
        .then((bytes) {
          if (!mounted || !identical(_sub, sub) || sub.cancelled) return;
          setState(() => _bytes = bytes);
        })
        .catchError((Object _) {
          if (!mounted || !identical(_sub, sub) || sub.cancelled) return;
          setState(() {
            _failed = true;
            _sub = null;
          });
        });
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    final child = bytes == null
        ? _PaintNotify(
            onPainted: _startLoad,
            child: _Placeholder(
              size: widget.size,
              borderRadius: widget.borderRadius,
            ),
          )
        : Image.memory(
            bytes,
            width: widget.size,
            height: widget.size,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.low,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => _Placeholder(
              size: widget.size,
              borderRadius: widget.borderRadius,
            ),
          );

    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: SizedBox(width: widget.size, height: widget.size, child: child),
      ),
    );
  }
}

class _PaintNotify extends SingleChildRenderObjectWidget {
  const _PaintNotify({required this.onPainted, required super.child});

  final bool Function() onPainted;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPaintNotify(onPainted);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPaintNotify renderObject,
  ) {
    renderObject.onPainted = onPainted;
  }
}

class _RenderPaintNotify extends RenderProxyBox {
  _RenderPaintNotify(this.onPainted);

  bool Function() onPainted;
  var _fired = false;

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (_fired) return;
    _fired = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!onPainted()) _fired = false;
    });
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.size, required this.borderRadius});

  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: MusikColors.bg2,
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(
          Icons.music_note,
          color: MusikColors.muted,
          size: size * 0.4,
        ),
      ),
    );
  }
}
