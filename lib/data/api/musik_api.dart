import 'package:dio/dio.dart';

import '../../core/errors.dart';
import '../models/models.dart';
import 'auth_interceptor.dart';

class MusikApi {
  MusikApi({
    required String baseUrl,
    required Future<String?> Function() tokenProvider,
    void Function()? onUnauthorized,
  }) : _dio = Dio(
         BaseOptions(
           baseUrl: _normalizeBase(baseUrl),
           connectTimeout: const Duration(seconds: 12),
           receiveTimeout: const Duration(seconds: 60),
           headers: {'Accept': 'application/json'},
         ),
       ),
       _tokenProvider = tokenProvider {
    _dio.interceptors.add(
      AuthInterceptor(
        tokenProvider: tokenProvider,
        onUnauthorized: onUnauthorized,
      ),
    );
  }

  final Dio _dio;
  final Future<String?> Function() _tokenProvider;

  String get baseUrl => _dio.options.baseUrl;

  static String _normalizeBase(String url) {
    var u = url.trim();
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    return u;
  }

  void updateBaseUrl(String baseUrl) {
    _dio.options.baseUrl = _normalizeBase(baseUrl);
  }

  Future<String?> getToken() => _tokenProvider();

  String absoluteUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    final p = path.startsWith('/') ? path : '/$path';
    return '$baseUrl$p';
  }

  // —— auth / meta ——
  Future<Map<String, dynamic>> health() => _getMap('/api/health');
  Future<Map<String, dynamic>> authMe() => _getMap('/api/auth/me');
  Future<Map<String, dynamic>> login(String password) =>
      _postMap('/api/auth/login', data: {'password': password});
  Future<void> logout() async {
    await _dio.post('/api/auth/logout');
  }

  Future<Map<String, dynamic>> profile() => _getMap('/api/profile');
  Future<Map<String, dynamic>> metricsWeekly() =>
      _getMap('/api/metrics/weekly');

  // —— catalog ——
  Future<List<Track>> library({String? artist, String? album}) async {
    final data = await _getDynamic(
      '/api/library',
      query: {
        if (artist != null && artist.trim().isNotEmpty) 'artist': artist.trim(),
        if (album != null && album.trim().isNotEmpty) 'album': album.trim(),
      },
    );
    final list = data is List ? data : (data is Map ? data['tracks'] : null);
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => Track.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<ArtistCard>> artists() async {
    final m = await _getMap('/api/artists');
    final list = m['artists'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => ArtistCard.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<AlbumCard>> albums() async {
    final m = await _getMap('/api/albums');
    final list = m['albums'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => AlbumCard.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<Track> track(int id) async {
    final m = await _getMap('/api/tracks/$id');
    return Track.fromJson(m);
  }

  Future<List<MixCard>> mixes() async {
    final m = await _getMap('/api/mixes');
    final list = m['mixes'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => MixCard.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<Map<String, dynamic>> favorites() => _getMap('/api/favorites');

  Future<FavoritesBundle> favoritesBundle() async {
    final m = await favorites();
    return FavoritesBundle.fromJson(m);
  }

  Future<Map<String, dynamic>> favoritesToggle(Map<String, dynamic> body) =>
      _postMap('/api/favorites/toggle', data: body);

  Future<Map<String, dynamic>> favoritesStatus({
    int? trackId,
    String? artist,
    String? album,
  }) => _getMap(
    '/api/favorites/status',
    query: {
      'track_id': ?trackId,
      if (artist != null && artist.isNotEmpty) 'artist': artist,
      if (album != null && album.isNotEmpty) 'album': album,
    },
  );

  Future<RecommendBundle> recommendFavorites() async {
    final m = await _getMap('/api/recommend/favorites');
    return RecommendBundle.fromJson(m);
  }

  Future<Map<String, dynamic>> recommendSeed({
    required String type,
    int? trackId,
    String? artist,
    String? album,
  }) => _getMap(
    '/api/recommend/seed',
    query: {
      'type': type,
      'track_id': ?trackId,
      'artist': ?artist,
      'album': ?album,
    },
  );

  Future<List<DiscoverTip>> discoverAlbums() async {
    final m = await _getMap('/api/discover/albums');
    return _tips(m);
  }

  Future<List<DiscoverTip>> discoverResurfaced() async {
    final m = await _getMap('/api/discover/resurfaced');
    return _tips(m);
  }

  List<DiscoverTip> _tips(Map<String, dynamic> m) {
    final list = m['tips'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => DiscoverTip.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<TrackLyrics> trackLyrics(int id) async {
    final m = await _getMap('/api/tracks/$id/lyrics');
    return TrackLyrics.fromJson(m);
  }

  Future<List<SimilarTrack>> similarTracks(int id) async {
    final data = await _getDynamic('/api/similar/$id');
    if (data is! List) return [];
    return data
        .whereType<Map>()
        .map((e) => SimilarTrack.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<ArtistCard>> similarArtists(String artist) async {
    final m = await _getMap('/api/similar/artists', query: {'artist': artist});
    final list = m['artists'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => ArtistCard.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<AlbumCard>> similarAlbums({
    required String artist,
    required String album,
  }) async {
    final m = await _getMap(
      '/api/similar/albums',
      query: {'artist': artist, 'album': album},
    );
    final list = m['albums'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => AlbumCard.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<Track>> laterList() async {
    final m = await _getMap('/api/later');
    final list = m['tracks'] ?? m['items'] ?? m['later'];
    if (list is! List) return [];
    final out = <Track>[];
    for (final row in list) {
      if (row is! Map) continue;
      final map = Map<String, dynamic>.from(row);
      // API puts full track under "stream" (legacy) or "track".
      final nested = map['track'] ?? map['stream'];
      if (nested is Map) {
        out.add(Track.fromJson(Map<String, dynamic>.from(nested)));
      } else {
        out.add(
          Track(
            id:
                (map['track_id'] as num?)?.toInt() ??
                (map['id'] as num?)?.toInt() ??
                int.tryParse('${map['track_id'] ?? map['id']}') ??
                0,
            title: (map['title'] ?? '').toString(),
            artist: (map['artist'] ?? '').toString(),
            duration: (map['duration'] as num?)?.toDouble(),
          ),
        );
      }
    }
    return out;
  }

  Future<void> laterRemove(int trackId) async {
    await _dio.delete('/api/later', data: {'track_id': trackId});
  }

  // —— playback ——
  Future<Map<String, dynamic>> radioStart({int? seed}) =>
      _postMap('/api/radio/start', data: {'seed_track_id': ?seed});

  Future<Map<String, dynamic>> play(Map<String, dynamic> body) =>
      _postMap('/api/play', data: body);

  Future<Map<String, dynamic>> mixPlay(String kind) =>
      _postMap('/api/mixes/$kind/play', data: {});

  Future<Map<String, dynamic>> sessionJump({
    required String sessionId,
    required int index,
  }) => _postMap(
    '/api/session/jump',
    data: {'session_id': sessionId, 'index': index},
  );

  Future<Map<String, dynamic>> now(String sessionId) =>
      _getMap('/api/now', query: {'session_id': sessionId});

  Future<Map<String, dynamic>> events(Map<String, dynamic> body) =>
      _postMap('/api/events', data: body);

  Future<Map<String, dynamic>> laterAdd(int trackId) =>
      _postMap('/api/later', data: {'track_id': trackId});

  // —— jobs / share ——
  Future<Map<String, dynamic>> enqueueJob(String kind) =>
      _postMap('/api/jobs/$kind', data: {});

  Future<Map<String, dynamic>> getJob(int id) => _getMap('/api/jobs/$id');

  Future<Map<String, dynamic>> waitForJob(
    int id, {
    Duration timeout = const Duration(minutes: 3),
    Duration pollInterval = const Duration(seconds: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final job = await getJob(id);
      final status = job['status']?.toString();
      if (status == 'done') return job;
      if (status == 'failed') {
        throw Exception(job['error']?.toString() ?? 'Job $id failed');
      }
      await Future<void>.delayed(pollInterval);
    }
    throw Exception('Job $id did not finish in ${timeout.inSeconds}s');
  }

  Future<Map<String, dynamic>> shareCreate() =>
      _postMap('/api/share/radio', data: {});

  Future<Map<String, dynamic>> shareList() => _getMap('/api/share/radio');

  Future<void> shareRevoke(String token) async {
    await _dio.delete('/api/share/radio/$token');
  }

  // —— helpers ——
  Future<Map<String, dynamic>> _getMap(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    try {
      final res = await _dio.get<dynamic>(path, queryParameters: query);
      return _asMap(res.data);
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }

  Future<dynamic> _getDynamic(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    try {
      final res = await _dio.get<dynamic>(path, queryParameters: query);
      return res.data;
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }

  Future<Map<String, dynamic>> _postMap(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    try {
      final res = await _dio.post<dynamic>(path, data: data);
      return _asMap(res.data);
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw ApiException('unexpected response');
  }
}
