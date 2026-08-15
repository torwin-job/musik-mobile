import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../data/models/models.dart';

const _filesChannel = MethodChannel('com.musik.musik_app/files');

/// Dark placeholder — avoids the white square when cover is missing/unreadable.
Uri androidDefaultArtUri() =>
    Uri.parse('android.resource://com.musik.musik_app/drawable/ic_album_art');

/// Balanced for heat: enough to start/seek, not dual 45s decode buffers.
AudioLoadConfiguration mobileAudioLoadConfiguration() =>
    const AudioLoadConfiguration(
      androidLoadControl: AndroidLoadControl(
        minBufferDuration: Duration(seconds: 10),
        maxBufferDuration: Duration(seconds: 20),
        bufferForPlaybackDuration: Duration(milliseconds: 800),
        bufferForPlaybackAfterRebufferDuration: Duration(seconds: 2),
        backBufferDuration: Duration(seconds: 20),
        prioritizeTimeOverSizeThresholds: true,
      ),
    );

AudioPlayer createMusikAudioPlayer() =>
    AudioPlayer(audioLoadConfiguration: mobileAudioLoadConfiguration());

/// System media session (notification / lock screen / headset).
/// Dual players: active for current; standby only while prefetch is held.
class MusikAudioHandler extends BaseAudioHandler with SeekHandler {
  MusikAudioHandler() {
    _bindActiveListeners();
  }

  final AudioPlayer _p0 = createMusikAudioPlayer();
  final AudioPlayer _p1 = createMusikAudioPlayer();
  int _activeIdx = 0;
  int? _preloadedTrackId;
  int _preloadGen = 0;
  DateTime? _lastBroadcast;

  StreamSubscription<PlaybackEvent>? _eventSub;
  StreamSubscription<ProcessingState>? _procSub;

  AudioPlayer get player => _activeIdx == 0 ? _p0 : _p1;
  AudioPlayer get _standby => _activeIdx == 0 ? _p1 : _p0;

  /// Called after active player swaps so UI can rebind position streams.
  VoidCallback? onActivePlayerChanged;

  Future<void> Function()? onSkipNext;
  Future<void> Function()? onCompleted;

