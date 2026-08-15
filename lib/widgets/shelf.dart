import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'auth_artwork.dart';

/// Horizontal shelf with title + optional «все».
class Shelf extends StatelessWidget {
  const Shelf({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.onSeeAll,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    // Wave-2 can insert shelves above existing ones. A stable subtree key
    // prevents Flutter from reusing another shelf's horizontal ScrollPosition.
    return KeyedSubtree(
      key: ValueKey('shelf:$title'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: const TextStyle(
                            color: MusikColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (onSeeAll != null)
                  TextButton(
                    onPressed: onSeeAll,
                    style: TextButton.styleFrom(
                      foregroundColor: MusikColors.accent,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('все'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

/// Cover + 1-line title + 1-line subtitle. Fixed geometry — no overflow.
class CoverCard extends StatelessWidget {
  const CoverCard({
    super.key,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.artworkPath,
    this.highlight = false,
    this.enabled = true,
  });

  static const double coverSize = 112;
  static const double width = coverSize;
  static const double height = coverSize + 8 + 18 + 2 + 16;

  final String title;
  final String? subtitle;
  final String? artworkPath;
  final bool highlight;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: width,
        height: height,
        child: Semantics(
          button: true,
          enabled: enabled,
          label: [title, if (subtitle != null) subtitle].join(', '),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: enabled ? onTap : null,
              child: Opacity(
                opacity: enabled ? 1 : 0.4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: highlight
                              ? MusikColors.accent.withValues(alpha: 0.55)
                              : MusikColors.line,
                        ),
                      ),
                      child: AuthArtwork(
                        pathOrUrl: artworkPath,
                        size: coverSize,
                        borderRadius: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle ?? ' ',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MusikColors.muted,
                        fontSize: 11,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ShelfRow extends StatelessWidget {
  const ShelfRow({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
  });

  final int itemCount;
  final NullableIndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: CoverCard.height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: itemCount,
        // Don't keep off-screen covers alive — major win with IndexedStack tabs.
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
        cacheExtent: CoverCard.width * 2,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: itemBuilder,
      ),
    );
  }
}

/// Compact track row for home / library.
class TrackRow extends StatelessWidget {
  const TrackRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.artworkPath,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final String? artworkPath;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Semantics(
        button: true,
        label: '$title, $subtitle',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Row(
              children: [
                AuthArtwork(pathOrUrl: artworkPath, size: 48, borderRadius: 8),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: MusikColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                trailing ??
                    const Icon(
                      Icons.play_arrow_rounded,
                      color: MusikColors.muted,
                      size: 22,
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
