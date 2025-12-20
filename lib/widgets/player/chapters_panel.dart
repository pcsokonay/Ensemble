import 'package:flutter/material.dart';
import '../../providers/music_assistant_provider.dart';
import '../../models/media_item.dart' show Audiobook, Chapter;
import '../../theme/design_tokens.dart';
import '../common/empty_state.dart';
import '../../l10n/app_localizations.dart';

/// Panel that displays audiobook chapters for navigation
class ChaptersPanel extends StatelessWidget {
  final MusicAssistantProvider maProvider;
  final Audiobook? audiobook;
  final Color textColor;
  final Color primaryColor;
  final Color backgroundColor;
  final double topPadding;
  final VoidCallback onClose;

  const ChaptersPanel({
    super.key,
    required this.maProvider,
    required this.audiobook,
    required this.textColor,
    required this.primaryColor,
    required this.backgroundColor,
    required this.topPadding,
    required this.onClose,
  });

  String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final secs = duration.inSeconds % 60;

    if (hours > 0) {
      return '${hours}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '${minutes}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final chapters = audiobook?.chapters ?? [];
    final currentChapterIndex = maProvider.getCurrentChapterIndex();

    return Container(
      color: backgroundColor,
      child: Column(
        children: [
          // Header
          Container(
            padding: EdgeInsets.only(top: topPadding + 4, left: 4, right: 16),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back_rounded, color: textColor, size: IconSizes.md),
                  onPressed: onClose,
                  padding: Spacing.paddingAll12,
                ),
                const Spacer(),
                Text(
                  S.of(context)!.chapters,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                // Placeholder for symmetry
                const SizedBox(width: 48),
              ],
            ),
          ),

          // Chapters list
          Expanded(
            child: chapters.isEmpty
                ? _buildEmptyState(context)
                : _buildChaptersList(chapters, currentChapterIndex),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return EmptyState.custom(
      context: context,
      icon: Icons.bookmark_outline_rounded,
      title: S.of(context)!.noChapters,
      subtitle: S.of(context)!.noChapterInfo,
    );
  }

  Widget _buildChaptersList(List<Chapter> chapters, int currentChapterIndex) {
    return ListView.builder(
      padding: Spacing.paddingH8,
      cacheExtent: 500,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: false,
      itemCount: chapters.length,
      itemBuilder: (context, index) {
        final chapter = chapters[index];
        final isCurrentChapter = index == currentChapterIndex;
        final isPastChapter = index < currentChapterIndex;

        return RepaintBoundary(
          child: Opacity(
            opacity: isPastChapter ? 0.5 : 1.0,
            child: Container(
              margin: EdgeInsets.symmetric(vertical: Spacing.xxs),
              decoration: BoxDecoration(
                color: isCurrentChapter ? primaryColor.withOpacity(0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: ListTile(
                dense: true,
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isCurrentChapter
                        ? primaryColor.withOpacity(0.2)
                        : textColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: isCurrentChapter ? primaryColor : textColor.withOpacity(0.6),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                title: Text(
                  chapter.title,
                  style: TextStyle(
                    color: isCurrentChapter ? primaryColor : textColor,
                    fontSize: 14,
                    fontWeight: isCurrentChapter ? FontWeight.w600 : FontWeight.normal,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                        _formatDuration(chapter.positionMs ~/ 1000),
                        style: TextStyle(
                          color: textColor.withOpacity(0.5),
                          fontSize: 12,
                        ),
                      ),
                trailing: isCurrentChapter
                    ? Icon(Icons.play_arrow_rounded, color: primaryColor, size: 20)
                    : null,
                onTap: () => _seekToChapter(index),
              ),
            ),
          ),
        );
      },
    );
  }

  void _seekToChapter(int chapterIndex) {
    final player = maProvider.selectedPlayer;
    if (player == null || audiobook == null) return;

    final chapters = audiobook!.chapters;
    if (chapters == null || chapterIndex >= chapters.length) return;

    final chapter = chapters[chapterIndex];
    // Seek to the chapter's start position (positionMs is in milliseconds)
    maProvider.seek(player.playerId, (chapter.positionMs / 1000).round());
  }
}
