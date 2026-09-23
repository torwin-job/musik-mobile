import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../domain/playback/playback_controller.dart';
import '../../providers/catalog_providers.dart';
import '../../widgets/auth_artwork.dart';
import '../../widgets/shelf.dart';

class PlayerPage extends ConsumerWidget {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasTrack = ref.watch(
      playbackControllerProvider.select((state) => state.current != null),
    );

    return Scaffold(
      appBar: AppBar(title: const _PlayerAppBarTitle()),
      body: !hasTrack
          ? const _EmptyPlayer()
          : ListView(
              key: const PageStorageKey('player-scroll'),
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              addAutomaticKeepAlives: false,
              children: const [
                _PlayerError(),
                _NowPlayingSection(),
                SizedBox(height: 8),
                PlayerScrubber(),
                _PlayerTransport(),
                _CurrentTrackActions(),
                _CurrentLyrics(),
                _CurrentRelated(),
                _UpNextSection(),
              ],
            ),
    );
  }
}

class _PlayerAppBarTitle extends ConsumerWidget {
  const _PlayerAppBarTitle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(
      playbackControllerProvider.select(
        (state) => state.name ?? (state.mode == 'radio' ? 'Радио' : 'Сейчас'),
      ),
    );
    return Text(name, style: const TextStyle(fontSize: 20));
  }
}

class _EmptyPlayer extends ConsumerWidget {
  const _EmptyPlayer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loading = ref.watch(
      playbackControllerProvider.select((state) => state.loading),
    );
    final ctl = ref.read(playbackControllerProvider.notifier);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.headphones, size: 56, color: MusikColors.muted),
            const SizedBox(height: 16),
            const Text(
              'Ничего не играет',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            const SizedBox(height: 8),
            const Text(
              'Запусти радио или выбери микс на главной',
              textAlign: TextAlign.center,
              style: TextStyle(color: MusikColors.muted),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: loading
                  ? null
                  : () async {
                      try {
                        await ctl.startRadio();
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('$e')));
                        }
                      }
                    },
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Радио'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerError extends ConsumerWidget {
  const _PlayerError();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final error = ref.watch(
      playbackControllerProvider.select((state) => state.error),
    );
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: error == null
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                error,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
    );
  }
}

class _NowPlayingSection extends ConsumerWidget {
  const _NowPlayingSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(
      playbackControllerProvider.select((state) => state.current),
    );
    if (track == null) return const SizedBox.shrink();
    final size = MediaQuery.sizeOf(context);
    final art = (size.shortestSide * 0.55).clamp(160.0, 280.0);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 160),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(begin: 0.975, end: 1.0).animate(animation),
          child: child,
        ),
      ),
      child: Column(
        key: ValueKey(track.id),
        children: [
          Center(
            child: AuthArtwork(
              pathOrUrl: track.artworkPath,
              size: art,
              borderRadius: 16,
            ),
          ),
          const SizedBox(height: 22),
          Text(
            track.title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: () => context.push(
              '/artist?name=${Uri.encodeComponent(track.artist)}',
            ),
            child: Text(
              [
                track.artist,
                if (track.album != null && track.album!.isNotEmpty) track.album,
              ].join(' · '),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: MusikColors.muted, fontSize: 14),
            ),
          ),
          if (track.album != null && track.album!.isNotEmpty)
            TextButton(
              onPressed: () => context.push(
                '/album?artist=${Uri.encodeComponent(track.artist)}'
                '&album=${Uri.encodeComponent(track.album!)}',
              ),
              child: const Text('Открыть альбом'),
            ),
        ],
      ),
    );
  }
}

class _CurrentTrackActions extends ConsumerWidget {
  const _CurrentTrackActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(
      playbackControllerProvider.select((state) => state.current),
    );
    return track == null
        ? const SizedBox.shrink()
        : _PlayerActions(key: ValueKey(track.id), track: track);
  }
}

class _CurrentLyrics extends ConsumerWidget {
  const _CurrentLyrics();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trackId = ref.watch(
      playbackControllerProvider.select((state) => state.current?.id),
    );
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: trackId == null
          ? const SizedBox.shrink()
          : _LyricsSection(key: ValueKey(trackId), trackId: trackId),
    );
  }
}

class _CurrentRelated extends ConsumerWidget {
  const _CurrentRelated();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(
      playbackControllerProvider.select((state) => state.current),
    );
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SizeTransition(sizeFactor: animation, child: child),
      ),
      child: track == null
          ? const SizedBox.shrink()
          : _RelatedSection(key: ValueKey(track.id), track: track),
    );
  }
}

String _fmtDur(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (d.inHours > 0) return '${d.inHours}:$m:$s';
  return '${d.inMinutes}:$s';
}

class PlayerScrubber extends ConsumerStatefulWidget {
  const PlayerScrubber({super.key});

  @override
  ConsumerState<PlayerScrubber> createState() => _PlayerScrubberState();
}

