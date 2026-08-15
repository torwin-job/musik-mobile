import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../domain/playback/playback_controller.dart';
import '../../providers/catalog_providers.dart';
import '../../widgets/auth_artwork.dart';
import '../../widgets/shelf.dart';

class ArtistPage extends ConsumerWidget {
  const ArtistPage({super.key, required this.artist});

  final String artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(artistDetailProvider(artist));
    final ctl = ref.read(playbackControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(artist)),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (data) {
          final cover = data.tracks.isNotEmpty
              ? data.tracks.first.artworkPath
              : null;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            child: CustomScrollView(
              key: PageStorageKey('artist-$artist'),
              slivers: [
                SliverToBoxAdapter(
                  child: Row(
                    children: [
                      AuthArtwork(pathOrUrl: cover, size: 96, borderRadius: 14),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              artist,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${data.tracks.length} треков · ${data.albums.length} альбомов',
                              style: const TextStyle(color: MusikColors.muted),
                            ),
                            const SizedBox(height: 10),
                            FilledButton.icon(
                              onPressed: () async {
                                try {
                                  await ctl.playArtist(artist);
                                  if (context.mounted) context.go('/player');
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('$e')),
                                    );
                                  }
                                }
                              },
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: const Text('Слушать'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (data.albums.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: Shelf(
                        title: 'Альбомы',
                        child: ShelfRow(
                          itemCount: data.albums.length,
                          itemBuilder: (context, i) {
                            final a = data.albums[i];
                            return CoverCard(
                              title: a.album,
                              subtitle: '${a.tracks} треков',
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
                    ),
                  ),
                ],
                if (data.tracks.isNotEmpty) ...[
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.only(top: 22, bottom: 8),
                      child: Text(
                        'Треки',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  SliverList.builder(
                    itemCount: data.tracks.length,
                    itemBuilder: (context, i) {
                      final t = data.tracks[i];
                      return TrackRow(
                        title: t.title,
                        subtitle: t.album ?? artist,
                        artworkPath: t.artworkPath,
                        onTap: () async {
                          try {
                            await ctl.playTrack(t.id);
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(
                                context,
                              ).showSnackBar(SnackBar(content: Text('$e')));
                            }
                          }
                        },
                      );
                    },
                  ),
                ],
                if (data.similar.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 22),
                      child: Shelf(
                        title: 'Похожие артисты',
                        child: ShelfRow(
                          itemCount: data.similar.length.clamp(0, 12),
                          itemBuilder: (context, i) {
                            final a = data.similar[i];
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
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
