import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../providers/music_assistant_provider.dart';
import '../services/settings_service.dart';

/// Displays a provider icon (SVG) from Music Assistant.
///
/// Shows a small icon in a rounded container, typically used as an overlay
/// on album art to indicate which provider the item comes from.
class ProviderIcon extends StatelessWidget {
  /// The provider domain (e.g., "spotify", "tidal", "qobuz")
  final String domain;

  /// Size of the icon container
  final double size;

  /// Whether to use dark mode icon variant
  final bool? isDark;

  const ProviderIcon({
    super.key,
    required this.domain,
    this.size = 20,
    this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final maProvider = context.read<MusicAssistantProvider>();
    final brightness = Theme.of(context).brightness;
    final useDark = isDark ?? brightness == Brightness.dark;

    final svgString = maProvider.getProviderIconSvg(domain, isDark: useDark);

    if (svgString == null || svgString.isEmpty) {
      return const SizedBox.shrink();
    }

    return SvgPicture.string(
      svgString,
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}

/// A positioned provider icon overlay for use in Stack widgets.
///
/// Typically positioned in a corner of album art.
class ProviderIconOverlay extends StatelessWidget {
  /// The provider domain (e.g., "spotify", "tidal", "qobuz")
  final String domain;

  /// Size of the icon container
  final double size;

  /// Position from the edges
  final double margin;

  const ProviderIconOverlay({
    super.key,
    required this.domain,
    this.size = 20,
    this.margin = 4,
  });

  @override
  Widget build(BuildContext context) {
    // Check if provider icons are enabled in settings
    if (!SettingsService.getShowProviderIconsSync()) {
      return const SizedBox.shrink();
    }

    return Positioned(
      right: margin,
      bottom: margin,
      child: ProviderIcon(
        domain: domain,
        size: size,
      ),
    );
  }
}
