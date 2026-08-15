import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../domain/playback/playback_controller.dart';
import 'auth_artwork.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(
      playbackControllerProvider.select((s) => s.current),
    );
    if (track == null) return const SizedBox.shrink();

    final fallbackPlaying = ref.watch(
      playbackControllerProvider.select((s) => s.playing),
    );
    final playing =
        ref.watch(livePlayingProvider).asData?.value ?? fallbackPlaying;

    return RepaintBoundary(
      child: Material(
        color: MusikColors.bg2,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _MiniProgressBar(),
            InkWell(
              onTap: () => context.go('/player'),
              child: SizedBox(
                height: 58,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      AuthArtwork(
                        pathOrUrl: track.artworkPath,
                        size: 42,
                        borderRadius: 8,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: MusikColors.muted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => ref
                            .read(playbackControllerProvider.notifier)
                            .togglePlay(),
                        icon: Icon(
                          playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 28,
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => ref
                            .read(playbackControllerProvider.notifier)
                            .skip(),
                        icon: const Icon(Icons.skip_next_rounded, size: 28),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Isolated so 2Hz progress ticks don't rebuild track title / artwork.
class _MiniProgressBar extends ConsumerWidget {
  const _MiniProgressBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Quantize to 1% — fewer rebuilds while still looking smooth enough.
    final fraction = ref.watch(
      playbackProgressProvider.select((p) => (p.fraction * 100).round() / 100),
    );
    return LinearProgressIndicator(
      value: fraction,
      minHeight: 2,
      backgroundColor: MusikColors.line,
      color: MusikColors.accent,
    );
  }
}
