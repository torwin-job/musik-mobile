import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musik_app/data/api/musik_api.dart';
import 'package:musik_app/data/models/models.dart';
import 'package:musik_app/providers/catalog_providers.dart';
import 'package:musik_app/providers/providers.dart';

void main() {
  test('mix rebuild waits for job completion before catalog reload', () async {
    final api = _FakeMusikApi();
    final container = _container(api);
    addTearDown(container.dispose);
    final subscription = container.listen(homeCatalogProvider, (_, _) {});
    addTearDown(subscription.close);

    await container.read(homeCatalogProvider.future);
    expect(api.mixReads, 1);

    final rebuild = container.read(catalogActionsProvider).rebuildMixes();
    await _waitUntil(() => api.trace.contains('wait:start:41'));

    expect(api.mixReads, 1);
    expect(
      api.trace,
      containsAllInOrder(['enqueue:mix_pack', 'wait:start:41']),
    );

    api.jobDone.complete();
    await rebuild;

    expect(api.mixReads, 2);
    expect(
      api.trace,
      containsAllInOrder([
        'enqueue:mix_pack',
        'wait:start:41',
        'wait:done:41',
        'mixes:2',
      ]),
    );
  });

  test('favorite mutation refreshes recommendations', () async {
    final api = _FakeMusikApi();
    final container = _container(api);
    addTearDown(container.dispose);
    final subscription = container.listen(homeCatalogProvider, (_, _) {});
    addTearDown(subscription.close);

    await container.read(homeCatalogProvider.future);
    await _waitForRecommendation(container, 'recommend-0');

    await container.read(catalogActionsProvider).toggleFavorite({
      'type': 'artist',
      'artist': 'New favorite',
    });
    await container.read(homeCatalogProvider.future);
    await _waitForRecommendation(container, 'recommend-1');

    expect(api.favoriteBodies, [
      {'type': 'artist', 'artist': 'New favorite'},
    ]);
    expect(api.recommendReads, 2);
  });

  test('stale wave2 cannot overwrite state after invalidation', () async {
    final staleRecommendation = Completer<RecommendBundle>();
    final api = _FakeMusikApi(firstRecommendation: staleRecommendation);
    final container = _container(api);
    addTearDown(container.dispose);
    final subscription = container.listen(homeCatalogProvider, (_, _) {});
    addTearDown(subscription.close);

    await container.read(homeCatalogProvider.future);

    await container.read(catalogActionsProvider).toggleFavorite({
      'type': 'track',
      'track_id': 7,
    });
    await container.read(homeCatalogProvider.future);
    await _waitForRecommendation(container, 'recommend-1');

    staleRecommendation.complete(_recommendation('stale-recommendation'));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(
      container
          .read(homeCatalogProvider)
          .asData
          ?.value
          .recommend
          .tracks
          .single
          .title,
      'recommend-1',
    );
  });

  test('detail providers request only matching catalog tracks', () async {
    final api = _FakeMusikApi();
    final container = _container(api);
    addTearDown(container.dispose);

    final artist = await container.read(
      artistDetailProvider('Massive Attack').future,
    );
    final album = await container.read(
      albumDetailProvider((
        artist: 'Massive Attack',
        album: 'Mezzanine',
      )).future,
    );

    expect(artist.tracks, hasLength(1));
    expect(album.tracks, hasLength(1));
    expect(api.libraryFilters, [
      (artist: 'Massive Attack', album: null),
      (artist: 'Massive Attack', album: 'Mezzanine'),
    ]);
  });

  test('favorite refresh reuses cached library catalog slices', () async {
    final api = _FakeMusikApi();
    final container = _container(api);
    addTearDown(container.dispose);
    final subscription = container.listen(libraryCatalogProvider, (_, _) {});
    addTearDown(subscription.close);

    await container.read(libraryCatalogProvider.future);
    await container.read(catalogActionsProvider).toggleFavorite({
      'type': 'track',
      'track_id': 7,
    });
    await container.read(libraryCatalogProvider.future);

    expect(api.libraryReads, 1);
    expect(api.artistReads, 1);
    expect(api.albumReads, 1);
    expect(api.favoriteReads, 2);
  });
}

