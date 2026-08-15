import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api/musik_api.dart';
import '../data/models/models.dart';
import 'providers.dart';

class CatalogActions {
  CatalogActions(this._ref);

  final Ref _ref;

  MusikApi get _api {
    final api = _ref.read(musikApiProvider);
    if (api == null) throw Exception('API не готов');
    return api;
  }

  Future<void> rebuildMixes() async {
    final api = _api;
    final queued = await api.enqueueJob('mix_pack');
    final rawId = queued['id'] ?? queued['job_id'];
    final id = rawId is num ? rawId.toInt() : int.tryParse('$rawId');
    if (id == null || id <= 0) {
      throw Exception('Сервер не вернул id задачи');
    }

    await api.waitForJob(id);
    _ref.invalidate(homeCatalogProvider);
    await _ref.read(homeCatalogProvider.future);
  }

  Future<Map<String, dynamic>> toggleFavorite(Map<String, dynamic> body) async {
    final result = await _api.favoritesToggle(body);
    _ref.invalidate(homeCatalogProvider);
    _ref.invalidate(favoritesBundleProvider);
    return result;
  }
}

final catalogActionsProvider = Provider<CatalogActions>(CatalogActions.new);

class HomeCatalog {
  const HomeCatalog({
    required this.mixes,
    required this.artists,
    required this.albums,
    this.favorites = const FavoritesBundle(),
    this.recommend = const RecommendBundle(empty: true),
    this.discoverNew = const [],
    this.discoverOld = const [],
    this.later = const [],
    this.error,
  });

  final List<MixCard> mixes;
  final List<ArtistCard> artists;
  final List<AlbumCard> albums;
  final FavoritesBundle favorites;
  final RecommendBundle recommend;
  final List<DiscoverTip> discoverNew;
  final List<DiscoverTip> discoverOld;
  final List<Track> later;
  final String? error;

  int get favoritesCount => favorites.trackCount;
}

/// Home feed — wave‑1 shelves first, wave‑2 fills in without blocking UI.
class HomeCatalogNotifier extends AsyncNotifier<HomeCatalog> {
  int _buildGeneration = 0;

  @override
  Future<HomeCatalog> build() async {
    final generation = ++_buildGeneration;
    final api = ref.watch(musikApiProvider);
    if (api == null) {
      return const HomeCatalog(
        mixes: [],
        artists: [],
        albums: [],
        error: 'API не готов',
      );
    }
    try {
      final core = await Future.wait([
        api.mixes(),
        api.artists(),
        api.albums(),
        api.favoritesBundle().catchError((_) => const FavoritesBundle()),
      ]);

      final mixes = core[0] as List<MixCard>;
      final artists = (core[1] as List<ArtistCard>).take(8).toList();
      final albums = (core[2] as List<AlbumCard>).take(8).toList();
      final fav = core[3] as FavoritesBundle;
      final favorites = FavoritesBundle(
        tracks: fav.tracks.take(8).toList(),
        artists: fav.artists.take(8).toList(),
        albums: fav.albums.take(8).toList(),
        ids: fav.ids,
        trackCount: fav.trackCount,
        artistCount: fav.artistCount,
        albumCount: fav.albumCount,
      );

      final first = HomeCatalog(
        mixes: mixes,
        artists: artists,
        albums: albums,
        favorites: favorites,
      );

      // Show wave‑1 immediately; pull recommend/discover/later in background.
      // ignore: unawaited_futures
      _loadWave2(api, first, generation);
      return first;
    } catch (e) {
      return HomeCatalog(
        mixes: const [],
        artists: const [],
        albums: const [],
        error: e.toString(),
      );
    }
  }

