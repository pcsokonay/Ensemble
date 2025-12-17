enum MediaType {
  artist,
  album,
  track,
  playlist,
  radio,
  audiobook,
  chapter,
  podcast,
  podcastEpisode,
}

class ProviderMapping {
  final String itemId;
  final String providerDomain;
  final String providerInstance;
  final bool available;
  final Map<String, dynamic>? audioFormat;

  ProviderMapping({
    required this.itemId,
    required this.providerDomain,
    required this.providerInstance,
    required this.available,
    this.audioFormat,
  });

  factory ProviderMapping.fromJson(Map<String, dynamic> json) {
    return ProviderMapping(
      itemId: json['item_id'] as String? ?? '',
      providerDomain: json['provider_domain'] as String? ?? '',
      providerInstance: json['provider_instance'] as String? ?? '',
      available: json['available'] as bool? ?? true,
      audioFormat: json['audio_format'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'item_id': itemId,
      'provider_domain': providerDomain,
      'provider_instance': providerInstance,
      'available': available,
      if (audioFormat != null) 'audio_format': audioFormat,
    };
  }
}

class MediaItem {
  final String itemId;
  final String provider;
  final String name;
  final MediaType mediaType;
  final String? sortName;
  final String? uri;
  final List<ProviderMapping>? providerMappings;
  final Map<String, dynamic>? metadata;
  final bool? favorite;
  final int? position;
  final Duration? duration;

  MediaItem({
    required this.itemId,
    required this.provider,
    required this.name,
    required this.mediaType,
    this.sortName,
    this.uri,
    this.providerMappings,
    this.metadata,
    this.favorite,
    this.position,
    this.duration,
  });

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    MediaType? mediaType;
    final mediaTypeStr = json['media_type'] as String?;
    if (mediaTypeStr != null) {
      mediaType = MediaType.values.firstWhere(
        (e) => e.name == mediaTypeStr.toLowerCase(),
        orElse: () => MediaType.track,
      );
    }

    return MediaItem(
      itemId: json['item_id']?.toString() ?? json['id']?.toString() ?? '',
      provider: json['provider'] as String? ?? 'unknown',
      name: json['name'] as String? ?? '',
      mediaType: mediaType ?? MediaType.track,
      sortName: json['sort_name'] as String?,
      uri: json['uri'] as String?,
      providerMappings: (json['provider_mappings'] as List<dynamic>?)
          ?.map((e) => ProviderMapping.fromJson(e as Map<String, dynamic>))
          .toList(),
      metadata: json['metadata'] as Map<String, dynamic>?,
      favorite: json['favorite'] as bool?,
      position: json['position'] as int?,
      duration: json['duration'] != null
          ? Duration(seconds: (json['duration'] as num).toInt())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'item_id': itemId,
      'provider': provider,
      'name': name,
      'media_type': mediaType.name,
      if (sortName != null) 'sort_name': sortName,
      if (uri != null) 'uri': uri,
      if (providerMappings != null) 'provider_mappings': providerMappings,
      if (metadata != null) 'metadata': metadata,
      if (favorite != null) 'favorite': favorite,
      if (position != null) 'position': position,
      if (duration != null) 'duration': duration!.inSeconds,
    };
  }
}

class Artist extends MediaItem {
  Artist({
    required super.itemId,
    required super.provider,
    required super.name,
    super.sortName,
    super.uri,
    super.providerMappings,
    super.metadata,
    super.favorite,
  }) : super(mediaType: MediaType.artist);

  factory Artist.fromJson(Map<String, dynamic> json) {
    final item = MediaItem.fromJson(json);
    return Artist(
      itemId: item.itemId,
      provider: item.provider,
      name: item.name,
      sortName: item.sortName,
      uri: item.uri,
      providerMappings: item.providerMappings,
      metadata: item.metadata,
      favorite: item.favorite,
    );
  }

  @override
  Map<String, dynamic> toJson() => super.toJson();
}

class Album extends MediaItem {
  final List<Artist>? artists;
  final String? albumType;
  final int? year;