ProviderContainer _container(MusikApi api) {
  return ProviderContainer(
    overrides: [musikApiProvider.overrideWithValue(api)],
  );
}

Future<void> _waitForRecommendation(ProviderContainer container, String title) {
  return _waitUntil(() {
    final tracks = container
        .read(homeCatalogProvider)
        .asData
        ?.value
        .recommend
        .tracks;
    return tracks?.isNotEmpty == true && tracks!.single.title == title;
  });
}

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

RecommendBundle _recommendation(String title) {
  return RecommendBundle(
    tracks: [Track(id: 1, title: title, artist: 'Artist')],
  );
}

class _FakeMusikApi extends MusikApi {
  _FakeMusikApi({this.firstRecommendation})
    : super(baseUrl: 'http://localhost', tokenProvider: () async => null);

  final Completer<RecommendBundle>? firstRecommendation;
  final Completer<void> jobDone = Completer<void>();
  final List<String> trace = [];
  final List<Map<String, dynamic>> favoriteBodies = [];

  int mixReads = 0;
  int recommendReads = 0;
  int recommendationVersion = 0;
  int libraryReads = 0;
  int artistReads = 0;
  int albumReads = 0;
  int favoriteReads = 0;
  final List<({String? artist, String? album})> libraryFilters = [];

  @override
  Future<List<MixCard>> mixes() async {
    mixReads++;
    trace.add('mixes:$mixReads');
    return [MixCard(kind: 'daily', title: 'mix-$mixReads')];
  }

  @override
  Future<List<ArtistCard>> artists() async {
    artistReads++;
    return const [];
  }

  @override
  Future<List<AlbumCard>> albums() async {
    albumReads++;
    return const [];
  }

  @override
  Future<List<Track>> library({String? artist, String? album}) async {
    libraryReads++;
    libraryFilters.add((artist: artist, album: album));
    return const [
      Track(
        id: 7,
        title: 'Teardrop',
        artist: 'Massive Attack',
        album: 'Mezzanine',
      ),
    ];
  }

  @override
  Future<FavoritesBundle> favoritesBundle() async {
    favoriteReads++;
    return const FavoritesBundle();
  }

  @override
  Future<RecommendBundle> recommendFavorites() {
    recommendReads++;
    if (recommendReads == 1 && firstRecommendation != null) {
      return firstRecommendation!.future;
    }
    return Future.value(_recommendation('recommend-$recommendationVersion'));
  }

  @override
  Future<List<DiscoverTip>> discoverAlbums() async => const [];

  @override
  Future<List<DiscoverTip>> discoverResurfaced() async => const [];

  @override
  Future<List<ArtistCard>> similarArtists(String artist) async => const [];

  @override
  Future<List<AlbumCard>> similarAlbums({
    required String artist,
    required String album,
  }) async => const [];

  @override
  Future<List<Track>> laterList() async => const [];

  @override
  Future<Map<String, dynamic>> enqueueJob(String kind) async {
    trace.add('enqueue:$kind');
    return {'id': 41};
  }

  @override
  Future<Map<String, dynamic>> waitForJob(
    int id, {
    Duration timeout = const Duration(minutes: 3),
    Duration pollInterval = const Duration(seconds: 2),
  }) async {
    trace.add('wait:start:$id');
    await jobDone.future;
    trace.add('wait:done:$id');
    return {'id': id, 'status': 'done'};
  }

  @override
  Future<Map<String, dynamic>> favoritesToggle(
    Map<String, dynamic> body,
  ) async {
    favoriteBodies.add(Map<String, dynamic>.from(body));
    recommendationVersion++;
    return {'ok': true};
  }
}