class _PlayerScrubberState extends ConsumerState<PlayerScrubber> {
  double? _dragFraction;

  @override
  Widget build(BuildContext context) {
    final tick = ref.watch(playbackProgressProvider);
    final ctl = ref.read(playbackControllerProvider.notifier);
    final fraction = (_dragFraction ?? tick.fraction).clamp(0.0, 1.0);
    final shownPosition = _dragFraction == null
        ? tick.position
        : Duration(
            milliseconds: (fraction * tick.duration.inMilliseconds).round(),
          );
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 22),
          ),
          child: Slider(
            value: fraction,
            semanticFormatterCallback: (value) => _fmtDur(
              Duration(
                milliseconds: (value * tick.duration.inMilliseconds).round(),
              ),
            ),
            onChanged: tick.duration.inMilliseconds == 0
                ? null
                : (value) => setState(() => _dragFraction = value),
            onChangeEnd: (value) {
              final duration = tick.duration.inMilliseconds;
              if (duration == 0) return;
              setState(() => _dragFraction = null);
              ctl.seek(Duration(milliseconds: (value * duration).round()));
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _fmtDur(shownPosition),
                style: const TextStyle(color: MusikColors.muted, fontSize: 12),
              ),
              Text(
                _fmtDur(tick.duration),
                style: const TextStyle(color: MusikColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlayerTransport extends ConsumerWidget {
  const _PlayerTransport();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fallbackPlaying = ref.watch(
      playbackControllerProvider.select((s) => s.playing),
    );
    final playing =
        ref.watch(livePlayingProvider).asData?.value ?? fallbackPlaying;
    final rating = ref.watch(
      playbackControllerProvider.select((s) => s.rating),
    );
    final ctl = ref.read(playbackControllerProvider.notifier);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _Ctrl(
          icon: Icons.thumb_down_alt_outlined,
          tooltip: 'Не нравится',
          active: rating == ListenRating.dislike,
          onTap: ctl.dislike,
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: ctl.togglePlay,
          style: FilledButton.styleFrom(
            shape: const CircleBorder(),
            padding: const EdgeInsets.all(16),
          ),
          child: Tooltip(
            message: playing ? 'Пауза' : 'Воспроизвести',
            child: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 36,
            ),
          ),
        ),
        const SizedBox(width: 8),
        _Ctrl(
          icon: Icons.skip_next_rounded,
          tooltip: 'Следующий трек',
          onTap: ctl.skip,
          large: true,
        ),
        const SizedBox(width: 8),
        _Ctrl(
          icon: Icons.favorite_rounded,
          tooltip: 'Нравится',
          active: rating == ListenRating.like,
          onTap: ctl.like,
        ),
      ],
    );
  }
}

class _PlayerActions extends ConsumerWidget {
  const _PlayerActions({super.key, required this.track});

  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loading = ref.watch(
      playbackControllerProvider.select((s) => s.loading),
    );
    final ctl = ref.read(playbackControllerProvider.notifier);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 4,
      children: [
        TextButton(
          onPressed: () async {
            try {
              await ctl.toggleFavoriteArtist();
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('♥ артист')));
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('$e')));
              }
            }
          },
          child: const Text('♥ артист'),
        ),
        TextButton(
          onPressed: track.album == null
              ? null
              : () async {
                  try {
                    await ctl.toggleFavoriteAlbum();
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('♥ альбом')));
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('$e')));
                    }
                  }
                },
          child: const Text('♥ альбом'),
        ),
        TextButton(
          onPressed: () async {
            try {
              await ctl.addLater();
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('В «Потом»')));
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('$e')));
              }
            }
          },
          child: const Text('Потом'),
        ),
        TextButton(
          onPressed: loading
              ? null
              : () async {
                  try {
                    await ctl.playSimilarTo(track);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('$e')));
                    }
                  }
                },
          child: const Text('Похожее'),
        ),
      ],
    );
  }
}

class _UpNextSection extends ConsumerStatefulWidget {
  const _UpNextSection();

  @override
  ConsumerState<_UpNextSection> createState() => _UpNextSectionState();
}

class _UpNextSectionState extends ConsumerState<_UpNextSection> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final pb = ref.watch(playbackControllerProvider);
    final ctl = ref.read(playbackControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _buildUpNext(pb, ctl),
    );
  }

  List<Widget> _buildUpNext(PlaybackState pb, PlaybackController ctl) {
    if (pb.fixed && pb.playlist.length > 1) {
      final curId = pb.current?.id;
      var start = pb.index + 1;
      if (start < 0 || start > pb.playlist.length) {
        final i = pb.playlist.indexWhere((t) => t.id == curId);
        start = i >= 0 ? i + 1 : 0;
      }
      final allUpcoming = pb.playlist.skip(start).take(30).toList();
      final upcoming = allUpcoming.take(_expanded ? 30 : 8).toList();
      return [
        const SizedBox(height: 16),
        const Text(
          'Далее',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: 6),
        if (upcoming.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Конец плейлиста',
              style: TextStyle(color: MusikColors.muted),
            ),
          )
        else
          for (var i = 0; i < upcoming.length; i++)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Text(
                '${start + i + 1}',
                style: const TextStyle(color: MusikColors.muted),
              ),
              title: Text(
                upcoming[i].title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                upcoming[i].artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: MusikColors.muted, fontSize: 12),
              ),
              onTap: () => ctl.jumpTo(start + i),
            ),
        if (allUpcoming.length > 8)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(
                _expanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
              ),
              label: Text(_expanded ? 'Свернуть' : 'Показать очередь'),
            ),
          ),
      ];
    }

    if (!pb.fixed && pb.queue.isNotEmpty) {
      return [
        const SizedBox(height: 16),
        const Text(
          'Далее',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: 6),
        for (final q in pb.queue.take(12))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(q.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              q.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: MusikColors.muted, fontSize: 12),
            ),
          ),
      ];
    }

    return const [];
  }
}

