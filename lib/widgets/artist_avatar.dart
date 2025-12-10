import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../services/metadata_service.dart';

/// A CircleAvatar that shows artist image with automatic fallback to Deezer/Fanart.tv
class ArtistAvatar extends StatefulWidget {
  final Artist artist;
  final double radius;
  final int imageSize;
  final String? heroTag;
  final ValueChanged<String?>? onImageLoaded;

  const ArtistAvatar({
    super.key,
    required this.artist,
    this.radius = 24,
    this.imageSize = 128,
    this.heroTag,
    this.onImageLoaded,
  });

  @override
  State<ArtistAvatar> createState() => _ArtistAvatarState();
}

class _ArtistAvatarState extends State<ArtistAvatar> {
  String? _imageUrl;
  bool _triedFallback = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    final provider = context.read<MusicAssistantProvider>();

    // Try MA first
    final maUrl = provider.getImageUrl(widget.artist, size: widget.imageSize);
    if (maUrl != null) {
      if (mounted) {
        setState(() {
          _imageUrl = maUrl;
        });
        widget.onImageLoaded?.call(maUrl);
      }
      return;
    }

    // Fallback to external sources
    if (!_triedFallback) {
      _triedFallback = true;
      final fallbackUrl = await MetadataService.getArtistImageUrl(widget.artist.name);
      if (fallbackUrl != null && mounted) {
        setState(() {
          _imageUrl = fallbackUrl;
        });
        widget.onImageLoaded?.call(fallbackUrl);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final avatar = CircleAvatar(
      radius: widget.radius,
      backgroundColor: colorScheme.surfaceVariant,
      backgroundImage: _imageUrl != null ? CachedNetworkImageProvider(_imageUrl!) : null,
      child: _imageUrl == null
          ? Icon(Icons.person_rounded, color: colorScheme.onSurfaceVariant)
          : null,
    );

    if (widget.heroTag != null) {
      return Hero(
        tag: widget.heroTag!,
        child: avatar,
      );
    }

    return avatar;
  }
}
