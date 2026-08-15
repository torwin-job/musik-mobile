import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/errors.dart';
import '../../data/api/musik_api.dart';
import '../../data/models/models.dart';
import '../../data/repositories/settings_repository.dart';
import '../../providers/catalog_providers.dart';
import '../../providers/providers.dart';
import '../../services/musik_audio_handler.dart';
import '../../widgets/auth_art_provider.dart';

enum ListenRating { like, dislike }

/// High-frequency scrubber clock — separate from session state to avoid
/// rebuilding the whole shell on every position tick.
class PlaybackProgress {
  const PlaybackProgress({
    this.position = Duration.zero,
    this.duration = Duration.zero,
  });

  final Duration position;
  final Duration duration;

  double get fraction {
    if (duration.inMilliseconds <= 0) return 0;
    return (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  @override
  bool operator ==(Object other) =>
      other is PlaybackProgress &&
      other.position == position &&
      other.duration == duration;

  @override
  int get hashCode => Object.hash(position, duration);
}

class PlaybackProgressController extends Notifier<PlaybackProgress> {
  @override
  PlaybackProgress build() => const PlaybackProgress();

  void update({Duration? position, Duration? duration}) {
    final next = PlaybackProgress(
      position: position ?? state.position,
      duration: duration ?? state.duration,
    );
    if (next == state) return;
    state = next;
  }

  void reset() => state = const PlaybackProgress();
}

final playbackProgressProvider =
    NotifierProvider<PlaybackProgressController, PlaybackProgress>(
      PlaybackProgressController.new,
    );

class PlaybackState {
  const PlaybackState({
    this.sessionId,
    this.mode,
    this.maturity,
    this.name,
    this.fixed = false,
    this.current,
    this.playlist = const [],
    this.queue = const [],
    this.index = 0,
    this.playing = false,
    this.loading = false,
    this.rating,
    this.error,
    this.ended = false,
  });

  final String? sessionId;
  final String? mode;
  final String? maturity;
  final String? name;
  final bool fixed;
  final Track? current;
  final List<Track> playlist;
  final List<QueueItem> queue;
  final int index;
  final bool playing;
  final bool loading;
  final ListenRating? rating;
  final String? error;
  final bool ended;

  bool get hasTrack => current != null;

  PlaybackState copyWith({
    String? sessionId,
    String? mode,
    String? maturity,
    String? name,
    bool? fixed,
    Track? current,
    List<Track>? playlist,
    List<QueueItem>? queue,
    int? index,
    bool? playing,
    bool? loading,
    ListenRating? rating,
    String? error,
    bool? ended,
    bool clearError = false,
    bool clearRating = false,
    bool clearCurrent = false,
    bool clearName = false,
  }) {
    return PlaybackState(
      sessionId: sessionId ?? this.sessionId,
      mode: mode ?? this.mode,
      maturity: maturity ?? this.maturity,
      name: clearName ? name : (name ?? this.name),
      fixed: fixed ?? this.fixed,
      current: clearCurrent ? null : (current ?? this.current),
      playlist: playlist ?? this.playlist,
      queue: queue ?? this.queue,
      index: index ?? this.index,
      playing: playing ?? this.playing,
      loading: loading ?? this.loading,
      rating: clearRating ? null : (rating ?? this.rating),
      error: clearError ? null : (error ?? this.error),
      ended: ended ?? this.ended,
    );
  }
}

class PlaybackController extends Notifier<PlaybackState> {
  AudioPlayer? _player;
  MusikAudioHandler? _audio;
  Timer? _progressTimer;
  Timer? _prefetchTimer;
  StreamSubscription<PlayerState>? _playerSub;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  double _listenedSec = 0;
  DateTime? _listenStarted;
  DateTime? _lastPosEmit;
  bool _advancing = false;
  bool _ownsPlayer = true;
  int _startGen = 0;
  bool _transportBusy = false;
  int? _loadedTrackId;
  final _playingOut = StreamController<bool>.broadcast(sync: true);

  /// Live playing flag from ExoPlayer — use this for play/pause icons.
  Stream<bool> playingChanges() async* {
    yield _livePlayer?.playing ?? state.playing;
    yield* _playingOut.stream;
  }

  void _setPlaying(bool playing) {
    if (!_playingOut.isClosed) _playingOut.add(playing);
    if (state.playing != playing) {
      state = state.copyWith(playing: playing);
    }
  }

  MusikApi get _api {
    final api = ref.read(musikApiProvider);
    if (api == null) throw ApiException('API не готов');
    return api;
  }

  SettingsRepository? get _settingsOrNull {
    return ref.read(settingsRepositoryProvider).asData?.value;
  }

  @override
  PlaybackState build() {
    ref.onDispose(_disposePlayer);
    return const PlaybackState();
  }

  AudioPlayer? get _livePlayer {
    if (_audio != null) return _audio!.player;
    return _player;
  }

  Future<AudioPlayer> _ensurePlayer() async {
    if (_player != null) {
      // Dual-player skip may swap the active instance under audio_service.
      if (_audio != null) _player = _audio!.player;
      return _player!;
    }
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    final handler = musikAudioHandler;
    late final AudioPlayer player;
    if (handler != null) {
      _audio = handler;
      _ownsPlayer = false;
      player = handler.player;
      handler.onSkipNext = skip;
      handler.onCompleted = onCompleted;
      handler.onActivePlayerChanged = _rebindPlayerStreams;
    } else {
      _ownsPlayer = true;
      player = createMusikAudioPlayer();
    }
    _player = player;
    _bindPlayerStreams(player);
    return player;
  }

  /// Android uses server mobile AAC/MP3 profile (`?q=mobile`).
  String _streamUrlFor(Track track) {
    final abs = _api.absoluteUrl(track.streamPath);
    if (!Platform.isAndroid) return abs;
    final u = Uri.parse(abs);
    final q = Map<String, String>.from(u.queryParameters);
    q['q'] = 'mobile';
    return u.replace(queryParameters: q).toString();
  }

  void _rebindPlayerStreams() {
    final p = _audio?.player;
    if (p == null) return;
    _player = p;
    _bindPlayerStreams(p);
  }

  void _bindPlayerStreams(AudioPlayer player) {
    _playerSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _playerSub = player.playerStateStream.listen((ps) async {
      _setPlaying(ps.playing);
      if (_audio == null && ps.processingState == ProcessingState.completed) {
        await onCompleted();
      }
    });
    _posSub = player.positionStream.listen((p) {
      final now = DateTime.now();
      // Only the isolated scrubber watches this provider, so a shorter interval
      // keeps progress fluid without rebuilding the full player screen.
      if (_lastPosEmit != null &&
          now.difference(_lastPosEmit!) < const Duration(milliseconds: 500)) {
        return;
      }
      _lastPosEmit = now;
      ref.read(playbackProgressProvider.notifier).update(position: p);
    });
    _durSub = player.durationStream.listen((d) {
      if (d != null) {
        ref.read(playbackProgressProvider.notifier).update(duration: d);
      }
    });
  }

  void _disposePlayer() {
    _progressTimer?.cancel();
    _prefetchTimer?.cancel();
    _playerSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    if (_audio != null) {
      _audio!.onSkipNext = null;
      _audio!.onCompleted = null;
      _audio!.onActivePlayerChanged = null;
      unawaited(_audio!.clearStandby());
    }
    if (_ownsPlayer) {
      _player?.dispose();
    }
    _player = null;
    _audio = null;
    _loadedTrackId = null;
  }

  /// Prefetch after startup settles, while leaving only one standby player.
  void _schedulePrefetch() {
    _prefetchTimer?.cancel();
    _prefetchTimer = Timer(const Duration(seconds: 10), () {
      if (!state.playing) return;
      unawaited(_prefetchNext());
    });
  }

  Future<void> _prefetchNext() async {
    final handler = _audio;
    if (handler == null) return;
    if (!state.playing) return;
    if (state.queue.isEmpty) return;
    final next = state.queue.first.toTrack();
    if (next.id <= 0 || next.id == state.current?.id) return;
    try {
      final token = await _api.getToken();
      final url = _streamUrlFor(next);
      final headers = <String, String>{
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };
      unawaited(
        handler.prefetchTrack(track: next, streamUrl: url, headers: headers),
      );
    } catch (_) {}
  }

  Future<void> startRadio({int? seed}) async {
    await _runStart(() => _api.radioStart(seed: seed));
  }

  Future<void> playMix(String kind) async {
    await _runStart(() => _api.mixPlay(kind));
  }

  Future<void> playBody(Map<String, dynamic> body) async {
    await _runStart(() => _api.play(body));
  }

  Future<void> playTrack(int trackId) => playBody({
    'track_ids': [trackId],
  });

  Future<void> playArtist(String artist) => playBody({'artist': artist});

  Future<void> playAlbum(String artist, String album) =>
      playBody({'artist': artist, 'album': album});

  Future<void> playSimilarTo(Track track) async {
    final similar = await _api.similarTracks(track.id);
    final ids = similar.map((t) => t.id).where((id) => id > 0).toList();
    if (ids.isNotEmpty) {
      await playBody({'track_ids': ids, 'name': 'Похоже на «${track.title}»'});
      return;
    }
    if (track.artist.isNotEmpty) {
      final arts = await _api.similarArtists(track.artist);
      if (arts.isNotEmpty) {
        await playArtist(arts.first.artist);
        return;
      }
    }
    if (track.album != null && track.album!.isNotEmpty) {
      final albs = await _api.similarAlbums(
        artist: track.artist,
        album: track.album!,
      );
      if (albs.isNotEmpty) {
        await playAlbum(albs.first.artist, albs.first.album);
        return;
      }
    }
    throw Exception('Мало похожего в библиотеке');
  }

  Future<void> _runStart(Future<Map<String, dynamic>> Function() start) async {
    final gen = ++_startGen;
    state = state.copyWith(loading: true, clearError: true, ended: false);
    await _pauseForSwitch();
    if (gen != _startGen) return;
    try {
      final res = await start().timeout(const Duration(seconds: 25));
      if (gen != _startGen) return;
      await _applySession(res, play: true, startGen: gen);
    } catch (e) {
      if (gen != _startGen) return;
      state = state.copyWith(loading: false, error: e.toString());
      rethrow;
    } finally {
      // Never leave the home radio spinner spinning forever.
      if (gen == _startGen && state.loading) {
        state = state.copyWith(loading: false);
      }
    }
  }

  /// Pause current audio without tearing down AudioService.
  Future<void> _pauseForSwitch() async {
    _progressTimer?.cancel();
    try {
      if (_audio != null) {
        await _audio!.softStop().timeout(const Duration(milliseconds: 800));
      } else if (_livePlayer != null) {
        unawaited(_livePlayer!.pause());
        try {
          await _livePlayer!
              .seek(Duration.zero)
              .timeout(const Duration(milliseconds: 500));
        } catch (_) {}
      }
    } catch (_) {}
    state = state.copyWith(playing: false);
    _setPlaying(false);
  }

  Future<void> restore(String sessionId) async {
    final res = await _api.now(sessionId);
    await _applySession(res, play: false);
  }

  Future<void> _applySession(
    Map<String, dynamic> res, {
    required bool play,
    int? startGen,
  }) async {
    final sessionId = res['session_id']?.toString();
    final currentMap = res['current'];
    Track? current;
    if (currentMap is Map) {
      current = Track.fromJson(Map<String, dynamic>.from(currentMap));
    } else if (res['next'] is Map) {
      current = Track.fromJson(Map<String, dynamic>.from(res['next'] as Map));
    }

    final tracksRaw = res['tracks'];
    final playlist = <Track>[];
    if (tracksRaw is List) {
      for (final t in tracksRaw) {
        if (t is Map) {
          playlist.add(Track.fromJson(Map<String, dynamic>.from(t)));
        }
      }
    }

    final queueRaw = res['queue'];
    final queue = <QueueItem>[];
    if (queueRaw is List) {
      for (final q in queueRaw) {
        if (q is Map) {
          queue.add(QueueItem.fromJson(Map<String, dynamic>.from(q)));
        }
      }
    }

    final mode = res['mode']?.toString();
    final fixed =
        res['fixed'] == true ||
        mode == 'playlist' ||
        mode == 'listen' ||
        mode == 'daily' ||
        mode == 'favorites' ||
        mode == 'later' ||
        playlist.length > 1;

    final rawName = res['name']?.toString() ?? res['kind']?.toString();
    final displayName =
        rawName ??
        (mode == 'radio'
            ? 'Радио'
            : (fixed && playlist.isNotEmpty ? 'Плейлист' : null));

    final settings = _settingsOrNull;
    if (sessionId != null) {
      await settings?.setSessionId(sessionId);
    }

    state = state.copyWith(
      sessionId: sessionId,
      mode: mode,
      maturity: res['maturity']?.toString(),
      name: displayName,
      clearName: true,
      fixed: fixed,
      current: current,
      clearCurrent: current == null,
      playlist: playlist,
      queue: queue,
      index: (res['index'] is num) ? (res['index'] as num).toInt() : 0,
      loading: false,
      ended: res['ended'] == true,
      clearRating: true,
      clearError: true,
    );

    if (current != null) {
      if (startGen != null && startGen != _startGen) return;
      // Always load the stream — restore used to only set UI metadata, so
      // play after app reopen did nothing (player had no AudioSource).
      await _loadAndPlay(current, startGen: startGen, autoplay: play);
    }
  }

  bool _sourceReadyFor(Track track) {
    if (_loadedTrackId != track.id) return false;
    final player = _livePlayer;
    if (player == null) return false;
    if (player.audioSource != null) return true;
    // audio_service path may keep mediaItem after process edges.
    final mid = _audio?.mediaItem.value?.id;
    return mid == '${track.id}' &&
        player.processingState != ProcessingState.idle;
  }

  Future<void> _loadAndPlay(
    Track track, {
    int? startGen,
    bool autoplay = true,
  }) async {
    await _ensurePlayer();
    if (startGen != null && startGen != _startGen) return;

    _progressTimer?.cancel();
    _listenedSec = 0;
    _listenStarted = autoplay ? DateTime.now() : null;
    _lastPosEmit = null;
    ref.read(playbackProgressProvider.notifier).reset();

    final token = await _api.getToken();
    final url = _streamUrlFor(track);
    final headers = <String, String>{
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };

    state = state.copyWith(current: track, loading: true, clearError: true);

    try {
      final handler = _audio;
      if (handler != null) {
        await handler
            .loadTrack(
              track: track,
              streamUrl: url,
              headers: headers,
              artUri: null,
            )
            .timeout(const Duration(seconds: 25));
      } else {
        final player = _player!;
        await player
            .setAudioSource(AudioSource.uri(Uri.parse(url), headers: headers))
            .timeout(const Duration(seconds: 25));
      }
      if (startGen != null && startGen != _startGen) return;
      // Prefetch swap may have changed the active player.
      if (handler != null) _player = handler.player;
      _loadedTrackId = track.id;

      final live = _livePlayer!;
      final dur = live.duration;
      if (dur != null) {
        ref.read(playbackProgressProvider.notifier).update(duration: dur);
      } else if (track.duration != null) {
        ref
            .read(playbackProgressProvider.notifier)
            .update(
              duration: Duration(
                milliseconds: (track.duration! * 1000).round(),
              ),
            );
      }

      if (!autoplay) {
        state = state.copyWith(loading: false, playing: false);
        _setPlaying(false);
      } else {
        // play() Future often never completes under audio_service on Android.
        if (handler != null) {
          unawaited(handler.play());
        } else {
          unawaited(live.play());
        }

        try {
          await live.playingStream
              .firstWhere((p) => p)
              .timeout(const Duration(seconds: 8));
        } catch (_) {
          // Still mark playing — ExoPlayer may already be audible.
        }

        state = state.copyWith(loading: false, playing: true);
        _setPlaying(true);
        unawaited(_sendEvent('track_start'));
        _startProgressTimer();
        _schedulePrefetch();
      }

      if (handler != null) {
        unawaited(() async {
          final artUri = await _artUriFor(track);
          if (startGen != null && startGen != _startGen) return;
          if (artUri == null) return;
          final item = handler.mediaItem.value;
          if (item == null || item.id != '${track.id}') return;
          handler.mediaItem.add(item.copyWith(artUri: artUri));
        }());
      }
    } catch (e) {
      if (startGen != null && startGen != _startGen) return;
      _loadedTrackId = null;
      state = state.copyWith(
        loading: false,
        playing: false,
        error: 'Не удалось воспроизвести: $e',
      );
    }
  }

  Future<void> togglePlay() async {
    if (_transportBusy) return;
    _transportBusy = true;
    try {
      await _ensurePlayer();
      final track = state.current;
      if (track == null) return;
      final player = _livePlayer!;
      final currentlyPlaying = player.playing;
      final want = !currentlyPlaying;

      // After cold start / restore, UI can show a track with no AudioSource.
      if (want && !_sourceReadyFor(track)) {
        _transportBusy = false;
        await _loadAndPlay(track, autoplay: true);
        return;
      }

      if (currentlyPlaying) {
        _accumulateListen();
        _listenStarted = null;
      } else {
        _listenStarted = DateTime.now();
      }

      // Flip UI immediately; never await hanging just_audio Futures.
      _setPlaying(want);
      if (_audio != null) {
        if (want) {
          unawaited(_audio!.play());
          _schedulePrefetch();
        } else {
          _prefetchTimer?.cancel();
          unawaited(_audio!.pause()); // also clears standby
        }
      } else {
        if (want) {
          unawaited(player.play());
          _schedulePrefetch();
        } else {
          _prefetchTimer?.cancel();
          unawaited(player.pause());
        }
      }

      try {
        await player.playingStream
            .firstWhere((p) => p == want)
            .timeout(const Duration(milliseconds: 1500));
      } catch (_) {
        // Keep optimistic UI — stream may already match.
      }
      _setPlaying(player.playing);
      // Clear prior TimeoutException banners.
      state = state.copyWith(clearError: true);
    } catch (e) {
      _setPlaying(_livePlayer?.playing ?? false);
      // Don't surface TimeoutException noise for pause/play.
      if (e is! TimeoutException) {
        state = state.copyWith(error: '$e');
      }
    } finally {
      _transportBusy = false;
    }
  }

  Future<Uri?> _artUriFor(Track track) async {
    try {
      final token = await _api.getToken();
      final artUrl = AuthArtImageProvider.thumbUrl(
        _api.absoluteUrl(track.artworkPath),
        256,
      );
      // Reuse shelf/player cache when the same thumb was already fetched.
      final bytes =
          AuthArtImageProvider.peekBytes(artUrl) ??
          await AuthArtImageProvider.fetchBytes(url: artUrl, token: token);
      if (bytes.isEmpty) {
        return Platform.isAndroid ? androidDefaultArtUri() : null;
      }
      return await cacheArtFile(track.id, bytes) ??
          (Platform.isAndroid ? androidDefaultArtUri() : null);
    } catch (_) {
      return Platform.isAndroid ? androidDefaultArtUri() : null;
    }
  }

  void _startProgressTimer() {
    _progressTimer?.cancel();
    var ticks = 0;
    // Lighter wakeups: accumulate every 10s, POST ~every 40s.
    _progressTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (!state.playing || state.current == null) return;
      _accumulateListen();
      ticks++;
      if (ticks % 4 != 0) return;
      try {
        await _sendEvent('progress');
      } catch (_) {}
    });
  }