class _LyricsSection extends ConsumerWidget {
  const _LyricsSection({super.key, required this.trackId});

  final int trackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(trackLyricsProvider(trackId));
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Текст',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 8),
          async.when(
            loading: () =>
                const Text('…', style: TextStyle(color: MusikColors.muted)),
            error: (_, _) => const Text(
              'не удалось загрузить',
              style: TextStyle(color: MusikColors.muted),
            ),
            data: (ly) {
              final text = ly?.displayText ?? 'Текста нет';
              return SelectableText(
                text,
                style: TextStyle(
                  color: (ly == null || ly.isAbsent || ly.instrumental)
                      ? MusikColors.muted
                      : MusikColors.fg,
                  height: 1.45,
                  fontSize: 14,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RelatedSection extends ConsumerWidget {
  const _RelatedSection({super.key, required this.track});

  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (id: track.id, artist: track.artist, album: track.album ?? '');
    final async = ref.watch(relatedForTrackProvider(key));
    final ctl = ref.read(playbackControllerProvider.notifier);

    final child = async.when(
      loading: () => const Padding(
        key: ValueKey('related-loading'),
        padding: EdgeInsets.only(top: 20),
        child: Text('Похожее…', style: TextStyle(color: MusikColors.muted)),
      ),
      error: (_, _) => const SizedBox.shrink(key: ValueKey('related-empty')),
      data: (rel) {
        if (rel.tracks.isEmpty && rel.artists.isEmpty && rel.albums.isEmpty) {
          return const SizedBox.shrink(key: ValueKey('related-empty'));
        }
        return Column(
          key: ValueKey('related-data-${track.id}'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (rel.tracks.isNotEmpty) ...[
              const SizedBox(height: 22),
              const Text(
                'Похожие треки',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 6),
              for (final t in rel.tracks.take(10))
                TrackRow(
                  title: t.title,
                  subtitle: t.artist,
                  artworkPath: '/api/artwork/${t.id}',
                  onTap: () => ctl.playTrack(t.id),
                ),
            ],
            if (rel.artists.isNotEmpty) ...[
              const SizedBox(height: 18),
              Shelf(
                title: 'Похожие артисты',
                child: ShelfRow(
                  itemCount: rel.artists.length.clamp(0, 12),
                  itemBuilder: (context, i) {
                    final a = rel.artists[i];
                    return CoverCard(
                      title: a.artist,
                      subtitle: a.explanation ?? '${a.tracks} треков',
                      artworkPath:
                          a.artwork ??
                          (a.coverTrackId != null
                              ? '/api/artwork/${a.coverTrackId}'
                              : null),
                      onTap: () => context.push(
                        '/artist?name=${Uri.encodeComponent(a.artist)}',
                      ),
                    );
                  },
                ),
              ),
            ],
            if (rel.albums.isNotEmpty) ...[
              const SizedBox(height: 18),
              Shelf(
                title: 'Похожие альбомы',
                child: ShelfRow(
                  itemCount: rel.albums.length.clamp(0, 12),
                  itemBuilder: (context, i) {
                    final a = rel.albums[i];
                    return CoverCard(
                      title: a.album,
                      subtitle: a.explanation ?? a.artist,
                      artworkPath:
                          a.artwork ??
                          (a.coverTrackId != null
                              ? '/api/artwork/${a.coverTrackId}'
                              : null),
                      onTap: () => context.push(
                        '/album?artist=${Uri.encodeComponent(a.artist)}'
                        '&album=${Uri.encodeComponent(a.album)}',
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        );
      },
    );
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SizeTransition(sizeFactor: animation, child: child),
      ),
      child: child,
    );
  }
}

class _Ctrl extends StatelessWidget {
  const _Ctrl({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.large = false,
  });

  final IconData icon;
  final String tooltip;
  final Future<void> Function() onTap;
  final bool active;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => onTap(),
      tooltip: tooltip,
      iconSize: large ? 34 : 26,
      icon: Icon(icon, color: active ? MusikColors.accent : MusikColors.fg),
    );
  }
}
