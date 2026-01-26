import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:image/image.dart' as img;
import 'package:http/http.dart' as http;
import '../services/debug_logger.dart';

final _logger = DebugLogger();

/// Extracted adaptive colors from album art
class AdaptiveColors {
  final Color primary;       // Main accent color (vibrant)
  final Color surface;       // Background color
  final Color onSurface;     // Text color on background
  final Color miniPlayer;    // Darker version for mini player

  const AdaptiveColors({
    required this.primary,
    required this.surface,
    required this.onSurface,
    required this.miniPlayer,
  });

  static const fallback = AdaptiveColors(
    primary: Color(0xFF604CEC),
    surface: Color(0xFF121212),
    onSurface: Colors.white,
    miniPlayer: Color(0xFF1a1a1a),
  );
}

/// Data class to pass color extraction results from isolate
/// (Color objects can't be passed directly between isolates)
class _ExtractedColors {
  final int vibrantColor;
  final int lightVibrantColor;
  final int dominantColor;
  final int darkMutedColor;
  final int mutedColor;
  final int lightMutedColor;

  const _ExtractedColors({
    required this.vibrantColor,
    required this.lightVibrantColor,
    required this.dominantColor,
    required this.darkMutedColor,
    required this.mutedColor,
    required this.lightMutedColor,
  });
}

/// Helper to get contrasting text color based on background luminance
Color getContrastingTextColor(Color backgroundColor) {
  // Use relative luminance to determine if we need light or dark text
  // Standard threshold is 0.179 based on WCAG guidelines
  return backgroundColor.computeLuminance() > 0.4 ? Colors.black : Colors.white;
}

/// Top-level function for isolate-based color extraction
/// Must be top-level or static to work with compute()
_ExtractedColors? _extractColorsInIsolate(Uint8List imageBytes) {
  try {
    // Decode image using pure Dart image package
    final image = img.decodeImage(imageBytes);
    if (image == null) return null;

    // Resize for faster processing (max 100x100)
    final resized = img.copyResize(
      image,
      width: image.width > 100 ? 100 : image.width,
      height: image.height > 100 ? 100 : image.height,
      interpolation: img.Interpolation.average,
    );

    // Extract color histogram
    final colorCounts = <int, int>{};
    for (int y = 0; y < resized.height; y++) {
      for (int x = 0; x < resized.width; x++) {
        final pixel = resized.getPixel(x, y);
        // Quantize to reduce color space (shift off lower 4 bits)
        final r = (pixel.r.toInt() >> 4) << 4;
        final g = (pixel.g.toInt() >> 4) << 4;
        final b = (pixel.b.toInt() >> 4) << 4;
        final quantized = (0xFF << 24) | (r << 16) | (g << 8) | b;
        colorCounts[quantized] = (colorCounts[quantized] ?? 0) + 1;
      }
    }

    // Sort colors by frequency
    final sortedColors = colorCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (sortedColors.isEmpty) return null;

    // Categorize colors by HSL properties
    int? vibrant, lightVibrant, dominant, darkMuted, muted, lightMuted;

    for (final entry in sortedColors.take(32)) {
      final color = entry.key;
      final r = (color >> 16) & 0xFF;
      final g = (color >> 8) & 0xFF;
      final b = color & 0xFF;

      // Calculate HSL manually
      final rf = r / 255.0;
      final gf = g / 255.0;
      final bf = b / 255.0;
      final maxC = [rf, gf, bf].reduce((a, b) => a > b ? a : b);
      final minC = [rf, gf, bf].reduce((a, b) => a < b ? a : b);
      final lightness = (maxC + minC) / 2;
      final saturation = maxC == minC ? 0.0 :
          (lightness > 0.5
              ? (maxC - minC) / (2 - maxC - minC)
              : (maxC - minC) / (maxC + minC));

      // Categorize based on saturation and lightness
      if (saturation > 0.5 && lightness > 0.3 && lightness < 0.7) {
        vibrant ??= color;
      }
      if (saturation > 0.4 && lightness > 0.6) {
        lightVibrant ??= color;
      }
      if (saturation < 0.4 && lightness < 0.3) {
        darkMuted ??= color;
      }
      if (saturation < 0.4 && lightness > 0.3 && lightness < 0.7) {
        muted ??= color;
      }
      if (saturation < 0.4 && lightness > 0.7) {
        lightMuted ??= color;
      }

      // First color is dominant
      dominant ??= color;
    }

    // Fallback to dominant for any missing colors
    final defaultColor = dominant ?? sortedColors.first.key;

    return _ExtractedColors(
      vibrantColor: vibrant ?? defaultColor,
      lightVibrantColor: lightVibrant ?? vibrant ?? defaultColor,
      dominantColor: dominant ?? defaultColor,
      darkMutedColor: darkMuted ?? defaultColor,
      mutedColor: muted ?? defaultColor,
      lightMutedColor: lightMuted ?? muted ?? defaultColor,
    );
  } catch (e) {
    return null;
  }
}