  void _accumulateListen() {
    final now = DateTime.now();
    if (_listenStarted != null) {
      _listenedSec += now.difference(_listenStarted!).inMilliseconds / 1000.0;
      _listenStarted = now;
    }
  }

  Map<String, dynamic> _eventBody(String type, Track track, {String? reason}) {
    final sid = state.sessionId;
    if (sid == null) {
      throw ApiException('Нет активной сессии');
    }
    _accumulateListen();
    final tick = ref.read(playbackProgressProvider);
    final playerPos = _livePlayer?.position ?? tick.position;
    final playerDur = _livePlayer?.duration ?? tick.duration;
    final pos = playerPos.inMilliseconds / 1000.0;
    final dur = playerDur.inMilliseconds / 1000.0;
    return <String, dynamic>{
      'type': type,
      'session_id': sid,
      'track_id': track.id,
      'position_sec': pos,
      'duration_sec': dur > 0 ? dur : track.duration,
      'listened_sec': _listenedSec,
      'reason': ?reason,
    };
  }

  Future<Map<String, dynamic>> _sendEvent(
    String type, {
    String? reason,
    Track? track,
  }) async {
    final t = track ?? state.current;
    if (t == null) {
      throw ApiException('Нет активной сессии');
    }
    return _api.events(_eventBody(type, t, reason: reason));
  }

