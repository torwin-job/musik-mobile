class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    this.duration,
    this.artwork,
    this.stream,
    this.clusterId,
  });

  final int id;
  final String title;
  final String artist;
  final String? album;
  final double? duration;
  final String? artwork;
  final String? stream;
  final int? clusterId;

  factory Track.fromJson(Map<String, dynamic> j) {
    return Track(
      id: _asInt(j['id']) ?? 0,
      title: (j['title'] ?? '').toString(),
      artist: (j['artist'] ?? '').toString(),
      album: j['album']?.toString(),
      duration: _asDouble(j['duration']),
      artwork: j['artwork']?.toString(),
      stream: j['stream']?.toString(),
      clusterId: _asInt(j['cluster_id']),
    );
  }

  String get streamPath => stream ?? '/api/stream/$id';
  String get artworkPath => artwork ?? '/api/artwork/$id';

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    if (album != null) 'album': album,
    if (duration != null) 'duration': duration,
    if (artwork != null) 'artwork': artwork,
    if (stream != null) 'stream': stream,
  };
}

class QueueItem {
  const QueueItem({
    required this.trackId,
    required this.title,
    required this.artist,
    this.album,
    this.explanation,
  });

  final int trackId;
  final String title;
  final String artist;
  final String? album;
  final String? explanation;

  factory QueueItem.fromJson(Map<String, dynamic> j) {
    return QueueItem(
      trackId: _asInt(j['track_id'] ?? j['id']) ?? 0,
      title: (j['title'] ?? '').toString(),
      artist: (j['artist'] ?? '').toString(),
      album: j['album']?.toString(),
      explanation: j['explanation']?.toString(),
    );
  }

  Track toTrack() =>
      Track(id: trackId, title: title, artist: artist, album: album);
}

class MixCard {
  const MixCard({
    required this.kind,
    required this.title,
    this.subtitle,
    this.tracks = 0,
    this.ready = false,
    this.highlight = false,
    this.today = false,
    this.coverTrackId,
    this.special,
    this.playlistId,
  });

  final String kind;
  final String title;
  final String? subtitle;
  final int tracks;
  final bool ready;
  final bool highlight;
  final bool today;
  final int? coverTrackId;
  final String? special;
  final int? playlistId;

  factory MixCard.fromJson(Map<String, dynamic> j) {
    return MixCard(
      kind: (j['kind'] ?? '').toString(),
      title: (j['title'] ?? j['name'] ?? j['kind'] ?? '').toString(),
      subtitle: j['subtitle']?.toString(),
      tracks: _asInt(j['tracks']) ?? 0,
      ready: j['ready'] == true,
      highlight: j['highlight'] == true,
      today: j['today'] == true,
      coverTrackId: _asInt(j['cover_track_id']),
      special: j['special']?.toString(),
      playlistId: _asInt(j['playlist_id']),
    );
  }
}

class ArtistCard {
  const ArtistCard({
    required this.artist,
    required this.tracks,
    this.coverTrackId,
    this.artwork,
    this.explanation,
  });

  final String artist;
  final int tracks;
  final int? coverTrackId;
  final String? artwork;
  final String? explanation;

  factory ArtistCard.fromJson(Map<String, dynamic> j) {
    return ArtistCard(
      artist: (j['artist'] ?? '').toString(),
      tracks: _asInt(j['tracks']) ?? 0,
      coverTrackId: _asInt(j['cover_track_id']),
      artwork: j['artwork']?.toString(),
      explanation: j['explanation']?.toString(),
    );
  }
}

class AlbumCard {
  const AlbumCard({
    required this.artist,
    required this.album,
    required this.tracks,
    this.coverTrackId,
    this.artwork,
    this.explanation,
  });

  final String artist;
  final String album;
  final int tracks;
  final int? coverTrackId;
  final String? artwork;
  final String? explanation;

  factory AlbumCard.fromJson(Map<String, dynamic> j) {
    return AlbumCard(
      artist: (j['artist'] ?? '').toString(),
      album: (j['album'] ?? '').toString(),
      tracks: _asInt(j['tracks']) ?? 0,
      coverTrackId: _asInt(j['cover_track_id']),
      artwork: j['artwork']?.toString(),
      explanation: j['explanation']?.toString(),
    );
  }
}

class TrackLyrics {
  const TrackLyrics({
    required this.trackId,
    required this.status,
    this.plainLyrics = '',
    this.syncedLyrics = '',
    this.instrumental = false,
    this.source,
    this.error,
  });

  final int trackId;
  final String status;
  final String plainLyrics;
  final String syncedLyrics;
  final bool instrumental;
  final String? source;
  final String? error;

  factory TrackLyrics.fromJson(Map<String, dynamic> j) {
    return TrackLyrics(
      trackId: _asInt(j['track_id']) ?? 0,
      status: (j['status'] ?? '').toString(),
      plainLyrics: (j['plain_lyrics'] ?? '').toString(),
      syncedLyrics: (j['synced_lyrics'] ?? '').toString(),
      instrumental: j['instrumental'] == true,
      source: j['source']?.toString(),
      error: j['error']?.toString(),
    );
  }

  bool get isAbsent =>
      status == 'absent' || status == 'missing' || status.isEmpty;

  String get displayText {
    if (instrumental) return '(instrumental)';
    if (isAbsent) return 'Текста нет';
    final plain = plainLyrics.trim();
    if (plain.isNotEmpty) return plain;
    final synced = syncedLyrics.trim();
    if (synced.isNotEmpty) {
      // Strip [mm:ss.xx] timestamps for plain reading.
      return synced
          .split('\n')
          .map(
            (line) => line.replaceFirst(RegExp(r'^\[\d+:\d+[.\d]*\]\s*'), ''),
          )
          .join('\n')
          .trim();
    }
    return '—';
  }
}

