import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../data/models/models.dart';

const _filesChannel = MethodChannel('com.musik.musik_app/files');
const _playbackLockChannel = MethodChannel('com.musik.musik_app/playback_lock');

/// Keep CPU + Wi-Fi awake while audio plays. Screen-off power save otherwise
/// freezes ExoPlayer's HTTP buffer until the display turns back on.
Future<void> _setPlaybackNetworkLock(bool hold) async {
  if (kIsWeb || !Platform.isAndroid) return;
  try {
    await _playbackLockChannel.invokeMethod<void>(hold ? 'acquire' : 'release');
  } catch (_) {}
}

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

AudioPlayer createMusikAudioPlayer() {
  final player = AudioPlayer(
    audioLoadConfiguration: mobileAudioLoadConfiguration(),
  );
  // Media usage so a new player started with the screen off is still audible.
  unawaited(
    player.setAndroidAudioAttributes(
      const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.music,
        usage: AndroidAudioUsage.media,
      ),
    ),
  );
  return player;
}

var _audioSessionReady = false;

/// Audio focus plus the radio lock. Without focus, Android keeps the timeline
/// moving on the lock screen but mutes the stream.
Future<void> _holdBackgroundAudio() async {
  unawaited(_setPlaybackNetworkLock(true));
  try {
    final session = await AudioSession.instance;
    if (!_audioSessionReady) {
      await session.configure(const AudioSessionConfiguration.music());
      _audioSessionReady = true;
    }
    await session.setActive(true);
  } catch (_) {}
}

Future<void> _releaseAudioFocus() async {
  try {
    final session = await AudioSession.instance;
    await session.setActive(false);
  } catch (_) {}
}

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

  /// Real pause/stop. Track changes must not look like a pause, or Android
  /// drops the playback service and the next song dies after its first buffer.
  var _userPaused = false;

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
    _userPaused = false;
    unawaited(_holdBackgroundAudio());
    // Volume before play, in order. A muted standby used to survive the swap
    // and the lock screen then advanced with no sound.
    unawaited(() async {
      try {
        await player.setVolume(1);
      } catch (_) {}
      try {
        await player.play();
      } catch (_) {}
    }());
    _emitPlaying(true);
  }

  @override
  Future<void> pause() async {
    _userPaused = true;
    unawaited(player.pause());
    _emitPlaying(false);
    unawaited(_releaseAudioFocus());
    unawaited(_setPlaybackNetworkLock(false));
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
  }

  @override
  Future<void> stop() async {
    _userPaused = true;
    _emitPlaying(false);
    await softStop();
    try {
      await player.stop();
    } catch (_) {}
    await clearStandby();
    await _releaseAudioFocus();
    await _setPlaybackNetworkLock(false);
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
      // Keep full volume. Muting the standby player survived the swap on a
      // locked screen, so the next track advanced with no sound.
      try {
        await _standby.setVolume(1);
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
    unawaited(_holdBackgroundAudio());

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
      _userPaused = false;
      unawaited(player.play());
      _emitPlaying(true);
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

  bool _sessionPlaying(AudioPlayer p) {
    if (_userPaused) return false;
    // End of a track is not a pause. Reporting false here makes Android drop
    // the foreground service before the next file starts loading.
    return p.playing || p.processingState == ProcessingState.completed;
  }

  void _broadcastState(PlaybackEvent event) {
    final p = player;
    final playing = _sessionPlaying(p);
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
      // Keep the foreground service and its wake lock across pauses and
      // track changes. Dropping it on a locked screen leaves the progress
      // bar moving from the last session state with no audio.
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: false,
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