  Future<void> seek(Duration pos) async {
    await _ensurePlayer();
    final handler = _audio;
    if (handler != null) {
      await handler.seek(pos);
    } else {
      await _livePlayer!.seek(pos);
    }
    ref.read(playbackProgressProvider.notifier).update(position: pos);
    _lastPosEmit = DateTime.now();
  }

  Future<void> skip() async {
    if (_advancing) return;
    _advancing = true;
    try {
      _progressTimer?.cancel();
      await _advanceOptimistic(type: 'skip', reason: 'skipped');
    } finally {
      _advancing = false;
    }
  }

  Future<void> onCompleted() async {
    if (_advancing) return;
    _advancing = true;
    try {
      _progressTimer?.cancel();
      await _advanceOptimistic(type: 'track_end', reason: 'completed');
    } finally {
      _advancing = false;
    }
  }

  /// Play local queue[0] immediately; sync with server in parallel (LTE-friendly).
  Future<void> _advanceOptimistic({
    required String type,
    required String reason,
  }) async {
    final skipped = state.current;
    if (skipped == null) return;

    final localNext = state.queue.isNotEmpty
        ? state.queue.first.toTrack()
        : null;

    if (localNext == null || localNext.id <= 0) {
      final res = await _sendEvent(type, reason: reason, track: skipped);
      await _handleAdvance(res);
      return;
    }

    final body = _eventBody(type, skipped, reason: reason);
    final rest = state.queue.sublist(1);
    state = state.copyWith(
      current: localNext,
      queue: rest,
      loading: true,
      clearRating: true,
      clearError: true,
    );

    final playFut = _loadAndPlay(localNext);
    try {
      final res = await _api.events(body).timeout(const Duration(seconds: 20));
      await _reconcileAdvance(res, expectedId: localNext.id);
    } catch (_) {
      // Stay on local next — server sync failed (offline / timeout).
      _schedulePrefetch();
    }
    await playFut;
  }

