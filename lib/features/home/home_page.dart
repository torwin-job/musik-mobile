import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../domain/playback/playback_controller.dart';
import '../../providers/catalog_providers.dart';
import '../../widgets/shelf.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  Future<void> _play(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action, {
    bool openPlayer = false,
  }) async {
    try {
      await action();
      if (!context.mounted) return;
      if (openPlayer) context.go('/player');
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(homeCatalogProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('musik'),
        actions: [
          IconButton(
            tooltip: 'Поделиться радио',
            onPressed: () async {
              try {
                final share = await ref
                    .read(playbackControllerProvider.notifier)
                    .createShare();
                final url = share['url']?.toString() ?? '';
                if (url.isEmpty) throw Exception('Пустой URL');
                await Clipboard.setData(ClipboardData(text: url));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Ссылка скопирована')),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('$e')));
              }
            },
            icon: const Icon(Icons.ios_share_outlined),
          ),
          IconButton(
            tooltip: 'Настройки',
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: MusikColors.accent,
        onRefresh: ref.read(catalogActionsProvider).rebuildMixes,
        child: catalog.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            children: [
              Text('$e', style: const TextStyle(color: Colors.redAccent)),
            ],
          ),
          data: (data) {
            final sections = _buildSections(data);
            return ListView.builder(
              key: const PageStorageKey('home-feed'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              // Only build visible shelves — was building ~80 covers at once.
              itemCount: sections.length,
              cacheExtent: 280,
              addAutomaticKeepAlives: false,
              itemBuilder: (context, i) => sections[i](context, ref),
            );
          },
        ),
      ),
    );
  }

  List<Widget Function(BuildContext, WidgetRef)> _buildSections(
    HomeCatalog data,
  ) {
    final forYou = data.mixes
        .where(
          (m) =>
              !m.kind.startsWith('weekday_') &&
              m.special != 'later' &&
              m.kind != 'later',
        )
        .toList();
    final weekdays = data.mixes
        .where((m) => m.kind.startsWith('weekday_'))
        .toList();

    final out = <Widget Function(BuildContext, WidgetRef)>[
      (context, ref) => _RadioHero(
        onPlay: () => _play(
          context,
          ref,
          () => ref.read(playbackControllerProvider.notifier).startRadio(),
          openPlayer: true,
        ),
      ),
    ];

    if (data.error != null) {
      out.add(
        (context, ref) => Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            data.error!,
            style: const TextStyle(color: Colors.redAccent),
          ),
        ),
      );
    }

    void addShelf(Widget Function(BuildContext, WidgetRef) w) {
      out.add(
        (context, ref) => Padding(
          padding: const EdgeInsets.only(top: 22),
          child: w(context, ref),
        ),
      );
    }

    if (forYou.isNotEmpty) {
      addShelf(
        (context, ref) => Shelf(
          title: 'Для тебя',
          subtitle: data.favoritesCount > 0 ? '♥ ${data.favoritesCount}' : null,
          child: ShelfRow(
            itemCount: forYou.length.clamp(0, 10),
            itemBuilder: (context, i) {
              final m = forYou[i];
              return CoverCard(
                title: m.title,
                subtitle: m.subtitle ?? '${m.tracks} треков',
                highlight: m.highlight || m.today,
                enabled: m.ready,
                artworkPath: m.coverTrackId != null
                    ? '/api/artwork/${m.coverTrackId}'
                    : null,
                onTap: () => _play(
                  context,
                  ref,
                  () => ref
                      .read(playbackControllerProvider.notifier)
                      .playMix(m.kind),
                ),
              );
            },
          ),
        ),
      );
    }

    if (data.favorites.tracks.isNotEmpty) {
      addShelf(
        (context, ref) => Shelf(
          title: 'Любимое',
          subtitle:
              '${data.favorites.trackCount} · ${data.favorites.artistCount} арт.',
          onSeeAll: () => context.go('/library'),
          child: ShelfRow(
            itemCount: data.favorites.tracks.length,
            itemBuilder: (context, i) {
              final t = data.favorites.tracks[i];
              return CoverCard(
                title: t.title,
                subtitle: t.artist,
                artworkPath: t.artworkPath,
                onTap: () => _play(
                  context,
                  ref,
                  () => ref
                      .read(playbackControllerProvider.notifier)
                      .playTrack(t.id),
                ),
              );
            },
          ),
        ),
      );
    }

    if (data.favorites.artists.isNotEmpty) {
      addShelf(
        (context, ref) => Shelf(
          title: 'Любимые артисты',
          child: ShelfRow(
            itemCount: data.favorites.artists.length,
            itemBuilder: (context, i) {
              final a = data.favorites.artists[i];
              return CoverCard(
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
          ),
        ),
      );
    }

    if (data.favorites.albums.isNotEmpty) {
      addShelf(
        (context, ref) => Shelf(
          title: 'Любимые альбомы',
          child: ShelfRow(
            itemCount: data.favorites.albums.length,
            itemBuilder: (context, i) {
              final a = data.favorites.albums[i];
              return CoverCard(
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
          ),
        ),
      );
    }

    if (!data.recommend.empty &&
        (data.recommend.tracks.isNotEmpty ||
            data.recommend.artists.isNotEmpty ||
            data.recommend.albums.isNotEmpty)) {
      final tracks = data.recommend.tracks;
      final arts = data.recommend.artists;
      final albs = data.recommend.albums;
      final n = (tracks.length + arts.length + albs.length).clamp(0, 12);
      addShelf(
        (context, ref) => Shelf(
          title: 'Похожее на любимое',
          subtitle: data.recommend.explanation,
          child: ShelfRow(
            itemCount: n,
            itemBuilder: (context, i) {
              if (i < tracks.length) {
                final t = tracks[i];
                return CoverCard(
                  title: t.title,
                  subtitle: t.artist,
                  artworkPath: t.artworkPath,
                  onTap: () => _play(
                    context,
                    ref,
                    () => ref
                        .read(playbackControllerProvider.notifier)
                        .playTrack(t.id),
                  ),
                );
              }
              final ai = i - tracks.length;
              if (ai < arts.length) {
                final a = arts[ai];
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
              }
              final a = albs[ai - arts.length];
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
      );
    }

    if (data.later.isNotEmpty) {
      addShelf(
        (context, ref) => Shelf(
          title: 'Потом',
          child: ShelfRow(
            itemCount: data.later.length,
            itemBuilder: (context, i) {
              final t = data.later[i];
              return CoverCard(
                title: t.title,
                subtitle: t.artist,
                artworkPath: t.artworkPath,
                onTap: () => _play(
                  context,
                  ref,
                  () => ref
                      .read(playbackControllerProvider.notifier)
                      .playMix('later'),
                ),
              );
            },
          ),
        ),
      );
    }

    if (data.discoverNew.isNotEmpty || data.discoverOld.isNotEmpty) {
      addShelf(
        (context, ref) => Shelf(
          title: 'Открытия',
          subtitle: 'новые и забытые',
          child: Column(
            children: [
              for (final t in data.discoverNew)
                TrackRow(
                  title: t.album,
                  subtitle: t.explanation ?? t.artist,
                  artworkPath: t.trackIds.isNotEmpty
                      ? '/api/artwork/${t.trackIds.first}'
                      : null,
                  onTap: () => _play(
                    context,
                    ref,
                    () =>
                        ref.read(playbackControllerProvider.notifier).playBody({
                          'track_ids': t.trackIds,
                          'name': '${t.artist} — ${t.album}',
                        }),
                  ),
                ),
              for (final t in data.discoverOld)
                TrackRow(
                  title: t.album,
                  subtitle: t.explanation ?? 'забытое · ${t.artist}',
                  artworkPath: t.trackIds.isNotEmpty
                      ? '/api/artwork/${t.trackIds.first}'
                      : null,
                  onTap: () => _play(
                    context,
                    ref,
                    () =>
                        ref.read(playbackControllerProvider.notifier).playBody({
                          'track_ids': t.trackIds,
                          'name': '${t.artist} — ${t.album}',
                        }),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    if (weekdays.isNotEmpty) {
      addShelf(
        (context, ref) => Shelf(
          title: 'Дни недели',
          child: ShelfRow(
            itemCount: weekdays.length,
            itemBuilder: (context, i) {
              final m = weekdays[i];
              return CoverCard(
                title: m.title,
                subtitle: m.subtitle,
                highlight: m.today,
                enabled: m.ready,
                artworkPath: m.coverTrackId != null
                    ? '/api/artwork/${m.coverTrackId}'
                    : null,
                onTap: () => _play(
                  context,
                  ref,
                  () => ref
                      .read(playbackControllerProvider.notifier)
                      .playMix(m.kind),
                ),
              );
            },
          ),
        ),
      );
    }

    if (data.artists.isNotEmpty) {
      addShelf(
        (context, ref) => Shelf(
          title: 'Артисты',
          onSeeAll: () => context.go('/library'),
          child: ShelfRow(
            itemCount: data.artists.length,
            itemBuilder: (context, i) {
              final a = data.artists[i];
              return CoverCard(
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
          ),
        ),
      );
    }

    if (data.albums.isNotEmpty) {
      addShelf(
        (context, ref) => Shelf(
          title: 'Альбомы',
          onSeeAll: () => context.go('/library'),
          child: ShelfRow(
            itemCount: data.albums.length,
            itemBuilder: (context, i) {
              final a = data.albums[i];
              return CoverCard(
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
          ),
        ),
      );
    }

    if (forYou.isEmpty &&
        data.artists.isEmpty &&
        data.favorites.tracks.isEmpty &&
        data.error == null) {
      out.add(
        (context, ref) => const Padding(
          padding: EdgeInsets.only(top: 48),
          child: Text(
            'Библиотека пуста — просканируй музыку на сервере.',
            textAlign: TextAlign.center,
            style: TextStyle(color: MusikColors.muted),
          ),
        ),
      );
    }

    return out;
  }
}

class _RadioHero extends ConsumerWidget {
  const _RadioHero({required this.onPlay});

  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loading = ref.watch(
      playbackControllerProvider.select((s) => s.loading),
    );
    return Material(
      color: MusikColors.bg2,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onPlay,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: MusikColors.accent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: loading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: MusikColors.bg,
                        ),
                      )
                    : const Icon(
                        Icons.play_arrow_rounded,
                        color: MusikColors.bg,
                        size: 32,
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Слушать радио',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      loading ? 'запускаю…' : 'подстраивается под твой вкус',
                      style: const TextStyle(
                        color: MusikColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Обновить миксы',
                onPressed: () async {
                  try {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Собираю миксы…')),
                    );
                    await ref.read(catalogActionsProvider).rebuildMixes();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Миксы обновлены')),
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('$e')));
                  }
                },
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