  Future<void> _loadWave2(
    MusikApi api,
    HomeCatalog base,
    int generation,
  ) async {
    try {
      final extra = await Future.wait([
        api.recommendFavorites().catchError(
          (_) => const RecommendBundle(empty: true),
        ),
        api.discoverAlbums().catchError((_) => <DiscoverTip>[]),
        api.discoverResurfaced().catchError((_) => <DiscoverTip>[]),
        api.laterList().catchError((_) => <Track>[]),
      ]);
      final rec = extra[0] as RecommendBundle;
      final recommend = RecommendBundle(
        tracks: rec.tracks.take(8).toList(),
        artists: rec.artists.take(4).toList(),
        albums: rec.albums.take(4).toList(),
        explanation: rec.explanation,
        empty: rec.empty,
      );
      final discoverNew = (extra[1] as List<DiscoverTip>).take(3).toList();
      final discoverOld = (extra[2] as List<DiscoverTip>).take(3).toList();
      final later = (extra[3] as List<Track>).take(6).toList();
      if (!ref.mounted || generation != _buildGeneration) return;
      state = AsyncData(
        HomeCatalog(
          mixes: base.mixes,
          artists: base.artists,
          albums: base.albums,
          favorites: base.favorites,
          recommend: recommend,
          discoverNew: discoverNew,
          discoverOld: discoverOld,
          later: later,
        ),
      );
    } catch (e) {
      if (!ref.mounted || generation != _buildGeneration) return;
      state = AsyncData(
        HomeCatalog(
          mixes: base.mixes,
          artists: base.artists,
          albums: base.albums,
          favorites: base.favorites,
          error: e.toString(),
        ),
      );
    }
  }
}

final homeCatalogProvider =
    AsyncNotifierProvider<HomeCatalogNotifier, HomeCatalog>(
      HomeCatalogNotifier.new,
    );

class LibraryCatalog {
  const LibraryCatalog({
    required this.artists,
    required this.albums,
    required this.tracks,
    this.favorites = const FavoritesBundle(),
    this.later = const [],
  });

  final List<ArtistCard> artists;
  final List<AlbumCard> albums;
  final List<Track> tracks;
  final FavoritesBundle favorites;
  final List<Track> later;
}

T _requireApi<T>(MusikApi? api, T Function(MusikApi api) read) {
  if (api == null) throw Exception('API не готов');
  return read(api);
}

void _keepAliveBriefly(Ref ref) {
  final link = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 2), link.close);
  ref.onDispose(timer.cancel);
}

final libraryTracksProvider = FutureProvider.autoDispose<List<Track>>((ref) {
  _keepAliveBriefly(ref);
  return _requireApi(ref.watch(musikApiProvider), (api) => api.library());
});

final libraryArtistsProvider = FutureProvider.autoDispose<List<ArtistCard>>((
  ref,
) {
  _keepAliveBriefly(ref);
  return _requireApi(ref.watch(musikApiProvider), (api) => api.artists());
});

final libraryAlbumsProvider = FutureProvider.autoDispose<List<AlbumCard>>((
  ref,
) {
  _keepAliveBriefly(ref);
  return _requireApi(ref.watch(musikApiProvider), (api) => api.albums());
});

final favoritesBundleProvider = FutureProvider.autoDispose<FavoritesBundle>((
  ref,
) {
  final api = ref.watch(musikApiProvider);
  if (api == null) throw Exception('API не готов');
  return api.favoritesBundle().catchError((_) => const FavoritesBundle());
});

final laterTracksProvider = FutureProvider.autoDispose<List<Track>>((ref) {
  final api = ref.watch(musikApiProvider);
  if (api == null) throw Exception('API не готов');
  return api.laterList().catchError((_) => <Track>[]);
});

final libraryCatalogProvider = FutureProvider.autoDispose<LibraryCatalog>((
  ref,
) async {
  final results = await Future.wait([
    ref.watch(libraryArtistsProvider.future),
    ref.watch(libraryAlbumsProvider.future),
    ref.watch(libraryTracksProvider.future),
    ref.watch(favoritesBundleProvider.future),
    ref.watch(laterTracksProvider.future),
  ]);
  return LibraryCatalog(
    artists: results[0] as List<ArtistCard>,
    albums: results[1] as List<AlbumCard>,
    tracks: results[2] as List<Track>,
    favorites: results[3] as FavoritesBundle,
    later: results[4] as List<Track>,
  );
});