  Future<void> _reconcileAdvance(
    Map<String, dynamic> res, {
    required int expectedId,
  }) async {
    if (res['ended'] == true) {
      await _livePlayer?.stop();
      state = state.copyWith(
        ended: true,
        playing: false,
        clearCurrent: true,
        queue: const [],
      );
      return;
    }

    Track? serverNext;
    final nextMap = res['next'];
    if (nextMap is Map) {
      serverNext = Track.fromJson(Map<String, dynamic>.from(nextMap));
    }

    final queueRaw = res['queue'];
    final queue = <QueueItem>[];
    if (queueRaw is List) {
      for (final q in queueRaw) {
        if (q is Map) {
          queue.add(QueueItem.fromJson(Map<String, dynamic>.from(q)));
        }
      }
    }

    List<Track>? playlist;
    final tracksRaw = res['tracks'];
    if (tracksRaw is List) {
      playlist = [
        for (final t in tracksRaw)
          if (t is Map) Track.fromJson(Map<String, dynamic>.from(t)),
      ];
    }

    final mode = res['mode']?.toString() ?? state.mode;
    final fixed =
        res['fixed'] == true ||
        mode == 'listen' ||
        mode == 'playlist' ||
        mode == 'daily' ||
        mode == 'favorites' ||
        mode == 'later' ||
        (playlist != null && playlist.length > 1) ||
        state.fixed;

    state = state.copyWith(
      queue: queue,
      playlist: playlist,
      mode: mode,
      fixed: fixed,
      name: res['name']?.toString(),
      clearName: res.containsKey('name'),
      maturity: res['maturity']?.toString() ?? state.maturity,
      index: (res['index'] is num)
          ? (res['index'] as num).toInt()
          : state.index,
    );

    if (serverNext != null && serverNext.id != expectedId) {
      state = state.copyWith(current: serverNext, loading: true);
      await _loadAndPlay(serverNext);
    } else {
      _schedulePrefetch();
    }
  }

