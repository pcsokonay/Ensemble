import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'debug_logger.dart';
import 'settings_service.dart';
import 'device_id_service.dart';

/// Connection state for Sendspin player
enum SendspinConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

/// Callback types for Sendspin events
typedef SendspinPlayCallback = void Function(String streamUrl, Map<String, dynamic> trackInfo);
typedef SendspinPauseCallback = void Function();
typedef SendspinStopCallback = void Function();
typedef SendspinSeekCallback = void Function(int positionSeconds);
typedef SendspinVolumeCallback = void Function(int volumeLevel);

/// Service to manage Sendspin WebSocket connection for local playback
/// Sendspin is the replacement for builtin_player in MA 2.7.0b20+
///
/// Connection strategy (smart fallback for external access):
/// 1. If server is HTTPS, try external wss://{server}/sendspin first
/// 2. Fall back to local_ws_url from API (ws://local-ip:8927/sendspin)
/// 3. WebRTC fallback as last resort (requires TURN servers)
class SendspinService {
  final String serverUrl;
  final _logger = DebugLogger();

  WebSocketChannel? _channel;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;

  // Connection state
  SendspinConnectionState _state = SendspinConnectionState.disconnected;
  SendspinConnectionState get state => _state;

  final _stateController = StreamController<SendspinConnectionState>.broadcast();
  Stream<SendspinConnectionState> get stateStream => _stateController.stream;

  // Player info
  String? _playerId;
  String? _playerName;
  String? _connectedUrl;

  String? get playerId => _playerId;
  String? get playerName => _playerName;

  // Event callbacks
  SendspinPlayCallback? onPlay;
  SendspinPauseCallback? onPause;
  SendspinStopCallback? onStop;
  SendspinSeekCallback? onSeek;
  SendspinVolumeCallback? onVolume;

  // Player state for reporting to server
  bool _isPowered = true;
  bool _isPlaying = false;
  bool _isPaused = false;
  int _position = 0;
  int _volume = 100;
  bool _isMuted = false;

  bool _isDisposed = false;

  SendspinService(this.serverUrl);

  /// Initialize and connect to Sendspin server
  /// Uses persistent player ID and username-based naming
  Future<bool> connect() async {
    if (_isDisposed) return false;
    if (_state == SendspinConnectionState.connected) return true;

    _updateState(SendspinConnectionState.connecting);

    try {
      // Get persistent player ID and name
      _playerId = await DeviceIdService.getOrCreateDevicePlayerId();
      _playerName = await SettingsService.getLocalPlayerName();

      _logger.log('Sendspin: Connecting as "$_playerName" (ID: $_playerId)');

      // Try connection strategies in order
      bool connected = false;

      // Strategy 1: If server is HTTPS, try external wss:// first
      if (_isHttpsServer()) {
        final externalUrl = _buildExternalSendspinUrl();
        _logger.log('Sendspin: Trying external URL: $externalUrl');
        connected = await _tryConnect(externalUrl, timeout: const Duration(seconds: 3));
      }

      // Strategy 2: If external failed or server is HTTP, try local connection
      // Note: We would need local_ws_url from getSendspinConnectionInfo API
      // For now, skip this step and fall back to WebRTC (handled by provider)

      if (!connected) {
        _logger.log('Sendspin: External connection failed, WebRTC fallback needed');
        _updateState(SendspinConnectionState.error);
        return false;
      }

      return true;
    } catch (e) {
      _logger.log('Sendspin: Connection error: $e');
      _updateState(SendspinConnectionState.error);
      return false;
    }
  }

  /// Connect with a specific WebSocket URL (called by provider with local_ws_url)
  Future<bool> connectWithUrl(String wsUrl) async {
    if (_isDisposed) return false;
    if (_state == SendspinConnectionState.connected) return true;

    _updateState(SendspinConnectionState.connecting);

    try {
      _playerId = await DeviceIdService.getOrCreateDevicePlayerId();
      _playerName = await SettingsService.getLocalPlayerName();

      _logger.log('Sendspin: Connecting with URL: $wsUrl');

      final connected = await _tryConnect(wsUrl, timeout: const Duration(seconds: 5));

      if (!connected) {
        _updateState(SendspinConnectionState.error);
        return false;
      }

      return true;
    } catch (e) {
      _logger.log('Sendspin: Connection error: $e');
      _updateState(SendspinConnectionState.error);
      return false;
    }
  }

