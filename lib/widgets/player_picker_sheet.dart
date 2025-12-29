import 'package:flutter/material.dart';
import '../models/player.dart';
import '../l10n/app_localizations.dart';

/// A themed bottom sheet for selecting a player.
///
/// Supports adaptive theming - pass [adaptiveColorScheme] to use colors
/// extracted from album art, matching the detail screen backgrounds.
class PlayerPickerSheet extends StatelessWidget {
  final String title;
  final List<Player> players;
  final Player? selectedPlayer;
  final ColorScheme? adaptiveColorScheme;
  final Future<void> Function(Player player) onPlayerSelected;

  const PlayerPickerSheet({
    super.key,
    required this.title,
    required this.players,
    this.selectedPlayer,
    this.adaptiveColorScheme,
    required this.onPlayerSelected,
  });

  @override
  Widget build(BuildContext context) {
    final themeColorScheme = Theme.of(context).colorScheme;
    final colorScheme = adaptiveColorScheme ?? themeColorScheme;

    // Use surface container for slightly elevated look, or adaptive surface
    final backgroundColor = adaptiveColorScheme?.surface ?? themeColorScheme.surfaceContainerHigh;
    final onBackgroundColor = adaptiveColorScheme?.onSurface ?? themeColorScheme.onSurface;

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: onBackgroundColor.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: onBackgroundColor,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          const SizedBox(height: 8),

          // Player list
          if (players.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32.0),
              child: Text(
                S.of(context)!.noPlayersAvailable,
                style: TextStyle(color: onBackgroundColor.withOpacity(0.6)),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: players.length,
                itemBuilder: (context, index) {
                  final player = players[index];
                  final isSelected = selectedPlayer?.playerId == player.playerId;

                  return _PlayerTile(
                    player: player,
                    isSelected: isSelected,
                    colorScheme: colorScheme,
                    onBackgroundColor: onBackgroundColor,
                    onTap: () => onPlayerSelected(player),
                  );
                },
              ),
            ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 70),
        ],
      ),
    );
  }
}

class _PlayerTile extends StatelessWidget {
  final Player player;
  final bool isSelected;
  final ColorScheme colorScheme;
  final Color onBackgroundColor;
  final VoidCallback onTap;

  const _PlayerTile({
    required this.player,
    required this.isSelected,
    required this.colorScheme,
    required this.onBackgroundColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Status color based on player state
    Color statusColor;
    if (!player.available) {
      statusColor = Colors.grey.withOpacity(0.5);
    } else if (!player.powered) {
      statusColor = Colors.grey;
    } else if (player.state == 'playing') {
      statusColor = Colors.green;
    } else {
      statusColor = Colors.orange; // Idle/paused but powered
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: isSelected
            ? colorScheme.primaryContainer.withOpacity(0.3)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // Status indicator
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: statusColor,
                  ),
                ),
                const SizedBox(width: 12),

                // Speaker icon
                Icon(
                  Icons.speaker_rounded,
                  color: isSelected
                      ? colorScheme.primary
                      : onBackgroundColor.withOpacity(0.7),
                  size: 24,
                ),
                const SizedBox(width: 12),

                // Player name
                Expanded(
                  child: Text(
                    player.name,
                    style: TextStyle(
                      color: isSelected
                          ? colorScheme.primary
                          : onBackgroundColor,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      fontSize: 16,
                    ),
                  ),
                ),

                // Selected checkmark
                if (isSelected)
                  Icon(
                    Icons.check_circle_rounded,
                    color: colorScheme.primary,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows the player picker bottom sheet with adaptive theming.
///
/// Returns the selected player, or null if dismissed.
Future<void> showPlayerPickerSheet({
  required BuildContext context,
  required String title,
  required List<Player> players,
  Player? selectedPlayer,
  ColorScheme? adaptiveColorScheme,
  required Future<void> Function(Player player) onPlayerSelected,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => PlayerPickerSheet(
      title: title,
      players: players,
      selectedPlayer: selectedPlayer,
      adaptiveColorScheme: adaptiveColorScheme,
      onPlayerSelected: (player) async {
        Navigator.pop(context);
        await onPlayerSelected(player);
      },
    ),
  );
}
