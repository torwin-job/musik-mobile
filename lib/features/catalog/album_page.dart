import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../domain/playback/playback_controller.dart';
import '../../providers/catalog_providers.dart';
import '../../widgets/auth_artwork.dart';
import '../../widgets/shelf.dart';

class AlbumPage extends ConsumerWidget {
  const AlbumPage({super.key, required this.artist, required this.album});

  final String artist;
  final String album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(
      albumDetailProvider((artist: artist, album: album)),
    );
    final ctl = ref.read(playbackControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(album)),
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
              key: PageStorageKey('album-$artist-$album'),
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
                              album,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            InkWell(
                              onTap: () => context.push(
                                '/artist?name=${Uri.encodeComponent(artist)}',
                              ),
                              child: Text(
                                artist,
                                style: const TextStyle(
                                  color: MusikColors.accent,
                                ),
                              ),
                            ),
                            Text(
                              '${data.tracks.length} треков',
                              style: const TextStyle(color: MusikColors.muted),
                            ),
                            const SizedBox(height: 10),
                            FilledButton.icon(
                              onPressed: () async {
                                try {
                                  await ctl.playAlbum(artist, album);
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
                              label: const Text('Слушать альбом'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
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
                if (data.tracks.isEmpty)
                  const SliverToBoxAdapter(
                    child: Text(
                      'Нет треков',
                      style: TextStyle(color: MusikColors.muted),
                    ),
                  )
                else
                  SliverList.builder(
                    itemCount: data.tracks.length,
                    itemBuilder: (context, i) {
                      final track = data.tracks[i];
                      return TrackRow(
                        title: track.title,
                        subtitle: '${i + 1}',
                        artworkPath: track.artworkPath,
                        onTap: () async {
                          try {
                            await ctl.playBody({
                              'track_ids': data.tracks
                                  .map((t) => t.id)
                                  .toList(),
                              'name': '$artist — $album',
                              'start_index': i,
                            });
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
                if (data.similar.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 22),
                      child: Shelf(
                        title: 'Похожие альбомы',
                        child: ShelfRow(
                          itemCount: data.similar.length.clamp(0, 12),
                          itemBuilder: (context, i) {
                            final a = data.similar[i];
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