final trackLyricsProvider = FutureProvider.autoDispose
    .family<TrackLyrics?, int>((ref, trackId) async {
      final api = ref.watch(musikApiProvider);
      if (api == null || trackId <= 0) return null;
      try {
        return await api.trackLyrics(trackId);
      } catch (_) {
        return null;
      }
    });

class RelatedBundle {
  const RelatedBundle({
    this.tracks = const [],
    this.artists = const [],
    this.albums = const [],
  });

  final List<SimilarTrack> tracks;
  final List<ArtistCard> artists;
  final List<AlbumCard> albums;
}

final relatedForTrackProvider = FutureProvider.autoDispose
    .family<RelatedBundle, ({int id, String artist, String album})>((
      ref,
      key,
    ) async {
      final api = ref.watch(musikApiProvider);
      if (api == null) return const RelatedBundle();
      try {
        final results = await Future.wait([
          api.similarTracks(key.id),
          key.artist.isNotEmpty
              ? api.similarArtists(key.artist)
              : Future.value(<ArtistCard>[]),
          key.album.isNotEmpty
              ? api.similarAlbums(artist: key.artist, album: key.album)
              : Future.value(<AlbumCard>[]),
        ]);
        return RelatedBundle(
          tracks: (results[0] as List<SimilarTrack>).take(8).toList(),
          artists: (results[1] as List<ArtistCard>).take(8).toList(),
          albums: (results[2] as List<AlbumCard>).take(8).toList(),
        );
      } catch (_) {
        return const RelatedBundle();
      }
    });

final artistDetailProvider = FutureProvider.autoDispose
    .family<ArtistDetail, String>((ref, artist) async {
      final api = ref.watch(musikApiProvider);
      if (api == null) throw Exception('API не готов');
      final library = await api.library(artist: artist);
      final tracks = library
          .where((t) => t.artist.toLowerCase() == artist.toLowerCase())
          .toList();
      final albums = <String, AlbumCard>{};
      for (final t in tracks) {
        final name = (t.album ?? '').trim();
        if (name.isEmpty) continue;
        final key = name.toLowerCase();
        final prev = albums[key];
        albums[key] = AlbumCard(
          artist: artist,
          album: name,
          tracks: (prev?.tracks ?? 0) + 1,
          coverTrackId: prev?.coverTrackId ?? t.id,
          artwork: prev?.artwork ?? t.artworkPath,
        );
      }
      List<ArtistCard> similar = const [];
      try {
        similar = await api.similarArtists(artist);
      } catch (_) {}
      return ArtistDetail(
        artist: artist,
        tracks: tracks,
        albums: albums.values.toList(),
        similar: similar.take(8).toList(),
      );
    });

class ArtistDetail {
  const ArtistDetail({
    required this.artist,
    required this.tracks,
    required this.albums,
    required this.similar,
  });

  final String artist;
  final List<Track> tracks;
  final List<AlbumCard> albums;
  final List<ArtistCard> similar;
}

final albumDetailProvider = FutureProvider.autoDispose
    .family<AlbumDetail, ({String artist, String album})>((ref, key) async {
      final api = ref.watch(musikApiProvider);
      if (api == null) throw Exception('API не готов');
      final library = await api.library(artist: key.artist, album: key.album);
      final tracks = library.where((t) {
        final sameArtist = t.artist.toLowerCase() == key.artist.toLowerCase();
        final sameAlbum =
            (t.album ?? '').toLowerCase() == key.album.toLowerCase();
        return sameArtist && sameAlbum;
      }).toList();
      List<AlbumCard> similar = const [];
      try {
        similar = await api.similarAlbums(artist: key.artist, album: key.album);
      } catch (_) {}
      return AlbumDetail(
        artist: key.artist,
        album: key.album,
        tracks: tracks,
        similar: similar.take(8).toList(),
      );
    });

class AlbumDetail {
  const AlbumDetail({
    required this.artist,
    required this.album,
    required this.tracks,
    required this.similar,
  });

  final String artist;
  final String album;
  final List<Track> tracks;
  final List<AlbumCard> similar;
}