  void _bindActiveListeners() {
    _eventSub?.cancel();
    _procSub?.cancel();
    final p = player;
    _eventSub = p.playbackEventStream.listen(_broadcastState);
    _procSub = p.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        onCompleted?.call();
      }
    });
  }

  void _swapToStandby() {
    unawaited(player.pause());
    _activeIdx = 1 - _activeIdx;
    _preloadedTrackId = null;
    _bindActiveListeners();
    onActivePlayerChanged?.call();
    // Old player is now standby — release decoder/network.
    unawaited(clearStandby());
  }

  /// Drop standby source so the second ExoPlayer is idle (less heat).
  Future<void> clearStandby() async {
    _preloadGen++;
    _preloadedTrackId = null;
    try {
      await _standby.stop();
    } catch (_) {}
  }

  @override
  Future<void> play() async {
    // just_audio's play()/pause() Futures often never complete on Android
    // when used under audio_service — fire and sync via playback events.
    unawaited(player.play());
    _emitPlaying(true);
  }

  @override
  Future<void> pause() async {
    unawaited(player.pause());
    _emitPlaying(false);
    // Second player is pure heat while paused.
    unawaited(clearStandby());
  }

  void _emitPlaying(bool playing) {
    final cur = playbackState.valueOrNull;
    final p = player;
    playbackState.add(
      (cur ?? PlaybackState()).copyWith(
        playing: playing,
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        processingState: const {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[p.processingState]!,
        updatePosition: p.position,
        bufferedPosition: p.bufferedPosition,
        speed: p.speed,
        queueIndex: 0,
      ),
    );
  }

  /// Soft stop for track switches — does NOT tear down the media session.
  Future<void> softStop() async {
    unawaited(player.pause());
    try {
      await player
          .seek(Duration.zero)
          .timeout(const Duration(milliseconds: 500));
    } catch (_) {}
    _emitPlaying(false);
  }

  @override
  Future<void> stop() async {
    await softStop();
    try {
      await player.stop();
    } catch (_) {}
    await clearStandby();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> skipToPrevious() => player.seek(Duration.zero);

  @override
  Future<void> skipToNext() async {
    final cb = onSkipNext;
    if (cb != null) {
      await cb();
    }
  }

  /// Warm the next track on the standby player (HTTP + decode buffer).
  Future<void> prefetchTrack({
    required Track track,
    required String streamUrl,
    required Map<String, String> headers,
  }) async {
    if (_preloadedTrackId == track.id) return;
    final gen = ++_preloadGen;
    _preloadedTrackId = track.id;
    try {
      await _standby
          .setAudioSource(
            AudioSource.uri(Uri.parse(streamUrl), headers: headers),
          )
          .timeout(const Duration(seconds: 20));
      if (gen != _preloadGen) return;
      try {
        await _standby.pause();
      } catch (_) {}
      // Cap standby buffer work: once ready, stop further loading if possible.
      try {
        await _standby.setVolume(0);
      } catch (_) {}
    } catch (_) {
      if (gen == _preloadGen) {
        _preloadedTrackId = null;
        try {
          await _standby.stop();
        } catch (_) {}
      }
    }
  }

  Future<void> loadTrack({
    required Track track,
    required String streamUrl,
    required Map<String, String> headers,
    Uri? artUri,
  }) async {
    final resolvedArt =
        artUri ?? (Platform.isAndroid ? androidDefaultArtUri() : null);

    final item = MediaItem(
      id: '${track.id}',
      title: track.title,
      artist: track.artist,
      album: track.album,
      duration: track.duration != null
          ? Duration(milliseconds: (track.duration! * 1000).round())
          : null,
      artUri: resolvedArt,
      playable: true,
    );
    mediaItem.add(item);

    // Hot path: next track already buffered on standby.
    if (_preloadedTrackId == track.id &&
        _standby.audioSource != null &&
        _standby.processingState != ProcessingState.idle) {
      _swapToStandby();
      try {
        await player.setVolume(1);
      } catch (_) {}
      try {
        await player
            .seek(Duration.zero)
            .timeout(const Duration(milliseconds: 400));
      } catch (_) {}
      final dur = player.duration;
      if (dur != null && mediaItem.value != null) {
        mediaItem.add(mediaItem.value!.copyWith(duration: dur));
      }
      return;
    }

    await softStop();
    // Invalidate any half-prefetched next — avoid two decoders during load.
    unawaited(clearStandby());
    await player
        .setAudioSource(AudioSource.uri(Uri.parse(streamUrl), headers: headers))
        .timeout(const Duration(seconds: 25));
    try {
      await player.setVolume(1);
    } catch (_) {}
    final dur = player.duration;
    if (dur != null && mediaItem.value != null) {
      mediaItem.add(mediaItem.value!.copyWith(duration: dur));
    }
  }

  void _broadcastState(PlaybackEvent event) {
    final p = player;
    final playing = p.playing;
    // Throttle notification/session updates — high-freq events cook the CPU.
    final now = DateTime.now();
    if (_lastBroadcast != null &&
        now.difference(_lastBroadcast!) < const Duration(milliseconds: 750) &&
        playing == (playbackState.valueOrNull?.playing ?? false)) {
      return;
    }
    _lastBroadcast = now;
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
          MediaAction.play,
          MediaAction.pause,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: const {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[p.processingState]!,
        playing: playing,
        updatePosition: p.position,
        bufferedPosition: p.bufferedPosition,
        speed: p.speed,
        queueIndex: 0,
      ),
    );
  }
}

MusikAudioHandler? _handler;

MusikAudioHandler? get musikAudioHandler => _handler;

bool get audioServiceEnabled =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS);

Future<MusikAudioHandler?> initMusikAudioService() async {
  if (!audioServiceEnabled) return null;
  if (_handler != null) return _handler;
  _handler = await AudioService.init(
    builder: MusikAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.musik.musik_app.audio',
      androidNotificationChannelName: 'musik',
      androidNotificationIcon: 'drawable/ic_stat_musik',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      // Helps SystemUI decode covers at a sane size.
      artDownscaleWidth: 256,
      artDownscaleHeight: 256,
      fastForwardInterval: Duration(seconds: 15),
      rewindInterval: Duration(seconds: 15),
    ),
  );
  return _handler;
}

/// Write cover to cache and expose a content:// URI SystemUI can read.
Future<Uri?> cacheArtFile(int trackId, List<int> bytes) async {
  try {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/musik_art_$trackId.jpg');
    await file.writeAsBytes(bytes, flush: true);

    if (Platform.isAndroid) {
      try {
        final content = await _filesChannel.invokeMethod<String>(
          'toContentUri',
          {'path': file.path},
        );
        if (content != null && content.isNotEmpty) {
          return Uri.parse(content);
        }
      } catch (_) {}
    }
    return file.uri;
  } catch (_) {
    return Platform.isAndroid ? androidDefaultArtUri() : null;
  }
}
