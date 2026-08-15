import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Seamless cold-start surface while auth bootstrap finishes.
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: MusikColors.bg,
      body: SizedBox.expand(),
    );
  }
}