class PaletteHelper {
  /// Cache for downloaded image bytes to avoid re-downloading
  static final Map<String, Uint8List> _imageCache = {};
  static const int _maxCacheSize = 20;

  /// Extract color schemes from a URL using isolate-based processing
  /// This is the preferred method as it doesn't block the main thread
  static Future<(ColorScheme, ColorScheme)?> extractColorSchemesFromUrl(String imageUrl) async {
    try {
      // Check cache first
      Uint8List? imageBytes = _imageCache[imageUrl];

      if (imageBytes == null) {
        // Download image bytes
        final response = await http.get(Uri.parse(imageUrl));
        if (response.statusCode != 200) {
          _logger.warning('Failed to download image: ${response.statusCode}', context: 'Palette');
          return null;
        }
        imageBytes = response.bodyBytes;

        // Cache the bytes
        if (_imageCache.length >= _maxCacheSize) {
          _imageCache.remove(_imageCache.keys.first);
        }
        _imageCache[imageUrl] = imageBytes;
      }

      // Extract colors in isolate
      final extractedColors = await compute(_extractColorsInIsolate, imageBytes);
      if (extractedColors == null) return null;

      // Convert to ColorSchemes on main thread
      return _buildColorSchemes(extractedColors);
    } catch (e) {
      _logger.warning('Failed to extract colors from URL: $e', context: 'Palette');
      return null;
    }
  }

  /// Build ColorSchemes from extracted color data
  static (ColorScheme, ColorScheme) _buildColorSchemes(_ExtractedColors colors) {
    // Convert int colors to Color objects
    final vibrant = Color(colors.vibrantColor);
    final lightVibrant = Color(colors.lightVibrantColor);
    final dominant = Color(colors.dominantColor);
    final darkMuted = Color(colors.darkMutedColor);
    final muted = Color(colors.mutedColor);
    final lightMuted = Color(colors.lightMutedColor);

    // Get primary color - prefer vibrant, then dominant
    Color primary = vibrant;
    if (vibrant.computeLuminance() < 0.1) {
      primary = lightVibrant;
    }
    if (primary.computeLuminance() < 0.1) {
      primary = dominant;
    }

    // Ensure primary has enough saturation
    final hslPrimary = HSLColor.fromColor(primary);
    Color adjustedPrimary = primary;
    if (hslPrimary.saturation < 0.3) {
      adjustedPrimary = hslPrimary.withSaturation(0.5).toColor();
    }
    if (adjustedPrimary.computeLuminance() < 0.15) {
      final hsl = HSLColor.fromColor(adjustedPrimary);
      adjustedPrimary = hsl.withLightness((hsl.lightness + 0.25).clamp(0.3, 0.6)).toColor();
    }

    // Build dark mode colors
    final hslDarkSurface = HSLColor.fromColor(darkMuted);
    final darkSurface = hslDarkSurface
        .withLightness((hslDarkSurface.lightness * 0.3).clamp(0.05, 0.15))
        .toColor();
    final darkMiniPlayer = hslDarkSurface
        .withLightness(0.3.clamp(0.25, 0.38))
        .withSaturation((hslDarkSurface.saturation * 1.2).clamp(0.15, 0.5))
        .toColor();

    // Build light mode colors
    final hslLightSurface = HSLColor.fromColor(lightMuted);
    final lightSurface = hslLightSurface
        .withLightness(hslLightSurface.lightness.clamp(0.92, 0.98))
        .toColor();
    final lightMiniPlayer = hslLightSurface
        .withLightness(0.75.clamp(0.65, 0.8))
        .withSaturation((hslLightSurface.saturation * 1.2).clamp(0.15, 0.5))
        .toColor();

    // Determine contrasting text colors
    final lightOnPrimary = getContrastingTextColor(adjustedPrimary);
    final darkOnPrimary = getContrastingTextColor(adjustedPrimary);
    final lightOnMiniPlayer = getContrastingTextColor(lightMiniPlayer);
    final darkOnMiniPlayer = getContrastingTextColor(darkMiniPlayer);

    // Generate secondary container colors for FilledButton.tonal
    // These must be explicitly set or Flutter auto-generates them unpredictably
    final hslForSecondary = HSLColor.fromColor(adjustedPrimary);
    final lightSecondaryContainer = hslForSecondary
        .withLightness(0.9)
        .withSaturation((hslForSecondary.saturation * 0.5).clamp(0.1, 0.3))
        .toColor();
    final darkSecondaryContainer = hslForSecondary
        .withLightness(0.25)
        .withSaturation((hslForSecondary.saturation * 0.6).clamp(0.15, 0.4))
        .toColor();

    final lightScheme = ColorScheme(
      brightness: Brightness.light,
      primary: adjustedPrimary,
      onPrimary: lightOnPrimary,
      secondary: adjustedPrimary.withOpacity(0.8),
      onSecondary: lightOnPrimary,
      secondaryContainer: lightSecondaryContainer,
      onSecondaryContainer: Colors.black87,
      error: Colors.red,
      onError: Colors.white,
      surface: lightSurface,
      onSurface: Colors.black87,
      primaryContainer: lightMiniPlayer,
      onPrimaryContainer: lightOnMiniPlayer,
    );

    final darkScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: adjustedPrimary,
      onPrimary: darkOnPrimary,
      secondary: adjustedPrimary.withOpacity(0.8),
      onSecondary: darkOnPrimary,
      secondaryContainer: darkSecondaryContainer,
      onSecondaryContainer: Colors.white,
      error: Colors.redAccent,
      onError: Colors.black,
      surface: darkSurface,
      onSurface: Colors.white,
      primaryContainer: darkMiniPlayer,
      onPrimaryContainer: darkOnMiniPlayer,
    );

