import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../domain/playback/playback_controller.dart';
import '../../providers/catalog_providers.dart';
import '../../widgets/shelf.dart';

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  var _segment = 0;
  final _query = TextEditingController();
  Timer? _searchDebounce;
  var _effectiveQuery = '';

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      setState(() => _effectiveQuery = value.trim().toLowerCase());
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _query.clear();
    setState(() => _effectiveQuery = '');
  }

  Future<void> _play(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(libraryCatalogProvider);
    final q = _effectiveQuery;

    return Scaffold(
      appBar: AppBar(title: const Text('Библиотека')),
      body: catalog.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_rounded, size: 42),
                const SizedBox(height: 12),
                Text('$e', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => ref.invalidate(libraryCatalogProvider),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Повторить'),
                ),
              ],
            ),
          ),
        ),
        data: (data) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _query,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: switch (_segment) {
                      1 => 'Поиск артиста…',
                      2 => 'Поиск альбома…',
                      3 => 'Поиск в избранном…',
                      4 => 'Поиск в «Потом»…',
                      _ => 'Артист, трек, альбом…',
                    },
                    isDense: true,
                    suffixIcon: _query.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Очистить поиск',
                            onPressed: _clearSearch,
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                  onChanged: (value) {
                    setState(() {});
                    _onSearchChanged(value);
                  },
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Треки')),
                    ButtonSegment(value: 1, label: Text('Артисты')),
                    ButtonSegment(value: 2, label: Text('Альбомы')),
                    ButtonSegment(value: 3, label: Text('♥')),
                    ButtonSegment(value: 4, label: Text('Потом')),
                  ],
                  selected: {_segment},
                  onSelectionChanged: (s) => setState(() => _segment = s.first),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: RefreshIndicator(
                  color: MusikColors.accent,
                  onRefresh: () async => ref.invalidate(libraryCatalogProvider),
                  child: Builder(
                    builder: (context) {
                      if (_segment == 0) {
                        final items = data.tracks.where((t) {
                          if (q.isEmpty) return true;
                          return t.title.toLowerCase().contains(q) ||
                              t.artist.toLowerCase().contains(q) ||
                              (t.album ?? '').toLowerCase().contains(q);
                        }).toList();
                        return ListView.builder(
                          key: const PageStorageKey('library-tracks'),
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                          itemCount: items.length,
                          itemBuilder: (context, i) {
                            final t = items[i];
                            return TrackRow(
                              title: t.title,
                              subtitle: t.artist,
                              artworkPath: t.artworkPath,
                              onTap: () => _play(
                                () => ref
                                    .read(playbackControllerProvider.notifier)
                                    .playTrack(t.id),
                              ),
                            );
                          },
                        );
                      }
                      if (_segment == 1) {
                        final items = data.artists.where((a) {
                          if (q.isEmpty) return true;
                          return a.artist.toLowerCase().contains(q);
                        }).toList();
                        return ListView.builder(
                          key: const PageStorageKey('library-artists'),
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                          itemCount: items.length,
                          itemBuilder: (context, i) {
                            final a = items[i];
                            return TrackRow(
                              title: a.artist,
                              subtitle: '${a.tracks} треков',
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
                        );
                      }
                      if (_segment == 2) {
                        final items = data.albums.where((a) {
                          if (q.isEmpty) return true;
                          return a.album.toLowerCase().contains(q) ||
                              a.artist.toLowerCase().contains(q);
                        }).toList();
                        return ListView.builder(
                          key: const PageStorageKey('library-albums'),
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                          itemCount: items.length,
                          itemBuilder: (context, i) {
                            final a = items[i];
                            return TrackRow(
                              title: a.album,
                              subtitle: '${a.artist} · ${a.tracks}',
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
                        );
                      }
                      if (_segment == 3) {
                        final fav = data.favorites;
                        final tracks = fav.tracks.where((t) {
                          if (q.isEmpty) return true;
                          return t.title.toLowerCase().contains(q) ||
                              t.artist.toLowerCase().contains(q);
                        }).toList();
                        if (tracks.isEmpty &&
                            fav.artists.isEmpty &&
                            fav.albums.isEmpty) {
                          return ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(32),
                            children: const [
                              Text(
                                'Пока пусто — жми ♥ в плеере',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: MusikColors.muted),
                              ),
                            ],
                          );
                        }
                        final rows = <({String kind, Object? value})>[
                          if (tracks.isNotEmpty)
                            (kind: 'header', value: 'Треки'),
                          for (final track in tracks)
                            (kind: 'track', value: track),
                          if (fav.artists.isNotEmpty)
                            (kind: 'header', value: 'Артисты'),
                          for (final artist in fav.artists)
                            (kind: 'artist', value: artist),
                          if (fav.albums.isNotEmpty)
                            (kind: 'header', value: 'Альбомы'),
                          for (final album in fav.albums)
                            (kind: 'album', value: album),
                        ];
                        return ListView.builder(
                          key: const PageStorageKey('library-favorites'),
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                          itemCount: rows.length,
                          itemBuilder: (context, i) {
                            final row = rows[i];
                            if (row.kind == 'header') {
                              return Padding(
                                padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
                                child: Text(
                                  row.value! as String,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              );
                            }
                            if (row.kind == 'track') {
                              final t = row.value! as Track;
                              return TrackRow(
                                title: t.title,
                                subtitle: t.artist,
                                artworkPath: t.artworkPath,
                                onTap: () => _play(
                                  () => ref
                                      .read(playbackControllerProvider.notifier)
                                      .playTrack(t.id),
                                ),
                              );
                            }
                            if (row.kind == 'artist') {
                              final a = row.value! as ArtistCard;
                              return TrackRow(
                                title: a.artist,
                                subtitle: '${a.tracks} треков',
                                artworkPath:
                                    a.artwork ??
                                    (a.coverTrackId != null
                                        ? '/api/artwork/${a.coverTrackId}'
                                        : null),
                                onTap: () => context.push(
                                  '/artist?name=${Uri.encodeComponent(a.artist)}',
                                ),
                              );
                            }
                            final a = row.value! as AlbumCard;
                            return TrackRow(
                              title: a.album,
                              subtitle: a.artist,
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
                        );
                      }
                      // later
                      final items = data.later.where((t) {
                        if (q.isEmpty) return true;
                        return t.title.toLowerCase().contains(q) ||
                            t.artist.toLowerCase().contains(q);
                      }).toList();
                      if (items.isEmpty) {
                        return ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(32),
                          children: const [
                            Text(
                              'Список «Потом» пуст',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: MusikColors.muted),
                            ),
                          ],
                        );
                      }
                      return ListView.builder(
                        key: const PageStorageKey('library-later'),
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                        itemCount: items.length + 1,
                        itemBuilder: (context, i) {
                          if (i == 0) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: FilledButton.tonal(
                                onPressed: () => _play(
                                  () => ref
                                      .read(playbackControllerProvider.notifier)
                                      .playMix('later'),
                                ),
                                child: const Text('Слушать «Потом»'),
                              ),
                            );
                          }
                          final t = items[i - 1];
                          return TrackRow(
                            title: t.title,
                            subtitle: t.artist,
                            artworkPath: t.artworkPath,
                            onTap: () => _play(
                              () => ref
                                  .read(playbackControllerProvider.notifier)
                                  .playTrack(t.id),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
