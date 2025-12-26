import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import 'mini_player_content.dart';

/// A compact device selector bar shown when no track is playing
class DeviceSelectorBar extends StatelessWidget {
  final dynamic selectedPlayer;
  final dynamic peekPlayer;
  final bool hasMultiplePlayers;
  final Color backgroundColor;
  final Color textColor;
  final double width;
  final double height;
  final double borderRadius;
  final double slideOffset;
  final GestureDragStartCallback? onHorizontalDragStart;
  final GestureDragUpdateCallback? onHorizontalDragUpdate;
  final GestureDragEndCallback? onHorizontalDragEnd;

  const DeviceSelectorBar({
    super.key,
    required this.selectedPlayer,
    this.peekPlayer,
    required this.hasMultiplePlayers,
    required this.backgroundColor,
    required this.textColor,
    required this.width,
    required this.height,
    required this.borderRadius,
    required this.slideOffset,
    this.onHorizontalDragStart,
    this.onHorizontalDragUpdate,
    this.onHorizontalDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    final swipeHint = hasMultiplePlayers ? S.of(context)!.swipeToSwitchDevice : null;

    return GestureDetector(
      onHorizontalDragStart: hasMultiplePlayers ? onHorizontalDragStart : null,
      onHorizontalDragUpdate: hasMultiplePlayers ? onHorizontalDragUpdate : null,
      onHorizontalDragEnd: hasMultiplePlayers ? onHorizontalDragEnd : null,
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(borderRadius),
        elevation: 4,
        shadowColor: Colors.black.withOpacity(0.3),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: width,
          height: height,
          child: ClipRect(
            child: Stack(
              children: [
                // Peek player content (shows when dragging)
                if (slideOffset.abs() > 0.01 && peekPlayer != null)
                  _buildPeekContent(context, swipeHint),

                // Current player content
                MiniPlayerContent(
                  primaryText: selectedPlayer.name,
                  secondaryText: swipeHint,
                  imageUrl: null,
                  playerName: selectedPlayer.name,
                  backgroundColor: backgroundColor,
                  textColor: textColor,
                  width: width,
                  slideOffset: slideOffset,
                  isHint: swipeHint != null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Build peek player content that slides in from the edge
  Widget _buildPeekContent(BuildContext context, String? swipeHint) {
    final isFromRight = slideOffset < 0;
    final peekProgress = slideOffset.abs();

    // Calculate peek position - slides in as main content slides out
    final peekBaseOffset = isFromRight
        ? width * (1 - peekProgress)
        : -width * (1 - peekProgress);

    return Transform.translate(
      offset: Offset(peekBaseOffset, 0),
      child: MiniPlayerContent(
        primaryText: peekPlayer.name,
        secondaryText: swipeHint,
        imageUrl: null,
        playerName: peekPlayer.name,
        backgroundColor: backgroundColor,
        textColor: textColor,
        width: width,
        slideOffset: 0, // No additional slide - Transform handles positioning
        isHint: swipeHint != null,
      ),
    );
  }
}