  /// Attempt to connect to a specific WebSocket URL
  Future<bool> _tryConnect(String url, {Duration timeout = const Duration(seconds: 5)}) async {
    try {
      // Build connection URL with player info
      final uri = Uri.parse(url);
      final connectUri = uri.replace(
        queryParameters: {
          ...uri.queryParameters,
          'player_id': _playerId!,
          'player_name': _playerName!,
        },
      );

      _logger.log('Sendspin: Connecting to ${connectUri.toString()}');

      // Create WebSocket connection
      final webSocket = await WebSocket.connect(
        connectUri.toString(),
      ).timeout(timeout);

      _channel = IOWebSocketChannel(webSocket);
      _connectedUrl = url;

      // Set up message listener
      _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDone,
      );

      // Wait for server acknowledgment
      final ackReceived = await _waitForAck().timeout(
        const Duration(seconds: 3),
        onTimeout: () => false,
      );

      if (!ackReceived) {
        _logger.log('Sendspin: No acknowledgment from server');
        await _channel?.sink.close();
        _channel = null;
        return false;
      }

      _logger.log('Sendspin: Connected successfully');
      _updateState(SendspinConnectionState.connected);
      _startHeartbeat();

      return true;
    } catch (e) {
      _logger.log('Sendspin: Connection attempt failed: $e');
      return false;
    }
  }

  /// Wait for server acknowledgment after connection
  Completer<bool>? _ackCompleter;

  Future<bool> _waitForAck() async {
    _ackCompleter = Completer<bool>();
    return _ackCompleter!.future;
  }

  /// Handle incoming WebSocket messages
  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;
      final type = data['type'] as String?;

      _logger.log('Sendspin: Received message type: $type');

      switch (type) {
        case 'ack':
        case 'connected':
        case 'registered':
          // Server acknowledged our connection
          if (_ackCompleter != null && !_ackCompleter!.isCompleted) {
            _ackCompleter!.complete(true);
          }
          break;

        case 'play':
          // Server wants us to play audio
          final streamUrl = data['url'] as String?;
          final trackInfo = data['track'] as Map<String, dynamic>? ?? {};
          if (streamUrl != null && onPlay != null) {
            _isPlaying = true;
            _isPaused = false;
            onPlay!(streamUrl, trackInfo);
          }
          break;

        case 'pause':
          _isPaused = true;
          _isPlaying = false;
          onPause?.call();
          break;

        case 'stop':
          _isPlaying = false;
          _isPaused = false;
          onStop?.call();
          break;

        case 'seek':
          final position = data['position'] as int?;
          if (position != null) {
            _position = position;
            onSeek?.call(position);
          }
          break;

        case 'volume':
          final level = data['level'] as int?;
          if (level != null) {
            _volume = level;
            onVolume?.call(level);
          }
          break;

        case 'ping':
          // Respond to server ping
          _sendMessage({'type': 'pong'});
          break;

        case 'error':
          final errorMsg = data['message'] as String?;
          _logger.log('Sendspin: Server error: $errorMsg');
          break;

        default:
          _logger.log('Sendspin: Unknown message type: $type');
      }
    } catch (e) {
      _logger.log('Sendspin: Error handling message: $e');
    }
  }

  /// Handle WebSocket errors
  void _handleError(dynamic error) {
    _logger.log('Sendspin: WebSocket error: $error');
    _updateState(SendspinConnectionState.error);
    _scheduleReconnect();
  }

  /// Handle WebSocket close
  void _handleDone() {
    _logger.log('Sendspin: WebSocket closed');
    _updateState(SendspinConnectionState.disconnected);
    _scheduleReconnect();
  }

  /// Send a JSON message to the server
  void _sendMessage(Map<String, dynamic> message) {
    if (_channel == null || _state != SendspinConnectionState.connected) return;

    try {
      _channel!.sink.add(jsonEncode(message));
    } catch (e) {
      _logger.log('Sendspin: Error sending message: $e');
    }
  }

  /// Report current player state to server
  void reportState({
    bool? powered,
    bool? playing,
    bool? paused,
    int? position,
    int? volume,
    bool? muted,
  }) {
    if (powered != null) _isPowered = powered;
    if (playing != null) _isPlaying = playing;
    if (paused != null) _isPaused = paused;
    if (position != null) _position = position;
    if (volume != null) _volume = volume;
    if (muted != null) _isMuted = muted;

    _sendMessage({
      'type': 'state',
      'powered': _isPowered,
      'playing': _isPlaying,
      'paused': _isPaused,
      'position': _position,
      'volume': _volume,
      'muted': _isMuted,
    });
  }

  /// Check if server URL is HTTPS
  bool _isHttpsServer() {
    return serverUrl.startsWith('https://') ||
           serverUrl.startsWith('wss://') ||
           (!serverUrl.contains('://') && !serverUrl.contains(':'));
  }

  /// Build external Sendspin WebSocket URL from server URL
  String _buildExternalSendspinUrl() {
    var url = serverUrl;

    // Convert HTTP(S) to WS(S)
    if (url.startsWith('https://')) {
      url = 'wss://${url.substring(8)}';
    } else if (url.startsWith('http://')) {
      url = 'ws://${url.substring(7)}';
    } else if (!url.startsWith('ws://') && !url.startsWith('wss://')) {
      url = 'wss://$url';
    }

    // Remove trailing slash and add /sendspin path
    url = url.replaceAll(RegExp(r'/+$'), '');

    // Remove any existing path and add /sendspin
    final uri = Uri.parse(url);
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: '/sendspin',
    ).toString();
  }

  /// Start heartbeat timer
  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _sendMessage({'type': 'ping'});
    });
  }

  /// Stop heartbeat timer
  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Schedule reconnection attempt
  void _scheduleReconnect() {
    if (_isDisposed) return;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (!_isDisposed && _state != SendspinConnectionState.connected) {
        _logger.log('Sendspin: Attempting reconnection...');
        if (_connectedUrl != null) {
          connectWithUrl(_connectedUrl!);
        }
      }
    });
  }

  /// Update connection state
  void _updateState(SendspinConnectionState newState) {
    if (_state != newState) {
      _state = newState;
      _stateController.add(newState);
    }
  }

  /// Disconnect from server
  Future<void> disconnect() async {
    _stopHeartbeat();
    _reconnectTimer?.cancel();

    if (_channel != null) {
      _sendMessage({'type': 'disconnect'});
      await _channel!.sink.close();
      _channel = null;
    }

    _updateState(SendspinConnectionState.disconnected);
  }

  /// Dispose the service
  void dispose() {
    _isDisposed = true;
    _stopHeartbeat();
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _stateController.close();
  }
}
