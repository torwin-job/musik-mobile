import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'app.dart';
import 'services/musik_audio_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Cap Flutter's decoded-image cache — home shelves used to blow past 100MB.
  PaintingBinding.instance.imageCache.maximumSize = 40;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 40 << 20; // 40 MB

  // media_kit / mpv only for desktop — on Android just_audio uses ExoPlayer.
  if (!kIsWeb && (Platform.isLinux || Platform.isWindows)) {
    JustAudioMediaKit.title = 'musik';
    JustAudioMediaKit.bufferSize = 8 * 1024 * 1024;
    JustAudioMediaKit.ensureInitialized();
  }

  // Notification + lock screen controls (Android / iOS).
  await initMusikAudioService();

  runApp(const ProviderScope(child: MusikApp()));
}