  Future<void> _handleAdvance(Map<String, dynamic> res) async {
    if (res['ended'] == true) {
      await _livePlayer?.stop();
      state = state.copyWith(
        ended: true,
        playing: false,
        clearCurrent: true,
        queue: const [],
      );
      return;
    }

    Track? next;
    final nextMap = res['next'];
    if (nextMap is Map) {
      next = Track.fromJson(Map<String, dynamic>.from(nextMap));
    } else if (res['current'] is Map) {
      next = Track.fromJson(Map<String, dynamic>.from(res['current'] as Map));
    }

    final queueRaw = res['queue'];
    final queue = <QueueItem>[];
    if (queueRaw is List) {
      for (final q in queueRaw) {
        if (q is Map) {
          queue.add(QueueItem.fromJson(Map<String, dynamic>.from(q)));
        }
      }
    }

    List<Track>? playlist;
    final tracksRaw = res['tracks'];
    if (tracksRaw is List) {
      playlist = [
        for (final t in tracksRaw)
          if (t is Map) Track.fromJson(Map<String, dynamic>.from(t)),
      ];
    }

    final mode = res['mode']?.toString() ?? state.mode;
    final fixed =
        res['fixed'] == true ||
        mode == 'listen' ||
        mode == 'playlist' ||
        mode == 'daily' ||
        mode == 'favorites' ||
        mode == 'later' ||
        (playlist != null && playlist.length > 1) ||
        state.fixed;

    state = state.copyWith(
      queue: queue,
      playlist: playlist,
      mode: mode,
      fixed: fixed,
      name: res['name']?.toString(),
      clearName: res.containsKey('name'),
      maturity: res['maturity']?.toString() ?? state.maturity,
      index: (res['index'] is num)
          ? (res['index'] as num).toInt()
          : state.index,
      clearRating: true,
    );

    if (next != null) {
      // Optimistic UI while stream attaches (prefetched swap is near-instant).
      state = state.copyWith(current: next, loading: true, clearError: true);
      await _loadAndPlay(next);
    } else {
      await _livePlayer?.stop();
      state = state.copyWith(playing: false, clearCurrent: true);
    }
  }

