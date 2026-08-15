import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../providers/providers.dart';
import 'auth_art_provider.dart';

/// Cover art with Bearer auth — Flutter image cache + capped decode.
class AuthArtwork extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final path = pathOrUrl;
    final api = ref.watch(musikApiProvider);
    if (path == null || path.isEmpty || api == null) {
      return _Placeholder(size: size, borderRadius: borderRadius);
    }

    final tokenAsync = ref.watch(bearerTokenProvider);
    final token = tokenAsync.asData?.value;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cachePx = (size * dpr).round().clamp(48, 160);
    final url = AuthArtImageProvider.thumbUrl(api.absoluteUrl(path), cachePx);

    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Image(
          image: AuthArtImageProvider(url, token: token, cachePx: cachePx),
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.low,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, sync) {
            if (sync || frame != null) return child;
            return _Placeholder(size: size, borderRadius: borderRadius);
          },
          errorBuilder: (_, _, _) =>
              _Placeholder(size: size, borderRadius: borderRadius),
        ),
      ),
    );
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
