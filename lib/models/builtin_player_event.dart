enum BuiltinPlayerEventType {
  playMedia('play_media'),
  play('play'),
  resume('resume'),
  pause('pause'),
  stop('stop'),
  timeout('timeout'),
  mute('mute'),
  unmute('unmute'),
  setVolume('set_volume'),
  powerOff('power_off'),
  powerOn('power_on');

  final String value;
  const BuiltinPlayerEventType(this.value);

  static BuiltinPlayerEventType fromString(String value) {
    return BuiltinPlayerEventType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => BuiltinPlayerEventType.play,
    );
  }
}

class BuiltinPlayerEvent {
  final BuiltinPlayerEventType type;
  final String? mediaUrl;
  final double? volume;

  BuiltinPlayerEvent({
    required this.type,
    this.mediaUrl,
    this.volume,
  });

  factory BuiltinPlayerEvent.fromJson(Map<String, dynamic> json) {
    return BuiltinPlayerEvent(
      type: BuiltinPlayerEventType.fromString(json['type'] as String),
      mediaUrl: json['media_url'] as String?,
      volume: (json['volume'] as num?)?.toDouble(),
    );
  }
}

class BuiltinPlayerState {
  final bool powered;
  final bool playing;
  final bool paused;
  final double position; // seconds
  final double volume; // 0-100
  final bool muted;

  BuiltinPlayerState({
    required this.powered,
    required this.playing,
    required this.paused,
    required this.position,
    required this.volume,
    required this.muted,
  });

  Map<String, dynamic> toJson() {
    return {
      'powered': powered,
      'playing': playing,
      'paused': paused,
      'position': position,
      'volume': volume,
      'muted': muted,
    };
  }
}