  Future<void> jumpTo(int index) async {
    final sid = state.sessionId;
    if (sid == null) return;
    state = state.copyWith(loading: true);
    try {
      final res = await _api.sessionJump(sessionId: sid, index: index);
      await _applySession(res, play: true);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> like() async {
    state = state.copyWith(rating: ListenRating.like);
    try {
      await _sendEvent('like');
      final t = state.current;
      if (t != null) {
        await ref.read(catalogActionsProvider).toggleFavorite({
          'type': 'track',
          'track_id': t.id,
        });
      }
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> dislike() async {
    state = state.copyWith(rating: ListenRating.dislike);
    try {
      await _sendEvent('dislike');
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> toggleFavoriteArtist() async {
    final t = state.current;
    if (t == null) return;
    await ref.read(catalogActionsProvider).toggleFavorite({
      'type': 'artist',
      'artist': t.artist,
    });
  }

  Future<void> toggleFavoriteAlbum() async {
    final t = state.current;
    if (t == null || t.album == null) return;
    await ref.read(catalogActionsProvider).toggleFavorite({
      'type': 'album',
      'artist': t.artist,
      'album': t.album,
    });
  }

  Future<void> addLater() async {
    final t = state.current;
    if (t == null) return;
    await _api.laterAdd(t.id);
  }

  Future<Map<String, dynamic>> createShare() => _api.shareCreate();
}

final playbackControllerProvider =
    NotifierProvider<PlaybackController, PlaybackState>(PlaybackController.new);

/// Play/pause icon — driven by ExoPlayer stream, not stale Riverpod snapshots.
final livePlayingProvider = StreamProvider<bool>((ref) {
  ref.watch(playbackControllerProvider.select((s) => s.current?.id));
  return ref.read(playbackControllerProvider.notifier).playingChanges();
});
