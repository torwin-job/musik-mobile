import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musik_app/data/models/models.dart';
import 'package:musik_app/domain/playback/playback_controller.dart';
import 'package:musik_app/features/library/library_page.dart';
import 'package:musik_app/features/player/player_page.dart';
import 'package:musik_app/providers/catalog_providers.dart';

void main() {
  testWidgets('library search applies after debounce', (tester) async {
    final container = ProviderContainer(
      overrides: [
        libraryCatalogProvider.overrideWith(
          (ref) async => const LibraryCatalog(
            artists: [],
            albums: [],
            tracks: [
              Track(id: 1, title: 'Alpha', artist: 'One'),
              Track(id: 2, title: 'Beta', artist: 'Two'),
            ],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: LibraryPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'alpha');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsNothing);
  });

  testWidgets('scrubber seeks once when drag ends', (tester) async {
    final container = ProviderContainer(
      overrides: [
        playbackControllerProvider.overrideWith(_FakePlaybackController.new),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(playbackProgressProvider.notifier)
        .update(
          position: const Duration(seconds: 10),
          duration: const Duration(seconds: 100),
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: PlayerScrubber())),
      ),
    );

    await tester.drag(find.byType(Slider), const Offset(180, 0));
    await tester.pump();

    final controller =
        container.read(playbackControllerProvider.notifier)
            as _FakePlaybackController;
    expect(controller.seekCalls, 1);
    expect(controller.lastSeek, isNotNull);
  });
}

class _FakePlaybackController extends PlaybackController {
  int seekCalls = 0;
  Duration? lastSeek;

  @override
  PlaybackState build() => const PlaybackState();

  @override
  Future<void> seek(Duration pos) async {
    seekCalls++;
    lastSeek = pos;
  }
}