class SimilarTrack {
  const SimilarTrack({
    required this.id,
    required this.artist,
    required this.title,
    this.cosine,
  });

  final int id;
  final String artist;
  final String title;
  final double? cosine;

  factory SimilarTrack.fromJson(Map<String, dynamic> j) {
    return SimilarTrack(
      id: _asInt(j['id']) ?? 0,
      artist: (j['artist'] ?? '').toString(),
      title: (j['title'] ?? '').toString(),
      cosine: _asDouble(j['cosine']),
    );
  }

  Track toTrack() => Track(id: id, title: title, artist: artist);
}

class FavoritesBundle {
  const FavoritesBundle({
    this.tracks = const [],
    this.artists = const [],
    this.albums = const [],
    this.ids = const [],
    this.trackCount = 0,
    this.artistCount = 0,
    this.albumCount = 0,
  });

  final List<Track> tracks;
  final List<ArtistCard> artists;
  final List<AlbumCard> albums;
  final List<int> ids;
  final int trackCount;
  final int artistCount;
  final int albumCount;

  factory FavoritesBundle.fromJson(Map<String, dynamic> j) {
    final tracks = <Track>[];
    final rawTracks = j['tracks'];
    if (rawTracks is List) {
      for (final row in rawTracks) {
        if (row is! Map) continue;
        final m = Map<String, dynamic>.from(row);
        final nested = m['track'];
        if (nested is Map) {
          tracks.add(Track.fromJson(Map<String, dynamic>.from(nested)));
        } else {
          tracks.add(
            Track(
              id: _asInt(m['track_id'] ?? m['id']) ?? 0,
              title: (m['title'] ?? '').toString(),
              artist: (m['artist'] ?? '').toString(),
              duration: _asDouble(m['duration']),
            ),
          );
        }
      }
    }

    final artists = <ArtistCard>[];
    final rawArtists = j['artists'];
    if (rawArtists is List) {
      for (final row in rawArtists) {
        if (row is Map) {
          artists.add(ArtistCard.fromJson(Map<String, dynamic>.from(row)));
        }
      }
    }

    final albums = <AlbumCard>[];
    final rawAlbums = j['albums'];
    if (rawAlbums is List) {
      for (final row in rawAlbums) {
        if (row is Map) {
          albums.add(AlbumCard.fromJson(Map<String, dynamic>.from(row)));
        }
      }
    }

    final ids = <int>[];
    final rawIds = j['ids'];
    if (rawIds is List) {
      for (final id in rawIds) {
        final n = _asInt(id);
        if (n != null) ids.add(n);
      }
    }

    final counts = j['counts'];
    final c = counts is Map ? Map<String, dynamic>.from(counts) : const {};

    return FavoritesBundle(
      tracks: tracks,
      artists: artists,
      albums: albums,
      ids: ids,
      trackCount: _asInt(c['tracks']) ?? _asInt(j['count']) ?? tracks.length,
      artistCount: _asInt(c['artists']) ?? artists.length,
      albumCount: _asInt(c['albums']) ?? albums.length,
    );
  }
}

class RecommendBundle {
  const RecommendBundle({
    this.tracks = const [],
    this.artists = const [],
    this.albums = const [],
    this.explanation,
    this.empty = false,
  });

  final List<Track> tracks;
  final List<ArtistCard> artists;
  final List<AlbumCard> albums;
  final String? explanation;
  final bool empty;

  factory RecommendBundle.fromJson(Map<String, dynamic> j) {
    final tracks = <Track>[];
    final rawTracks = j['tracks'];
    if (rawTracks is List) {
      for (final row in rawTracks) {
        if (row is Map) {
          tracks.add(Track.fromJson(Map<String, dynamic>.from(row)));
        }
      }
    }
    final artists = <ArtistCard>[];
    final rawArtists = j['artists'];
    if (rawArtists is List) {
      for (final row in rawArtists) {
        if (row is Map) {
          artists.add(ArtistCard.fromJson(Map<String, dynamic>.from(row)));
        }
      }
    }
    final albums = <AlbumCard>[];
    final rawAlbums = j['albums'];
    if (rawAlbums is List) {
      for (final row in rawAlbums) {
        if (row is Map) {
          albums.add(AlbumCard.fromJson(Map<String, dynamic>.from(row)));
        }
      }
    }
    return RecommendBundle(
      tracks: tracks,
      artists: artists,
      albums: albums,
      explanation: j['explanation']?.toString(),
      empty:
          j['empty'] == true ||
          (tracks.isEmpty && artists.isEmpty && albums.isEmpty),
    );
  }
}

class DiscoverTip {
  const DiscoverTip({
    required this.artist,
    required this.album,
    this.explanation,
    this.trackIds = const [],
  });

  final String artist;
  final String album;
  final String? explanation;
  final List<int> trackIds;

  factory DiscoverTip.fromJson(Map<String, dynamic> j) {
    final ids = <int>[];
    final raw = j['track_ids'];
    if (raw is List) {
      for (final id in raw) {
        final n = _asInt(id);
        if (n != null) ids.add(n);
      }
    }
    return DiscoverTip(
      artist: (j['artist'] ?? '').toString(),
      album: (j['album'] ?? '').toString(),
      explanation: j['explanation']?.toString(),
      trackIds: ids,
    );
  }
}

int? _asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

double? _asDouble(dynamic v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}
