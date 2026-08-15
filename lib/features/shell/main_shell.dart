import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../widgets/mini_player.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final _history = <int>[];

  @override
  void initState() {
    super.initState();
    _remember(widget.navigationShell.currentIndex);
  }

  @override
  void didUpdateWidget(covariant MainShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    _remember(widget.navigationShell.currentIndex);
  }

  void _remember(int index) {
    if (_history.isNotEmpty && _history.last == index) return;
    _history.remove(index);
    _history.add(index);
  }

  void _goBranch(int index) {
    _remember(index);
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  void _onPopInvoked(bool didPop, Object? result) {
    if (didPop) return;
    if (_history.length > 1) {
      _history.removeLast();
      widget.navigationShell.goBranch(_history.last);
      return;
    }
    if (widget.navigationShell.currentIndex != 0) {
      _remember(0);
      widget.navigationShell.goBranch(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final navigationShell = widget.navigationShell;
    // Hide mini-player on the full player tab — avoids duplicate controls.
    final showMini = navigationShell.currentIndex != 1;

    return PopScope(
      canPop: navigationShell.currentIndex == 0 && _history.length <= 1,
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
        body: navigationShell,
        bottomNavigationBar: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showMini) const MiniPlayer(),
              NavigationBar(
                selectedIndex: navigationShell.currentIndex,
                onDestinationSelected: _goBranch,
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home),
                    label: 'Главная',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.play_circle_outline),
                    selectedIcon: Icon(Icons.play_circle),
                    label: 'Сейчас',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.library_music_outlined),
                    selectedIcon: Icon(Icons.library_music),
                    label: 'Библиотека',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.person_outline),
                    selectedIcon: Icon(Icons.person),
                    label: 'Профиль',
                  ),
                ],
              ),
            ],
          ),
        ),
        backgroundColor: MusikColors.bg,
      ),
    );
  }
}