  Album({
    required super.itemId,
    required super.provider,
    required super.name,
    this.artists,
    this.albumType,
    this.year,
    super.sortName,
    super.uri,
    super.providerMappings,
    super.metadata,
    super.favorite,
  }) : super(mediaType: MediaType.album);

  factory Album.fromJson(Map<String, dynamic> json) {
    final item = MediaItem.fromJson(json);
    // Parse year - can be int or null
    int? year;
    final yearValue = json['year'];
    if (yearValue is int) {
      year = yearValue;
    } else if (yearValue is String) {
      year = int.tryParse(yearValue);
    }

    return Album(
      itemId: item.itemId,
      provider: item.provider,
      name: item.name,
      artists: (json['artists'] as List<dynamic>?)
          ?.map((e) => Artist.fromJson(e as Map<String, dynamic>))
          .toList(),
      albumType: json['album_type'] as String?,
      year: year,
      sortName: item.sortName,
      uri: item.uri,
      providerMappings: item.providerMappings,
      metadata: item.metadata,
      favorite: item.favorite,
    );
  }

  String get artistsString =>
      artists?.map((a) => a.name).join(', ') ?? 'Unknown Artist';

  /// Get album name with year appended (e.g., "Album Name (2023)")
  String get nameWithYear {
    return year != null ? '$name ($year)' : name;
  }

  /// Check if this album is in the user's library
  bool get inLibrary {
    if (provider == 'library') return true;
    return providerMappings?.any((m) => m.providerInstance == 'library') ?? false;
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    if (artists != null) {
      json['artists'] = artists!.map((a) => a.toJson()).toList();
    }
    if (albumType != null) json['album_type'] = albumType;
    if (year != null) json['year'] = year;
    return json;
  }
}

class Track extends MediaItem {
  final List<Artist>? artists;
  final Album? album;

  Track({
    required super.itemId,
    required super.provider,
    required super.name,
    this.artists,
    this.album,
    super.sortName,
    super.uri,
    super.providerMappings,
    super.metadata,
    super.favorite,
    super.position,
    super.duration,
  }) : super(mediaType: MediaType.track);

  factory Track.fromJson(Map<String, dynamic> json) {
    final item = MediaItem.fromJson(json);
    return Track(
      itemId: item.itemId,
      provider: item.provider,
      name: item.name,
      artists: (json['artists'] as List<dynamic>?)
          ?.map((e) => Artist.fromJson(e as Map<String, dynamic>))
          .toList(),
      album: json['album'] != null
          ? Album.fromJson(json['album'] as Map<String, dynamic>)
          : null,
      sortName: item.sortName,
      uri: item.uri,
      providerMappings: item.providerMappings,
      metadata: item.metadata,
      favorite: item.favorite,
      position: item.position,
      duration: item.duration,
    );
  }

  String get artistsString =>
      artists?.map((a) => a.name).join(', ') ?? 'Unknown Artist';

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    if (artists != null) {
      json['artists'] = artists!.map((a) => a.toJson()).toList();
    }
    if (album != null) json['album'] = album!.toJson();
    return json;
  }
}

class Playlist extends MediaItem {
  final String? owner;
  final bool? isEditable;
  final int? trackCount;

  Playlist({
    required super.itemId,
    required super.provider,
    required super.name,
    this.owner,
    this.isEditable,
    this.trackCount,
    super.sortName,
    super.uri,
    super.providerMappings,
    super.metadata,
    super.favorite,
  }) : super(mediaType: MediaType.playlist);

  factory Playlist.fromJson(Map<String, dynamic> json) {
    final item = MediaItem.fromJson(json);
    return Playlist(
      itemId: item.itemId,
      provider: item.provider,
      name: item.name,
      owner: json['owner'] as String?,
      isEditable: json['is_editable'] as bool?,
      trackCount: json['track_count'] as int?,
      sortName: item.sortName,
      uri: item.uri,
      providerMappings: item.providerMappings,
      metadata: item.metadata,
      favorite: item.favorite,
    );
  }
}

class Chapter {
  final int chapterNumber;
  final int positionMs;
  final String title;
  final Duration? duration;

  Chapter({
    required this.chapterNumber,
    required this.positionMs,
    required this.title,
    this.duration,
  });