    return (lightScheme, darkScheme);
  }

  /// Clear the image cache
  static void clearCache() {
    _imageCache.clear();
  }

  /// Extract a color palette from an image with higher color count for better variety
  /// NOTE: This runs on the main thread. Prefer extractColorSchemesFromUrl for better performance.
  static Future<PaletteGenerator?> extractPalette(ImageProvider imageProvider) async {
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        imageProvider,
        maximumColorCount: 32, // Increased from 20 for more color variety
      );
      return palette;
    } catch (e) {
      _logger.warning('Failed to extract palette: $e', context: 'Palette');
      return null;
    }
  }

  /// Extract actual colors from the palette (not seed-based)
  static AdaptiveColors? extractAdaptiveColors(PaletteGenerator? palette, {required bool isDark}) {
    if (palette == null) return null;

    // Get primary color - prefer vibrant, then dominant
    final Color primary = palette.vibrantColor?.color ??
                         palette.lightVibrantColor?.color ??
                         palette.dominantColor?.color ??
                         const Color(0xFF604CEC);

    // Ensure primary has enough saturation to be visually distinct
    // AND enough lightness for white text to be readable on it
    final HSLColor hslPrimary = HSLColor.fromColor(primary);
    Color adjustedPrimary = primary;

    // Adjust saturation if too low
    if (hslPrimary.saturation < 0.3) {
      adjustedPrimary = hslPrimary.withSaturation(0.5).toColor();
    }

    // Ensure minimum lightness for contrast with white text
    // If primary is too dark (luminance < 0.15), lighten it
    if (adjustedPrimary.computeLuminance() < 0.15) {
      final hsl = HSLColor.fromColor(adjustedPrimary);
      adjustedPrimary = hsl.withLightness((hsl.lightness + 0.25).clamp(0.3, 0.6)).toColor();
    }

    if (isDark) {
      // Dark mode: use dark muted colors for background
      final Color surfaceBase = palette.darkMutedColor?.color ??
                                palette.mutedColor?.color ??
                                const Color(0xFF121212);

      // Darken the surface color significantly for the expanded background
      final HSLColor hslSurface = HSLColor.fromColor(surfaceBase);
      final Color surface = hslSurface
          .withLightness((hslSurface.lightness * 0.3).clamp(0.05, 0.15))
          .toColor();

      // Mini player should be medium brightness - noticeably tinted but readable
      // Use the muted color but at medium lightness (0.25-0.35 range)
      final Color miniPlayer = hslSurface
          .withLightness(0.3.clamp(0.25, 0.38))
          .withSaturation((hslSurface.saturation * 1.2).clamp(0.15, 0.5))
          .toColor();

      return AdaptiveColors(
        primary: adjustedPrimary,
        surface: surface,
        onSurface: Colors.white,
        miniPlayer: miniPlayer,
      );
    } else {
      // Light mode: use light muted colors
      final Color surfaceBase = palette.lightMutedColor?.color ??
                                palette.mutedColor?.color ??
                                Colors.white;

      final HSLColor hslSurface = HSLColor.fromColor(surfaceBase);
      final Color surface = hslSurface
          .withLightness((hslSurface.lightness).clamp(0.92, 0.98))
          .toColor();

      // Mini player in light mode - medium tinted
      final Color miniPlayer = hslSurface
          .withLightness(0.75.clamp(0.65, 0.8))
          .withSaturation((hslSurface.saturation * 1.2).clamp(0.15, 0.5))
          .toColor();

      return AdaptiveColors(
        primary: adjustedPrimary,
        surface: surface,
        onSurface: Colors.black87,
        miniPlayer: miniPlayer,
      );
    }
  }

  /// Generate color schemes from a palette (kept for backward compatibility)
  static (ColorScheme, ColorScheme)? generateColorSchemes(PaletteGenerator? palette) {
    if (palette == null) return null;

    final lightColors = extractAdaptiveColors(palette, isDark: false);
    final darkColors = extractAdaptiveColors(palette, isDark: true);

    if (lightColors == null || darkColors == null) return null;

    // Determine contrasting text colors based on primary color luminance
    final lightOnPrimary = getContrastingTextColor(lightColors.primary);
    final darkOnPrimary = getContrastingTextColor(darkColors.primary);
    final lightOnMiniPlayer = getContrastingTextColor(lightColors.miniPlayer);
    final darkOnMiniPlayer = getContrastingTextColor(darkColors.miniPlayer);

    // Generate secondary container colors for FilledButton.tonal
    final hslLightPrimary = HSLColor.fromColor(lightColors.primary);
    final lightSecondaryContainer = hslLightPrimary
        .withLightness(0.9)
        .withSaturation((hslLightPrimary.saturation * 0.5).clamp(0.1, 0.3))
        .toColor();
    final hslDarkPrimary = HSLColor.fromColor(darkColors.primary);
    final darkSecondaryContainer = hslDarkPrimary
        .withLightness(0.25)
        .withSaturation((hslDarkPrimary.saturation * 0.6).clamp(0.15, 0.4))
        .toColor();

    final lightScheme = ColorScheme(
      brightness: Brightness.light,
      primary: lightColors.primary,
      onPrimary: lightOnPrimary,
      secondary: lightColors.primary.withOpacity(0.8),
      onSecondary: lightOnPrimary,
      secondaryContainer: lightSecondaryContainer,
      onSecondaryContainer: Colors.black87,
      error: Colors.red,
      onError: Colors.white,
      surface: lightColors.surface,
      onSurface: lightColors.onSurface,
      primaryContainer: lightColors.miniPlayer,
      onPrimaryContainer: lightOnMiniPlayer,
    );

    final darkScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: darkColors.primary,
      onPrimary: darkOnPrimary,
      secondary: darkColors.primary.withOpacity(0.8),
      onSecondary: darkOnPrimary,
      secondaryContainer: darkSecondaryContainer,
      onSecondaryContainer: Colors.white,
      error: Colors.redAccent,
      onError: Colors.black,
      surface: darkColors.surface,
      onSurface: darkColors.onSurface,
      primaryContainer: darkColors.miniPlayer,
      onPrimaryContainer: darkOnMiniPlayer,
    );

    return (lightScheme, darkScheme);
  }

  /// Extract color schemes from an image provider in one call
  /// NOTE: This runs on the main thread. Prefer extractColorSchemesFromUrl for better performance.
  static Future<(ColorScheme, ColorScheme)?> extractColorSchemes(ImageProvider imageProvider) async {
    final palette = await extractPalette(imageProvider);
    return generateColorSchemes(palette);
  }

  /// Get primary color for use in UI elements
  static Color? getPrimaryColor(PaletteGenerator? palette) {
    if (palette == null) return null;

    return palette.vibrantColor?.color ??
           palette.dominantColor?.color ??
           palette.lightVibrantColor?.color;
  }

  /// Get background color for use in UI
  static Color? getBackgroundColor(PaletteGenerator? palette, {required bool isDark}) {
    if (palette == null) return null;

    if (isDark) {
      return palette.darkMutedColor?.color ??
             palette.mutedColor?.color?.withOpacity(0.3) ??
             const Color(0xFF1a1a1a);
    } else {
      return palette.lightMutedColor?.color ??
             palette.mutedColor?.color?.withOpacity(0.9) ??
             Colors.white;
    }
  }
}