  factory Chapter.fromJson(Map<String, dynamic> json) {
    return Chapter(
      chapterNumber: json['chapter_number'] as int? ?? json['chapter_id'] as int? ?? 0,
      positionMs: json['position_ms'] as int? ?? json['position'] as int? ?? 0,
      title: json['title'] as String? ?? 'Chapter ${json['chapter_number'] ?? 0}',
      duration: json['duration'] != null
          ? Duration(seconds: (json['duration'] as num).toInt())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'chapter_number': chapterNumber,
      'position_ms': positionMs,
      'title': title,
      if (duration != null) 'duration': duration!.inSeconds,
    };
  }
}

class Audiobook extends MediaItem {
  final List<Artist>? authors;
  final List<Artist>? narrators;
  final String? publisher;
  final String? description;
  final int? year;
  final List<Chapter>? chapters;
  final int? resumePositionMs;
  final bool? fullyPlayed;

  Audiobook({
    required super.itemId,
    required super.provider,
    required super.name,
    this.authors,
    this.narrators,
    this.publisher,
    this.description,
    this.year,
    this.chapters,
    this.resumePositionMs,
    this.fullyPlayed,
    super.sortName,
    super.uri,
    super.providerMappings,
    super.metadata,
    super.favorite,
    super.duration,
  }) : super(mediaType: MediaType.audiobook);

  factory Audiobook.fromJson(Map<String, dynamic> json) {
    final item = MediaItem.fromJson(json);

    // Parse year
    int? year;
    final yearValue = json['year'];
    if (yearValue is int) {
      year = yearValue;
    } else if (yearValue is String) {
      year = int.tryParse(yearValue);
    }

    // Helper to parse authors/narrators that can be either strings or Artist objects
    List<Artist>? parseArtistList(dynamic data) {
      if (data == null) return null;
      if (data is! List) return null;

      return data.map((e) {
        if (e is String) {
          // MA returns just the name as a string
          return Artist(
            itemId: '',
            provider: 'library',
            name: e,
          );
        } else if (e is Map<String, dynamic>) {
          // Full Artist object
          return Artist.fromJson(e);
        }
        return Artist(itemId: '', provider: 'library', name: 'Unknown');
      }).toList();
    }

    return Audiobook(
      itemId: item.itemId,
      provider: item.provider,
      name: item.name,
      authors: parseArtistList(json['authors']),
      narrators: parseArtistList(json['narrators']),
      publisher: json['publisher'] as String?,
      description: json['description'] as String?,
      year: year,
      chapters: (json['chapters'] as List<dynamic>?)
          ?.map((e) => Chapter.fromJson(e as Map<String, dynamic>))
          .toList(),
      resumePositionMs: json['resume_position_ms'] as int?,
      fullyPlayed: json['fully_played'] as bool?,
      sortName: item.sortName,
      uri: item.uri,
      providerMappings: item.providerMappings,
      metadata: item.metadata,
      favorite: item.favorite,
      duration: item.duration,
    );
  }

  String get authorsString =>
      authors?.map((a) => a.name).join(', ') ?? 'Unknown Author';

  String get narratorsString =>
      narrators?.map((n) => n.name).join(', ') ?? 'Unknown Narrator';

  /// Get progress as a percentage (0.0 to 1.0)
  double get progress {
    if (fullyPlayed == true) return 1.0;
    if (resumePositionMs == null || duration == null) return 0.0;
    final totalMs = duration!.inMilliseconds;
    if (totalMs == 0) return 0.0;
    return (resumePositionMs! / totalMs).clamp(0.0, 1.0);
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    if (authors != null) {
      json['authors'] = authors!.map((a) => a.toJson()).toList();
    }
    if (narrators != null) {
      json['narrators'] = narrators!.map((n) => n.toJson()).toList();
    }
    if (publisher != null) json['publisher'] = publisher;
    if (description != null) json['description'] = description;
    if (year != null) json['year'] = year;
    if (chapters != null) {
      json['chapters'] = chapters!.map((c) => c.toJson()).toList();
    }
    if (resumePositionMs != null) json['resume_position_ms'] = resumePositionMs;
    if (fullyPlayed != null) json['fully_played'] = fullyPlayed;
    return json;
  }
}
